/* eslint-disable max-len */
import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {App, deleteApp, initializeApp} from "firebase-admin/app";
import {Firestore, Timestamp, getFirestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  acceptRideForDriver,
  cancelRideForActor,
  cancelRideForPassenger,
  createRideRequestForPassenger,
  DRIVER_TRANSITIONS,
  RideLifecycleDependencies,
  transitionRideForDriver,
} from "./ride-lifecycle-orchestration.js";
import {rideOperationId} from "./ride-lifecycle-helpers.js";
import {
  buildRideMatchOffer,
  rideMatchOfferDocumentId,
} from "./ride-match-offer-helpers.js";

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
const seedDriver = async (uid: string, status = "approved") => {
  const driverId = `driver_${uid}`;
  await firestore.collection("driverProfiles").doc(driverId)
    .set({authUserId: uid, status});
  return driverId;
};
const seedMatchAuthority = async (
  driverUid: string,
  rideId: string,
  rideVersion: number,
): Promise<void> => {
  const profiles = await firestore
    .collection("driverProfiles")
    .where("authUserId", "==", driverUid)
    .limit(2)
    .get();

  if (
    profiles.size !== 1 ||
    profiles.docs[0].get("status") !== "approved"
  ) {
    return;
  }

  const driverId = profiles.docs[0].id;

  const offerRef = firestore
    .collection("driverRideMatchOffers")
    .doc(
      rideMatchOfferDocumentId(
        driverId,
        rideId,
      ),
    );

  if ((await offerRef.get()).exists) {
    return;
  }

  const now = Timestamp.now();

  const activatedAt =
    Timestamp.fromMillis(
      now.toMillis() - 60_000,
    );

  const expiresAt =
    Timestamp.fromMillis(
      now.toMillis() + 3_600_000,
    );

  const routeId =
    `authority_route_${driverId}`;

  const passRef = firestore
    .collection("driverAccessPasses")
    .doc(
      `authority_pass_${driverId}`,
    );

  const routeRef = firestore
    .collection("driverReturnRoutes")
    .doc(routeId);

  const lockRef = firestore
    .collection("driverActiveReturnRoutes")
    .doc(driverId);

  const batch = firestore.batch();

  batch.set(
    passRef,
    {
      driverId,
      status: "active",
      purchasedAt: now,
      activatedAt,
      expiresAt,
    },
  );

  batch.set(
    routeRef,
    {
      driverId,
      origin: {
        latitude: 41.0,
        longitude: 29.0,
      },
      destination: {
        latitude: 41.1,
        longitude: 29.1,
      },
      status: "active",
      createdAt: activatedAt,
      activatedAt,
      expiresAt,
      routeDistanceMeters: 12000,
      routeDurationSeconds: 1800,
      encodedPolyline:
        "synthetic_authority_polyline",
      pricingVersion: null,
    },
  );

  batch.set(
    lockRef,
    {
      routeId,
      activatedAt,
      expiresAt,
    },
  );

  batch.create(
    offerRef,
    buildRideMatchOffer({
      driverId,
      rideId,
      rideVersion,
      returnRouteId: routeId,
      routeExpiresAt: expiresAt,
      now,
      measurement: {
        pickupRouteIndex: 2,
        dropoffRouteIndex: 8,
        pickupDetourMeters: 900,
        pickupDetourSeconds: 180,
        dropoffDetourMeters: 1300,
        dropoffDetourSeconds: 260,
      },
    }),
  );

  try {
    await batch.commit();
  } catch (error: unknown) {
    if (!(await offerRef.get()).exists) {
      throw error;
    }
  }
};

const acceptForDriver = async (
  driverUid: string,
  rawInput: unknown,
) => {
  const input =
    rawInput as {
      rideId?: unknown;
      expectedVersion?: unknown;
    };

  if (
    typeof input.rideId === "string" &&
    typeof input.expectedVersion === "number" &&
    Number.isInteger(input.expectedVersion) &&
    input.expectedVersion > 0
  ) {
    await seedMatchAuthority(
      driverUid,
      input.rideId,
      input.expectedVersion,
    );
  }

  return acceptRideForDriver(
    {firestore},
    driverUid,
    rawInput,
  );
};
const acceptPayload = (rideId: string, requestId: string,
  expectedVersion = 1) => ({rideId, requestId, expectedVersion});
const createFor = async (uid: string, label: string) =>
  createRideRequestForPassenger(dependencies(), uid,
    payload(`${identity(label)}_123456789`));
const eventTypes = async (rideId: string) =>
  (await eventsFor(rideId)).docs.map((event) => event.get("type"));
const advanceToInProgress = async (passengerUid: string, driverUid: string) => {
  await seedDriver(driverUid);
  const created = await createFor(passengerUid, "lifecycle_create");
  const rideId = created.rideId as string;
  const accepted = await acceptForDriver(driverUid,
    acceptPayload(rideId, `${identity("lifecycle_accept")}_123456789`,
      created.version as number));
  const arrived = await transitionRideForDriver({firestore}, driverUid,
    acceptPayload(rideId, `${identity("lifecycle_arrive")}_123456789`,
      accepted.version as number), DRIVER_TRANSITIONS.markDriverArrived);
  const started = await transitionRideForDriver({firestore}, driverUid,
    acceptPayload(rideId, `${identity("lifecycle_start")}_123456789`,
      arrived.version as number), DRIVER_TRANSITIONS.startRide);
  return {rideId, created, accepted, arrived, started};
};

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

test("two drivers accepting one ride concurrently produce one assignment", async () => {
  const passenger = identity("accept_race_passenger");
  const driverA = identity("accept_race_driver_a");
  const driverB = identity("accept_race_driver_b");
  const [driverIdA, driverIdB] = await Promise.all([
    seedDriver(driverA), seedDriver(driverB),
  ]);
  const created = await createFor(passenger, "accept_race_create");
  const rideId = created.rideId as string;
  const results = await Promise.allSettled([
    acceptForDriver(driverA, acceptPayload(rideId,
      `${identity("accept_race_a")}_123456789`)),
    acceptForDriver(driverB, acceptPayload(rideId,
      `${identity("accept_race_b")}_123456789`)),
  ]);
  assert.equal(results.filter((item) => item.status === "fulfilled").length, 1);
  const ride = await firestore.collection("rides").doc(rideId).get();
  assert.equal(ride.get("version"), 2);
  assert.ok([driverIdA, driverIdB].includes(ride.get("driverId")));
  const pointers = await Promise.all([driverIdA, driverIdB].map((id) =>
    firestore.collection("driverActiveRides").doc(id).get()));
  assert.equal(pointers.filter((item) => item.exists).length, 1);
  assert.equal((await eventTypes(rideId)).filter((type) =>
    type === "rideDriverAccepted").length, 1);
  const loser = ride.get("driverId") === driverIdA ? driverB : driverA;
  assert.equal((await operationsFor(loser)).size, 0);
});

test("one driver accepting two rides concurrently locks only one", async () => {
  const driverUid = identity("driver_two_rides");
  const driverId = await seedDriver(driverUid);
  const first = await createFor(identity("two_rides_passenger_a"), "two_rides_create_a");
  const second = await createFor(identity("two_rides_passenger_b"), "two_rides_create_b");
  const results = await Promise.allSettled([
    acceptForDriver(driverUid, acceptPayload(first.rideId as string,
      `${identity("two_rides_accept_a")}_123456789`)),
    acceptForDriver(driverUid, acceptPayload(second.rideId as string,
      `${identity("two_rides_accept_b")}_123456789`)),
  ]);
  assert.equal(results.filter((item) => item.status === "fulfilled").length, 1);
  const rides = await Promise.all([first, second].map((item) =>
    firestore.collection("rides").doc(item.rideId as string).get()));
  assert.equal(rides.filter((ride) => ride.get("status") === "driverEnRoute").length, 1);
  assert.equal(rides.filter((ride) => ride.get("status") === "matching").length, 1);
  assert.equal(rides.filter((ride) => ride.get("driverId") === null).length, 1);
  assert.ok((await firestore.collection("driverActiveRides").doc(driverId).get()).exists);
  const loserRide = rides.find((ride) => ride.get("status") === "matching")!;
  assert.equal((await eventTypes(loserRide.id)).includes("rideDriverAccepted"), false);
});

test("same accept request replays without duplicate event", async () => {
  const passenger = identity("accept_replay_passenger");
  const driver = identity("accept_replay_driver");
  await seedDriver(driver);
  const created = await createFor(passenger, "accept_replay_create");
  const input = acceptPayload(created.rideId as string,
    `${identity("accept_replay_request")}_123456789`);
  const first = await acceptForDriver(driver, input);
  const second = await acceptForDriver(driver, input);
  assert.deepEqual(second, first);
  assert.equal((await eventTypes(created.rideId as string)).filter((type) =>
    type === "rideDriverAccepted").length, 1);
});

test("concurrent duplicate accept is exactly once", async () => {
  const passenger = identity("accept_duplicate_passenger");
  const driver = identity("accept_duplicate_driver");
  await seedDriver(driver);
  const created = await createFor(passenger, "accept_duplicate_create");
  const input = acceptPayload(created.rideId as string,
    `${identity("accept_duplicate_request")}_123456789`);
  const results = await Promise.all([
    acceptForDriver(driver, input),
    acceptForDriver(driver, input),
  ]);
  assert.deepEqual(results[1], results[0]);
  assert.equal((await eventTypes(created.rideId as string)).filter((type) =>
    type === "rideDriverAccepted").length, 1);
});

test("same accept request id with different payload is rejected", async () => {
  const driver = identity("accept_mismatch_driver");
  await seedDriver(driver);
  const first = await createFor(identity("accept_mismatch_passenger_a"),
    "accept_mismatch_create_a");
  const second = await createFor(identity("accept_mismatch_passenger_b"),
    "accept_mismatch_create_b");
  const requestId = `${identity("accept_mismatch_request")}_123456789`;
  await acceptForDriver(driver,
    acceptPayload(first.rideId as string, requestId));
  await assert.rejects(acceptForDriver(driver,
    acceptPayload(second.rideId as string, requestId)),
  (error: HttpsError) => error.code === "failed-precondition");
  assert.equal((await firestore.collection("rides").doc(second.rideId as string).get())
    .get("status"), "matching");
});

test("accept and passenger cancel with same version have one winner", async () => {
  const passenger = identity("accept_cancel_passenger");
  const driver = identity("accept_cancel_driver");
  await seedDriver(driver);
  const created = await createFor(passenger, "accept_cancel_create");
  const rideId = created.rideId as string;
  const results = await Promise.allSettled([
    acceptForDriver(driver, acceptPayload(rideId,
      `${identity("accept_cancel_accept")}_123456789`)),
    cancelRideForActor({firestore}, passenger, cancelPayload(rideId,
      `${identity("accept_cancel_cancel")}_123456789`)),
  ]);
  assert.equal(results.filter((item) => item.status === "fulfilled").length, 1);
  const ride = await firestore.collection("rides").doc(rideId).get();
  assert.equal(ride.get("version"), 2);
  assert.ok(["driverEnRoute", "cancelled"].includes(ride.get("status")));
  const transitions = (await eventTypes(rideId)).filter((type) =>
    type === "rideDriverAccepted" || type === "rideCancelled");
  assert.equal(transitions.length, 1);
});

test("arrived replay is exactly once and stale arrived is rejected", async () => {
  const passenger = identity("arrived_passenger");
  const driver = identity("arrived_driver");
  await seedDriver(driver);
  const created = await createFor(passenger, "arrived_create");
  const accepted = await acceptForDriver(driver,
    acceptPayload(created.rideId as string, `${identity("arrived_accept")}_123456789`));
  const input = acceptPayload(created.rideId as string,
    `${identity("arrived_request")}_123456789`, accepted.version as number);
  const first = await transitionRideForDriver({firestore}, driver, input,
    DRIVER_TRANSITIONS.markDriverArrived);
  assert.deepEqual(await transitionRideForDriver({firestore}, driver, input,
    DRIVER_TRANSITIONS.markDriverArrived), first);
  await assert.rejects(transitionRideForDriver({firestore}, driver,
    acceptPayload(created.rideId as string, `${identity("arrived_stale")}_123456789`,
      accepted.version as number), DRIVER_TRANSITIONS.markDriverArrived));
  assert.equal((await eventTypes(created.rideId as string)).filter((type) =>
    type === "rideDriverArrived").length, 1);
});

test("start replay is exactly once and stale start is rejected", async () => {
  const passenger = identity("start_passenger");
  const driver = identity("start_driver");
  await seedDriver(driver);
  const created = await createFor(passenger, "start_create");
  const accepted = await acceptForDriver(driver,
    acceptPayload(created.rideId as string, `${identity("start_accept")}_123456789`));
  const arrived = await transitionRideForDriver({firestore}, driver,
    acceptPayload(created.rideId as string, `${identity("start_arrive")}_123456789`,
      accepted.version as number), DRIVER_TRANSITIONS.markDriverArrived);
  const input = acceptPayload(created.rideId as string,
    `${identity("start_request")}_123456789`, arrived.version as number);
  const first = await transitionRideForDriver({firestore}, driver, input,
    DRIVER_TRANSITIONS.startRide);
  assert.deepEqual(await transitionRideForDriver({firestore}, driver, input,
    DRIVER_TRANSITIONS.startRide), first);
  await assert.rejects(transitionRideForDriver({firestore}, driver,
    acceptPayload(created.rideId as string, `${identity("start_stale")}_123456789`,
      arrived.version as number), DRIVER_TRANSITIONS.startRide));
  assert.equal((await eventTypes(created.rideId as string)).filter((type) =>
    type === "rideStarted").length, 1);
});

test("complete replay cleans pointers and emits exactly once", async () => {
  const passenger = identity("complete_passenger");
  const driver = identity("complete_driver");
  const driverId = `driver_${driver}`;
  const lifecycle = await advanceToInProgress(passenger, driver);
  const input = acceptPayload(lifecycle.rideId,
    `${identity("complete_request")}_123456789`, lifecycle.started.version as number);
  const first = await transitionRideForDriver({firestore}, driver, input,
    DRIVER_TRANSITIONS.completeRide);
  assert.deepEqual(await transitionRideForDriver({firestore}, driver, input,
    DRIVER_TRANSITIONS.completeRide), first);
  const ride = await firestore.collection("rides").doc(lifecycle.rideId).get();
  assert.equal(ride.get("status"), "completed");
  assert.equal(ride.get("version"), (lifecycle.started.version as number) + 1);
  assert.equal(ride.get("completedAt") !== null, true);
  assert.equal((await firestore.collection("passengerActiveRides").doc(passenger).get()).exists,
    false);
  assert.equal((await firestore.collection("driverActiveRides").doc(driverId).get()).exists,
    false);
  assert.equal((await eventTypes(lifecycle.rideId)).filter((type) =>
    type === "rideCompleted").length, 1);
});

test("concurrent duplicate complete is deterministic", async () => {
  const passenger = identity("complete_duplicate_passenger");
  const driver = identity("complete_duplicate_driver");
  const lifecycle = await advanceToInProgress(passenger, driver);
  const input = acceptPayload(lifecycle.rideId,
    `${identity("complete_duplicate_request")}_123456789`,
    lifecycle.started.version as number);
  const results = await Promise.all([
    transitionRideForDriver({firestore}, driver, input, DRIVER_TRANSITIONS.completeRide),
    transitionRideForDriver({firestore}, driver, input, DRIVER_TRANSITIONS.completeRide),
  ]);
  assert.deepEqual(results[1], results[0]);
  assert.equal((await eventTypes(lifecycle.rideId)).filter((type) =>
    type === "rideCompleted").length, 1);
});

test("different complete request cannot mutate terminal ride", async () => {
  const passenger = identity("complete_terminal_passenger");
  const driver = identity("complete_terminal_driver");
  const lifecycle = await advanceToInProgress(passenger, driver);
  await transitionRideForDriver({firestore}, driver,
    acceptPayload(lifecycle.rideId, `${identity("complete_terminal_first")}_123456789`,
      lifecycle.started.version as number), DRIVER_TRANSITIONS.completeRide);
  await assert.rejects(transitionRideForDriver({firestore}, driver,
    acceptPayload(lifecycle.rideId, `${identity("complete_terminal_second")}_123456789`,
      (lifecycle.started.version as number) + 1), DRIVER_TRANSITIONS.completeRide),
  (error: HttpsError) => error.code === "failed-precondition");
  assert.equal((await eventTypes(lifecycle.rideId)).filter((type) =>
    type === "rideCompleted").length, 1);
});

test("driver and passenger cancel race has one terminal transition", async () => {
  const passenger = identity("cancel_actor_race_passenger");
  const driver = identity("cancel_actor_race_driver");
  await seedDriver(driver);
  const created = await createFor(passenger, "cancel_actor_race_create");
  const accepted = await acceptForDriver(driver,
    acceptPayload(created.rideId as string, `${identity("cancel_actor_accept")}_123456789`));
  const rideId = created.rideId as string;
  const results = await Promise.allSettled([
    cancelRideForActor({firestore}, passenger, {...cancelPayload(rideId,
      `${identity("cancel_actor_passenger")}_123456789`),
    expectedVersion: accepted.version}),
    cancelRideForActor({firestore}, driver, {rideId,
      requestId: `${identity("cancel_actor_driver")}_123456789`,
      expectedVersion: accepted.version, reasonCode: "driver_cancelled"}),
  ]);
  assert.equal(results.filter((item) => item.status === "fulfilled").length, 1);
  const ride = await firestore.collection("rides").doc(rideId).get();
  assert.equal(ride.get("status"), "cancelled");
  assert.equal((await eventTypes(rideId)).filter((type) => type === "rideCancelled").length, 1);
});

test("pointer mismatch rejects transition without partial writes", async () => {
  const passenger = identity("pointer_mismatch_passenger");
  const driver = identity("pointer_mismatch_driver");
  const driverId = await seedDriver(driver);
  const created = await createFor(passenger, "pointer_mismatch_create");
  const accepted = await acceptForDriver(driver,
    acceptPayload(created.rideId as string, `${identity("pointer_mismatch_accept")}_123456789`));
  await firestore.collection("driverActiveRides").doc(driverId)
    .set({rideId: "wrong_ride", status: "driverEnRoute"});
  await assert.rejects(transitionRideForDriver({firestore}, driver,
    acceptPayload(created.rideId as string, `${identity("pointer_mismatch_arrive")}_123456789`,
      accepted.version as number), DRIVER_TRANSITIONS.markDriverArrived),
  (error: HttpsError) => error.code === "failed-precondition");
  const ride = await firestore.collection("rides").doc(created.rideId as string).get();
  assert.equal(ride.get("status"), "driverEnRoute");
  assert.equal(ride.get("version"), accepted.version);
  assert.equal((await eventTypes(ride.id)).includes("rideDriverArrived"), false);
});

test("non-driver, unapproved and non-assigned actors are rejected", async () => {
  const passenger = identity("auth_role_passenger");
  const approved = identity("auth_role_approved");
  const pending = identity("auth_role_pending");
  const stranger = identity("auth_role_stranger");
  await Promise.all([seedDriver(approved), seedDriver(pending, "pendingReview"),
    seedDriver(stranger)]);
  const created = await createFor(passenger, "auth_role_create");
  await assert.rejects(acceptForDriver(identity("auth_role_no_profile"),
    acceptPayload(created.rideId as string, `${identity("auth_role_no_profile_req")}_123456789`)));
  await assert.rejects(acceptForDriver(pending,
    acceptPayload(created.rideId as string, `${identity("auth_role_pending_req")}_123456789`)));
  const accepted = await acceptForDriver(approved,
    acceptPayload(created.rideId as string, `${identity("auth_role_accept")}_123456789`));
  await assert.rejects(transitionRideForDriver({firestore}, stranger,
    acceptPayload(created.rideId as string, `${identity("auth_role_stranger_req")}_123456789`,
      accepted.version as number), DRIVER_TRANSITIONS.markDriverArrived));
});
