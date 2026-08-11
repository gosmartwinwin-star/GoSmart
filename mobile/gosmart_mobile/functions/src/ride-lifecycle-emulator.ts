/* eslint-disable max-len */
import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {App, deleteApp, initializeApp} from "firebase-admin/app";
import {Firestore, getFirestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  cancelRideForPassenger,
  createRideRequestForPassenger,
  RideLifecycleDependencies,
} from "./ride-lifecycle-orchestration.js";
import {rideOperationId} from "./ride-lifecycle-helpers.js";

const projectId = "gosmart-ride-concurrency-test";
let firestore: Firestore;
let app: App;
let sequence = 0;

before(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error("Tests must run inside Firestore emulator.");
  }
  app = initializeApp({projectId}, `ride-concurrency-${process.pid}`);
  firestore = getFirestore(app);
});

after(async () => {
  if (app) await deleteApp(app);
});

const identity = (label: string) => {
  sequence += 1;
  return `${label}_${process.pid}_${sequence}`;
};
const payload = (requestId: string, offset = 0) => ({requestId,
  pickup: {latitude: 41 + offset, longitude: 29, addressLabel: "Pickup"},
  dropoff: {latitude: 41.1 + offset, longitude: 29.1, addressLabel: "Dropoff"}});
const cancelPayload = (rideId: string, requestId: string) => ({rideId, requestId,
  expectedVersion: 1, reasonCode: "passenger_cancelled"});
const routeProvider = (counter?: {calls: number}) => async () => {
  if (counter) counter.calls += 1;
  await new Promise((resolve) => setTimeout(resolve, 15));
  return {distanceMeters: 5000, durationSeconds: 600,
    encodedPolyline: "test_encoded_polyline"};
};
const dependencies = (counter?: {calls: number}): RideLifecycleDependencies => ({
  firestore, computeRoute: routeProvider(counter),
});
const ridesFor = (uid: string) => firestore.collection("rides")
  .where("passengerId", "==", uid).get();
const operationsFor = (uid: string) => firestore.collection("rideOperations")
  .where("actorUid", "==", uid).get();
const eventsFor = (rideId: string) => firestore.collection("rides").doc(rideId)
  .collection("events").get();
const errorCode = (reason: PromiseRejectedResult) =>
  (reason.reason as HttpsError).code;

test("two concurrent create requests allow one ride without orphans", async () => {
  const uid = identity("create_race_user");
  const firstId = `${identity("create_race_request_a")}_123456789`;
  const secondId = `${identity("create_race_request_b")}_123456789`;
  const results = await Promise.allSettled([
    createRideRequestForPassenger(dependencies(), uid, payload(firstId)),
    createRideRequestForPassenger(dependencies(), uid, payload(secondId, 0.01)),
  ]);
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  const rejected = results.find((result): result is PromiseRejectedResult =>
    result.status === "rejected");
  assert.ok(rejected);
  assert.equal(errorCode(rejected), "already-exists");
  const rides = await ridesFor(uid);
  assert.equal(rides.size, 1);
  const ride = rides.docs[0];
  assert.equal(ride.get("status"), "matching");
  assert.equal((await eventsFor(ride.id)).size, 1);
  const pointer = await firestore.collection("passengerActiveRides").doc(uid).get();
  assert.equal(pointer.get("rideId"), ride.id);
  const operations = await operationsFor(uid);
  assert.equal(operations.size, 1);
  assert.equal(operations.docs[0].get("status"), "completed");
});

test("same create request replays response without route or duplicate data", async () => {
  const uid = identity("create_replay_user");
  const requestId = `${identity("create_replay_request")}_123456789`;
  const counter = {calls: 0};
  const deps = dependencies(counter);
  const first = await createRideRequestForPassenger(deps, uid, payload(requestId));
  const second = await createRideRequestForPassenger(deps, uid, payload(requestId));
  assert.deepEqual(second, first);
  assert.equal(counter.calls, 1);
  const rides = await ridesFor(uid);
  assert.equal(rides.size, 1);
  assert.equal(rides.docs[0].get("version"), 1);
  assert.equal((await eventsFor(rides.docs[0].id)).size, 1);
  assert.equal((await operationsFor(uid)).size, 1);
  assert.equal((await firestore.collection("passengerActiveRides").doc(uid).get())
    .get("rideId"), rides.docs[0].id);
});

test("same create request id with different payload is rejected unchanged", async () => {
  const uid = identity("create_mismatch_user");
  const requestId = `${identity("create_mismatch_request")}_123456789`;
  const deps = dependencies();
  const first = await createRideRequestForPassenger(deps, uid, payload(requestId));
  await assert.rejects(
    createRideRequestForPassenger(deps, uid, payload(requestId, 0.02)),
    (error: HttpsError) => error.code === "failed-precondition" &&
      (error.details as {reason?: string}).reason === "idempotency_payload_mismatch",
  );
  const rides = await ridesFor(uid);
  assert.equal(rides.size, 1);
  assert.equal(rides.docs[0].id, first.rideId);
  assert.equal((await eventsFor(rides.docs[0].id)).size, 1);
  assert.equal((await operationsFor(uid)).size, 1);
});

test("duplicate cancel replay mutates version and event exactly once", async () => {
  const uid = identity("cancel_replay_user");
  const createId = `${identity("cancel_replay_create")}_123456789`;
  const cancelId = `${identity("cancel_replay_cancel")}_123456789`;
  const created = await createRideRequestForPassenger(dependencies(), uid,
    payload(createId));
  const input = cancelPayload(created.rideId as string, cancelId);
  const first = await cancelRideForPassenger({firestore}, uid, input);
  const second = await cancelRideForPassenger({firestore}, uid, input);
  assert.deepEqual(second, first);
  const ride = await firestore.collection("rides").doc(created.rideId as string).get();
  assert.equal(ride.get("status"), "cancelled");
  assert.equal(ride.get("version"), 2);
  const events = await eventsFor(ride.id);
  assert.equal(events.docs.filter((event) => event.get("type") === "rideCancelled").length, 1);
  assert.equal((await firestore.collection("passengerActiveRides").doc(uid).get()).exists,
    false);
  assert.equal((await operationsFor(uid)).size, 2);
});

test("concurrent duplicate cancel returns deterministic result exactly once", async () => {
  const uid = identity("cancel_concurrent_replay_user");
  const created = await createRideRequestForPassenger(dependencies(), uid,
    payload(`${identity("cancel_concurrent_create")}_123456789`));
  const input = cancelPayload(created.rideId as string,
    `${identity("cancel_concurrent_request")}_123456789`);
  const results = await Promise.all([
    cancelRideForPassenger({firestore}, uid, input),
    cancelRideForPassenger({firestore}, uid, input),
  ]);
  assert.deepEqual(results[1], results[0]);
  const ride = await firestore.collection("rides").doc(created.rideId as string).get();
  assert.equal(ride.get("version"), 2);
  assert.equal(ride.get("status"), "cancelled");
  const events = await eventsFor(ride.id);
  assert.equal(events.docs.filter((event) => event.get("type") === "rideCancelled").length, 1);
  assert.equal((await firestore.collection("passengerActiveRides").doc(uid).get()).exists,
    false);
  assert.equal((await operationsFor(uid)).size, 2);
});

test("different concurrent cancel requests produce one mutation and event", async () => {
  const uid = identity("cancel_race_user");
  const created = await createRideRequestForPassenger(dependencies(), uid,
    payload(`${identity("cancel_race_create")}_123456789`));
  const rideId = created.rideId as string;
  const results = await Promise.allSettled([
    cancelRideForPassenger({firestore}, uid, cancelPayload(rideId,
      `${identity("cancel_race_request_a")}_123456789`)),
    cancelRideForPassenger({firestore}, uid, cancelPayload(rideId,
      `${identity("cancel_race_request_b")}_123456789`)),
  ]);
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  const rejected = results.find((result): result is PromiseRejectedResult =>
    result.status === "rejected");
  assert.ok(rejected);
  assert.equal(errorCode(rejected), "failed-precondition");
  const ride = await firestore.collection("rides").doc(rideId).get();
  assert.equal(ride.get("version"), 2);
  const events = await eventsFor(rideId);
  assert.equal(events.docs.filter((event) => event.get("type") === "rideCancelled").length, 1);
  assert.equal((await operationsFor(uid)).size, 2);
});

test("stale cancel after mutation leaves canonical state unchanged", async () => {
  const uid = identity("cancel_stale_user");
  const created = await createRideRequestForPassenger(dependencies(), uid,
    payload(`${identity("cancel_stale_create")}_123456789`));
  const rideId = created.rideId as string;
  await cancelRideForPassenger({firestore}, uid, cancelPayload(rideId,
    `${identity("cancel_stale_winner")}_123456789`));
  const eventsBefore = await eventsFor(rideId);
  const losingRequestId = `${identity("cancel_stale_loser")}_123456789`;
  await assert.rejects(cancelRideForPassenger({firestore}, uid,
    cancelPayload(rideId, losingRequestId)),
  (error: HttpsError) => error.code === "failed-precondition" &&
    (error.details as {reason?: string}).reason === "stale_ride_version");
  const ride = await firestore.collection("rides").doc(rideId).get();
  assert.equal(ride.get("status"), "cancelled");
  assert.equal(ride.get("version"), 2);
  assert.equal((await eventsFor(rideId)).size, eventsBefore.size);
  assert.equal((await firestore.collection("passengerActiveRides").doc(uid).get()).exists,
    false);
  const losingOperation = await firestore.collection("rideOperations").doc(
    rideOperationId(uid, "cancelRide", losingRequestId)).get();
  assert.equal(losingOperation.exists, false);
});
