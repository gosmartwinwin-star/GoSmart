/* eslint-disable max-len */
import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {App, deleteApp, initializeApp} from "firebase-admin/app";
import {Firestore, Timestamp, getFirestore} from "firebase-admin/firestore";
import {
  buildInitialRide,
  rideOperationId,
} from "./ride-lifecycle-helpers.js";
import {
  buildRideMatchOffer,
  rideMatchOfferDocumentId,
} from "./ride-match-offer-helpers.js";

const projectId = "demo-gosmart";
const region = "europe-west1";

let app: App | undefined;
let firestore: Firestore;
let sequence = 0;

type AuthSession = {
  uid: string;
  idToken: string;
};

type JsonRecord = Record<string, unknown>;

const requiredEnvironment = (name: string): string => {
  const value = process.env[name];
  if (!value || value.trim().length === 0) {
    throw new Error(`${name} must be provided by Firebase emulators.`);
  }
  return value.trim();
};

const assertLoopbackHost = (name: string, value: string): void => {
  const normalized = value.toLowerCase();
  if (
    !normalized.startsWith("127.0.0.1:") &&
    !normalized.startsWith("localhost:") &&
    !normalized.startsWith("[::1]:")
  ) {
    throw new Error(`${name} must target a loopback emulator.`);
  }
};

const authHost = requiredEnvironment("FIREBASE_AUTH_EMULATOR_HOST");
const firestoreHost = requiredEnvironment("FIRESTORE_EMULATOR_HOST");
const functionsHost =
  process.env.FUNCTIONS_EMULATOR_HOST?.trim() || "127.0.0.1:5001";

assertLoopbackHost("FIREBASE_AUTH_EMULATOR_HOST", authHost);
assertLoopbackHost("FIRESTORE_EMULATOR_HOST", firestoreHost);
assertLoopbackHost("FUNCTIONS_EMULATOR_HOST", functionsHost);

const unique = (label: string): string => {
  sequence += 1;
  return `${label}_${process.pid}_${Date.now()}_${sequence}`;
};

const requestId = (label: string): string =>
  `${unique(label)}_1234567890123456`;

const asRecord = (value: unknown, label: string): JsonRecord => {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error(`${label} must be a JSON object.`);
  }
  return value as JsonRecord;
};

const requireString = (
  record: JsonRecord,
  field: string,
  label: string,
): string => {
  const value = record[field];
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${label}.${field} must be a non-empty string.`);
  }
  return value;
};

const signUp = async (label: string): Promise<AuthSession> => {
  const response = await fetch(
    `http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-api-key`,
    {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({
        email: `${unique(label)}@example.test`,
        password: `GoSmart_${unique("password")}_A1`,
        returnSecureToken: true,
      }),
    },
  );

  const envelope = asRecord(await response.json(), "Auth response");
  if (!response.ok) {
    const error = typeof envelope.error === "object" &&
      envelope.error !== null ?
      envelope.error as JsonRecord :
      {};
    const code = typeof error.message === "string" ?
      error.message :
      "unknown";
    throw new Error(`Auth emulator sign-up failed: ${code}`);
  }

  return {
    uid: requireString(envelope, "localId", "Auth response"),
    idToken: requireString(envelope, "idToken", "Auth response"),
  };
};

const callable = async (
  session: AuthSession,
  name: string,
  data: JsonRecord,
): Promise<JsonRecord> => {
  const response = await fetch(
    `http://${functionsHost}/${projectId}/${region}/${name}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${session.idToken}`,
      },
      body: JSON.stringify({data}),
    },
  );

  const envelope = asRecord(await response.json(), `${name} response`);

  if (!response.ok || envelope.error !== undefined) {
    const error = typeof envelope.error === "object" &&
      envelope.error !== null ?
      envelope.error as JsonRecord :
      {};
    const status = typeof error.status === "string" ?
      error.status :
      "unknown";
    throw new Error(
      `Callable ${name} failed: http=${response.status} status=${status}`,
    );
  }

  const value = Object.prototype.hasOwnProperty.call(envelope, "result") ?
    envelope.result :
    envelope.data;

  return asRecord(value, `${name} result`);
};

const activeRide = (result: JsonRecord): JsonRecord | null => {
  const value = result.activeRide;
  if (value === null) return null;
  return asRecord(value, "activeRide");
};

const expectRideState = (
  ride: JsonRecord | null,
  rideId: string,
  status: string,
  version: number,
  driverId: string | null,
): void => {
  assert.ok(ride);
  assert.equal(ride.rideId, rideId);
  assert.equal(ride.status, status);
  assert.equal(ride.version, version);
  assert.equal(ride.driverId, driverId);
};

const seedMatchingRide = async (
  passengerUid: string,
  driverUid: string,
): Promise<{rideId: string; driverId: string; offerId: string}> => {
  const rideId = unique("ride_callable");
  const driverId = unique("driver_profile");
  const now = Timestamp.now();

  const routeActivatedAt =
    Timestamp.fromMillis(
      now.toMillis() - 60_000,
    );

  const routeExpiresAt =
    Timestamp.fromMillis(
      now.toMillis() + 3_600_000,
    );

  const returnRouteId =
    unique("return_route");

  const driverPassId =
    unique("driver_pass");

  const offerId =
    rideMatchOfferDocumentId(
      driverId,
      rideId,
    );
  const pickup = {
    latitude: 41.01,
    longitude: 29.01,
    addressLabel: "Callable E2E Pickup",
  };
  const dropoff = {
    latitude: 41.02,
    longitude: 29.02,
    addressLabel: "Callable E2E Dropoff",
  };
  const route = {
    distanceMeters: 2500,
    durationSeconds: 420,
    encodedPolyline: "callable_e2e_polyline",
  };

  const rideRef = firestore.collection("rides").doc(rideId);
  const batch = firestore.batch();

  batch.set(
    firestore.collection("driverProfiles").doc(driverId),
    {
      authUserId: driverUid,
      status: "approved",
      createdAt: now,
      approvedAt: now,
      suspendedAt: null,
    },
  );

  batch.set(
    firestore
      .collection("driverAccessPasses")
      .doc(driverPassId),
    {
      driverId,
      status: "active",
      purchasedAt: now,
      activatedAt: routeActivatedAt,
      expiresAt: routeExpiresAt,
    },
  );

  batch.set(
    firestore
      .collection("driverReturnRoutes")
      .doc(returnRouteId),
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
      createdAt: routeActivatedAt,
      activatedAt: routeActivatedAt,
      expiresAt: routeExpiresAt,
      routeDistanceMeters: 12000,
      routeDurationSeconds: 1800,
      encodedPolyline:
        "callable_authority_polyline",
      pricingVersion: null,
    },
  );

  batch.set(
    firestore
      .collection("driverActiveReturnRoutes")
      .doc(driverId),
    {
      routeId: returnRouteId,
      activatedAt: routeActivatedAt,
      expiresAt: routeExpiresAt,
    },
  );

  batch.set(
    firestore
      .collection("driverRideMatchOffers")
      .doc(offerId),
    buildRideMatchOffer({
      driverId,
      rideId,
      rideVersion: 1,
      returnRouteId,
      routeExpiresAt,
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
  batch.set(
    rideRef,
    buildInitialRide(
      passengerUid,
      {
        requestId: requestId("fixture_create"),
        pickup,
        dropoff,
      },
      route,
      now,
    ),
  );

  batch.set(
    firestore.collection("passengerActiveRides").doc(passengerUid),
    {
      rideId,
      status: "matching",
      updatedAt: now,
    },
  );

  batch.set(
    rideRef.collection("events").doc(unique("rideRequestCreated_fixture")),
    {
      type: "rideRequestCreated",
      fromStatus: null,
      toStatus: "matching",
      actorType: "passenger",
      actorId: passengerUid,
      createdAt: now,
    },
  );

  await batch.commit();
  return {rideId, driverId, offerId};
};

before(() => {
  app = initializeApp(
    {projectId},
    `ride-callable-emulator-${process.pid}`,
  );
  firestore = getFirestore(app);
});

after(async () => {
  if (app) await deleteApp(app);
});

test(
  "passenger and driver auth identities traverse real callable ride lifecycle",
  async () => {
    const passenger = await signUp("passenger");
    const driver = await signUp("driver");

    assert.notEqual(passenger.uid, driver.uid);

    const fixture = await seedMatchingRide(passenger.uid, driver.uid);
    const {rideId, driverId, offerId} = fixture;

    const passengerBefore = activeRide(
      await callable(passenger, "getMyActiveRide", {}),
    );
    expectRideState(passengerBefore, rideId, "matching", 1, null);

    const driverBefore = activeRide(
      await callable(driver, "getMyActiveDriverRide", {}),
    );
    assert.equal(driverBefore, null);

    const acceptRequestId = requestId("accept");
    const accepted = await callable(driver, "acceptRide", {
      rideId,
      requestId: acceptRequestId,
      expectedVersion: 1,
    });
    assert.equal(accepted.status, "driverEnRoute");
    assert.equal(accepted.version, 2);
    const consumedOffer = await firestore
      .collection("driverRideMatchOffers")
      .doc(offerId)
      .get();

    assert.equal(
      consumedOffer.get("status"),
      "consumed",
    );

    assert.ok(
      consumedOffer.get("consumedAt") instanceof
        Timestamp,
    );

    const passengerAccepted = activeRide(
      await callable(passenger, "getMyActiveRide", {}),
    );
    expectRideState(
      passengerAccepted,
      rideId,
      "driverEnRoute",
      2,
      driverId,
    );

    const driverAccepted = activeRide(
      await callable(driver, "getMyActiveDriverRide", {}),
    );
    expectRideState(
      driverAccepted,
      rideId,
      "driverEnRoute",
      2,
      driverId,
    );

    const arriveRequestId = requestId("arrive");
    const arrived = await callable(driver, "markDriverArrived", {
      rideId,
      requestId: arriveRequestId,
      expectedVersion: 2,
    });
    assert.equal(arrived.status, "driverArrived");
    assert.equal(arrived.version, 3);

    const startRequestId = requestId("start");
    const started = await callable(driver, "startRide", {
      rideId,
      requestId: startRequestId,
      expectedVersion: 3,
    });
    assert.equal(started.status, "inProgress");
    assert.equal(started.version, 4);

    const completeRequestId = requestId("complete");
    const completed = await callable(driver, "completeRide", {
      rideId,
      requestId: completeRequestId,
      expectedVersion: 4,
    });
    assert.equal(completed.status, "completed");
    assert.equal(completed.version, 5);

    assert.equal(
      activeRide(await callable(passenger, "getMyActiveRide", {})),
      null,
    );
    assert.equal(
      activeRide(await callable(driver, "getMyActiveDriverRide", {})),
      null,
    );

    const finalRide = await firestore.collection("rides").doc(rideId).get();
    assert.equal(finalRide.exists, true);
    assert.equal(finalRide.get("passengerId"), passenger.uid);
    assert.equal(finalRide.get("driverId"), driverId);
    assert.equal(finalRide.get("status"), "completed");
    assert.equal(finalRide.get("version"), 5);
    assert.ok(finalRide.get("completedAt") instanceof Timestamp);

    const passengerPointer = await firestore
      .collection("passengerActiveRides")
      .doc(passenger.uid)
      .get();
    const driverPointer = await firestore
      .collection("driverActiveRides")
      .doc(driverId)
      .get();

    assert.equal(passengerPointer.exists, false);
    assert.equal(driverPointer.exists, false);

    const eventSnapshot = await firestore
      .collection("rides")
      .doc(rideId)
      .collection("events")
      .get();

    const eventTypes = eventSnapshot.docs
      .map((document) => document.get("type"))
      .sort();

    assert.deepEqual(eventTypes, [
      "rideCompleted",
      "rideDriverAccepted",
      "rideDriverArrived",
      "rideRequestCreated",
      "rideStarted",
    ].sort());

    for (const [callableName, mutationRequestId] of [
      ["acceptRide", acceptRequestId],
      ["markDriverArrived", arriveRequestId],
      ["startRide", startRequestId],
      ["completeRide", completeRequestId],
    ] as const) {
      const operation = await firestore
        .collection("rideOperations")
        .doc(rideOperationId(driver.uid, callableName, mutationRequestId))
        .get();

      assert.equal(
        operation.exists,
        true,
        `${callableName} operation must exist`,
      );
      assert.equal(operation.get("actorUid"), driver.uid);
      assert.equal(operation.get("callableName"), callableName);
      assert.equal(operation.get("status"), "completed");
    }
  },
);
/* eslint-enable max-len */
