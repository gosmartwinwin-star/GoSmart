import assert from "node:assert/strict";
/* eslint-disable max-len */
import {readFileSync} from "node:fs";
import test from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  buildInitialRide,
  parseRideStatus,
  requirePassengerCancellation,
  requirePositiveVersion,
  rideOperationId,
  rideRequestDigest,
  serializeActiveRide,
  validateCancelRidePayload,
  validateCreateRideRequestPayload,
  validateRequestId,
} from "./ride-lifecycle-helpers.js";

const reason = (callback: () => unknown) => {
  try {
    callback();
    return null;
  } catch (error) {
    return ((error as HttpsError).details as {reason?: string} | undefined)?.reason;
  }
};
const createPayload = (extra: Record<string, unknown> = {}) => ({
  requestId: "request_123456789", pickup: {latitude: 41, longitude: 29,
    addressLabel: "Pickup"}, dropoff: {latitude: 41.1, longitude: 29.1,
    addressLabel: "Dropoff"}, ...extra,
});

test("canonical ride statuses parse and unknown status fails closed", () => {
  for (const status of ["matching", "driverEnRoute", "driverArrived", "inProgress",
    "completed", "cancelled", "expired"]) {
    assert.equal(parseRideStatus(status), status);
  }
  assert.equal(reason(() => parseRideStatus("accepted")), "ride_data_invalid");
});

test("create payload is exact and validates locations", () => {
  assert.deepEqual(validateCreateRideRequestPayload(createPayload()), createPayload());
  assert.equal(reason(() => validateCreateRideRequestPayload(
    createPayload({passengerId: "injected"}))), "invalid_create_ride_payload");
  assert.equal(reason(() => validateCreateRideRequestPayload(
    createPayload({status: "completed"}))), "invalid_create_ride_payload");
  assert.equal(reason(() => validateCreateRideRequestPayload(
    createPayload({route: {distanceMeters: 1}}))), "invalid_create_ride_payload");
  assert.equal(reason(() => validateCreateRideRequestPayload(createPayload({pickup:
    {latitude: 91, longitude: 29, addressLabel: "Pickup"}}))), "invalid_pickup");
  assert.equal(reason(() => validateCreateRideRequestPayload(createPayload({dropoff:
    {latitude: 41, longitude: 181, addressLabel: "Dropoff"}}))), "invalid_dropoff");
  assert.equal(reason(() => validateCreateRideRequestPayload(createPayload({pickup:
    {latitude: 41, longitude: 29, addressLabel: ""}}))), "invalid_pickup");
  assert.equal(reason(() => validateCreateRideRequestPayload(createPayload({pickup:
    {latitude: 41, longitude: 29, addressLabel: "Pickup\nInjected"}}))),
  "invalid_pickup");
});

test("create rejects identical coordinates and nested unknown fields", () => {
  assert.equal(reason(() => validateCreateRideRequestPayload(createPayload({dropoff:
    {latitude: 41, longitude: 29, addressLabel: "Other"}}))),
  "identical_ride_locations");
  assert.equal(reason(() => validateCreateRideRequestPayload(createPayload({pickup:
    {latitude: 41, longitude: 29, addressLabel: "Pickup", uid: "x"}}))),
  "invalid_pickup");
});

test("request id format is bounded and path safe", () => {
  assert.equal(validateRequestId("request_123456789"), "request_123456789");
  for (const value of ["short", "request with space", "../../request_123456789",
    "x".repeat(129)]) {
    assert.equal(reason(() => validateRequestId(value)), "invalid_request_id");
  }
});

test("cancel payload is exact with controlled version and reason", () => {
  const input = {rideId: "ride_123", requestId: "request_123456789",
    expectedVersion: 1, reasonCode: "passenger_cancelled"};
  assert.deepEqual(validateCancelRidePayload(input), input);
  assert.equal(reason(() => validateCancelRidePayload({...input, driverId: "x"})),
    "invalid_cancel_ride_payload");
  assert.equal(reason(() => validateCancelRidePayload({...input, expectedVersion: 0})),
    "invalid_ride_version");
  assert.equal(reason(() => validateCancelRidePayload({...input, reasonCode: "free_text"})),
    "invalid_cancellation_reason");
});

test("passenger cancellation policy allows only pre-start states", () => {
  for (const status of ["matching", "driverEnRoute", "driverArrived"] as const) {
    assert.doesNotThrow(() => requirePassengerCancellation(status));
  }
  assert.equal(reason(() => requirePassengerCancellation("inProgress")),
    "ride_cannot_be_cancelled");
  for (const status of ["completed", "cancelled", "expired"] as const) {
    assert.equal(reason(() => requirePassengerCancellation(status)), "ride_is_terminal");
  }
});

test("initial ride contract is server-derived and version one", () => {
  const input = validateCreateRideRequestPayload(createPayload());
  const now = Timestamp.fromMillis(1000);
  const ride = buildInitialRide("user-a", input,
    {distanceMeters: 100, durationSeconds: 20, encodedPolyline: "abc"}, now);
  assert.equal(ride.passengerId, "user-a");
  assert.equal(ride.status, "matching");
  assert.equal(ride.version, 1);
  assert.equal(ride.driverId, null);
  assert.equal(ride.route.computedAt, now);
  assert.equal(ride.cancelledAt, null);
});

test("versions and idempotency identifiers are strict and deterministic", () => {
  assert.equal(requirePositiveVersion(1), 1);
  assert.equal(reason(() => requirePositiveVersion(0)), "ride_data_invalid");
  const first = rideOperationId("user-a", "cancelRide", "request_123456789");
  assert.match(first, /^[a-f0-9]{64}$/u);
  assert.equal(first, rideOperationId("user-a", "cancelRide", "request_123456789"));
  assert.notEqual(first, rideOperationId("user-a", "createRideRequest",
    "request_123456789"));
  assert.equal(rideRequestDigest("createRideRequest", createPayload()),
    rideRequestDigest("createRideRequest", {dropoff: createPayload().dropoff,
      pickup: createPayload().pickup, requestId: "request_123456789"}));
  assert.notEqual(rideRequestDigest("createRideRequest", createPayload()),
    rideRequestDigest("createRideRequest", createPayload({dropoff:
      {latitude: 42, longitude: 30, addressLabel: "Other"}})));
});

test("active ride serialization is safe and omits passenger/internal fields", () => {
  const now = Timestamp.fromMillis(1000);
  const data = buildInitialRide("user-a",
    validateCreateRideRequestPayload(createPayload()),
    {distanceMeters: 100, durationSeconds: 20, encodedPolyline: "abc"}, now);
  const result = serializeActiveRide("ride-a", data);
  const serialized = JSON.stringify(result);
  assert.equal(result.rideId, "ride-a");
  for (const forbidden of ["passengerId", "requestDigest", "actorUid",
    "callableName"]) assert.equal(serialized.includes(forbidden), false);
});

test("ride callables preserve auth, transactions, locks and events", () => {
  const source = readFileSync("src/index.ts", "utf8");
  const orchestration = readFileSync("src/ride-lifecycle-orchestration.ts", "utf8");
  const create = source.slice(source.indexOf("export const createRideRequest"),
    source.indexOf("export const getMyActiveRide"));
  const read = source.slice(source.indexOf("export const getMyActiveRide"),
    source.indexOf("export const cancelRide"));
  const cancel = source.slice(source.indexOf("export const cancelRide"),
    source.indexOf("export const getMyDriverApplicationStatus"));
  assert.match(create, /if \(!request\.auth\)/u);
  assert.match(create, /createRideRequestForPassenger/u);
  assert.match(create, /computeRoute: computePublishedRoute/u);
  assert.doesNotMatch(create, /request\.data\.(uid|passengerId|status|version|route)/u);
  assert.match(read, /activeRide: null/u);
  assert.doesNotMatch(read, /events.*create|rideRequestCreated|rideCancelled/u);
  assert.match(cancel, /cancelRideForActor/u);
  assert.match(orchestration, /expectedVersion/u);
  assert.match(orchestration, /passengerActiveRides/u);
  assert.match(orchestration, /runTransaction/u);
  assert.match(orchestration, /rideRequestCreated/u);
  assert.match(orchestration, /rideOperations/u);
  assert.match(orchestration, /transaction\.delete\(passengerActiveRef\)/u);
  assert.match(orchestration, /rideCancelled/u);
  assert.match(orchestration, /operationData\.result/u);
});
