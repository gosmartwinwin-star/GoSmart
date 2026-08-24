/* eslint-disable max-len */
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  requireDriverCancellation,
  requirePassengerCancellation,
  requireRideTransition,
  validateCancelRidePayload,
  validateRideMutationPayload,
} from "./ride-lifecycle-helpers.js";

const reason = (callback: () => unknown) => {
  try {
    callback();
    return null;
  } catch (error) {
    return ((error as HttpsError).details as {reason?: string} | undefined)?.reason;
  }
};
const mutation = {rideId: "ride_123", requestId: "request_123456789",
  expectedVersion: 1};

test("canonical driver transitions allow only their exact source state", () => {
  assert.doesNotThrow(() => requireRideTransition("matching", "matching"));
  assert.doesNotThrow(() => requireRideTransition("driverEnRoute", "driverEnRoute"));
  assert.doesNotThrow(() => requireRideTransition("driverArrived", "driverArrived"));
  assert.doesNotThrow(() => requireRideTransition("inProgress", "inProgress"));
  assert.equal(reason(() => requireRideTransition("matching", "driverEnRoute")),
    "invalid_ride_transition");
});

test("terminal states are immutable for driver transitions", () => {
  for (const status of ["completed", "cancelled", "expired"] as const) {
    assert.equal(reason(() => requireRideTransition(status, "inProgress")),
      "ride_is_terminal");
  }
});

test("driver cancellation permits only assigned pre-start states", () => {
  assert.doesNotThrow(() => requireDriverCancellation("driverEnRoute"));
  assert.doesNotThrow(() => requireDriverCancellation("driverArrived"));
  assert.equal(reason(() => requireDriverCancellation("matching")),
    "ride_cannot_be_cancelled");
  assert.equal(reason(() => requireDriverCancellation("inProgress")),
    "ride_cannot_be_cancelled");
});

test("passenger cancellation policy remains unchanged", () => {
  for (const status of ["matching", "driverEnRoute", "driverArrived"] as const) {
    assert.doesNotThrow(() => requirePassengerCancellation(status));
  }
  assert.equal(reason(() => requirePassengerCancellation("inProgress")),
    "ride_cannot_be_cancelled");
});

test("driver mutation payload is exact and versioned", () => {
  assert.deepEqual(validateRideMutationPayload(mutation), mutation);
  assert.equal(reason(() => validateRideMutationPayload({...mutation, driverId: "x"})),
    "invalid_ride_mutation_payload");
  assert.equal(reason(() => validateRideMutationPayload({...mutation, expectedVersion: 0})),
    "invalid_ride_version");
  assert.equal(reason(() => validateRideMutationPayload({...mutation, requestId: "short"})),
    "invalid_request_id");
});

test("cancel reason codes are controlled without actor input", () => {
  assert.equal(validateCancelRidePayload({...mutation,
    reasonCode: "passenger_cancelled"}).reasonCode, "passenger_cancelled");
  assert.equal(validateCancelRidePayload({...mutation,
    reasonCode: "driver_cancelled"}).reasonCode, "driver_cancelled");
  assert.equal(reason(() => validateCancelRidePayload({...mutation,
    reasonCode: "free_text"})), "invalid_cancellation_reason");
  assert.equal(reason(() => validateCancelRidePayload({...mutation,
    reasonCode: "driver_cancelled", actorType: "driver"})),
  "invalid_cancel_ride_payload");
});

test("driver callable wrappers enforce auth and delegate domain logic", () => {
  const source = readFileSync("src/index.ts", "utf8");
  for (const name of ["acceptRide", "markDriverArrived", "startRide", "completeRide"]) {
    const start = source.indexOf(`export const ${name}`);
    assert.ok(start >= 0);
    const body = source.slice(start, source.indexOf("export const", start + 20));
    assert.match(body, /if \(!request\.auth\)/u);
    assert.doesNotMatch(body, /request\.data\.(driverId|uid|actorType)/u);
  }
});
