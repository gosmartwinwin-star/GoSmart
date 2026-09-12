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
        password: `YoldaAl_${unique("password")}_A1`,
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
    const details = typeof error.details === "object" &&
      error.details !== null ?
      error.details as JsonRecord :
      {};
    const reason = typeof details.reason === "string" ?
      details.reason :
      "unknown";
    throw new Error(
      `Callable ${name} failed: http=${response.status} status=${status} reason=${reason}`,
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
      1,
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

const seedDriverPlanPurchaseFixture = async (
  driverUid: string,
): Promise<{
  driverId: string;
  catalogVersion: string;
  amountMinor: number;
  currency: string;
}> => {
  const driverId = unique("purchase_driver_profile");
  const catalogVersion = unique("driver_plan_catalog");
  const amountMinor = 1234;
  const currency = "EUR";
  const now = Timestamp.now();

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
    firestore.collection("platformConfig").doc("driverPlanCatalog"),
    {
      catalogVersion,
      plans: {
        daily: {
          enabled: true,
          amountMinor,
          currency,
        },
        weekly: {
          enabled: true,
          amountMinor: 2345,
          currency,
        },
        monthly: {
          enabled: true,
          amountMinor: 3456,
          currency,
        },
        quarterly: {
          enabled: true,
          amountMinor: 4567,
          currency,
        },
      },
    },
  );

  await batch.commit();

  return {
    driverId,
    catalogVersion,
    amountMinor,
    currency,
  };
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
test(
  "mutual ride rating callable persists exactly one immutable rating per participant",
  async () => {
    const passenger = await signUp("rating_passenger");
    const driver = await signUp("rating_driver");
    const outsider = await signUp("rating_outsider");

    const fixture =
      await seedMatchingRide(passenger.uid, driver.uid);

    const {rideId, driverId} = fixture;

    await callable(driver, "acceptRide", {
      rideId,
      requestId: requestId("rating_accept"),
      expectedVersion: 1,
    });

    await callable(driver, "markDriverArrived", {
      rideId,
      requestId: requestId("rating_arrive"),
      expectedVersion: 2,
    });

    await callable(driver, "startRide", {
      rideId,
      requestId: requestId("rating_start"),
      expectedVersion: 3,
    });

    await assert.rejects(
      () =>
        callable(passenger, "getMyRideRatingStatus", {
          rideId,
        }),
      /status=FAILED_PRECONDITION/u,
    );
    await assert.rejects(
      () =>
        callable(passenger, "submitRideRating", {
          rideId,
          rating: 5,
          requestId: requestId("rating_before_complete"),
        }),
      /status=FAILED_PRECONDITION/u,
    );

    await callable(driver, "completeRide", {
      rideId,
      requestId: requestId("rating_complete"),
      expectedVersion: 4,
    });

    const parentBeforeRating =
      await firestore.collection("rides").doc(rideId).get();

    assert.equal(parentBeforeRating.exists, true);
    assert.equal(parentBeforeRating.get("status"), "completed");
    assert.equal(parentBeforeRating.get("version"), 5);
    assert.equal(parentBeforeRating.get("passengerId"), passenger.uid);
    assert.equal(parentBeforeRating.get("driverId"), driverId);
    const passengerStatusBeforeSubmit =
      await callable(
        passenger,
        "getMyRideRatingStatus",
        {rideId},
      );

    assert.deepEqual(
      passengerStatusBeforeSubmit,
      {
        rideId,
        hasSubmitted: false,
      },
    );

    const driverStatusBeforeSubmit =
      await callable(
        driver,
        "getMyRideRatingStatus",
        {rideId},
      );

    assert.deepEqual(
      driverStatusBeforeSubmit,
      {
        rideId,
        hasSubmitted: false,
      },
    );

    await assert.rejects(
      () =>
        callable(passenger, "submitRideRating", {
          rideId,
          rating: 6,
          requestId: requestId("rating_invalid"),
        }),
      /status=INVALID_ARGUMENT/u,
    );

    await assert.rejects(
      () =>
        callable(outsider, "getMyRideRatingStatus", {
          rideId,
        }),
      /status=PERMISSION_DENIED/u,
    );
    await assert.rejects(
      () =>
        callable(outsider, "submitRideRating", {
          rideId,
          rating: 3,
          requestId: requestId("rating_outsider"),
        }),
      /status=PERMISSION_DENIED/u,
    );

    const passengerRequestId =
      requestId("rating_passenger_submit");

    const passengerInput = {
      rideId,
      rating: 5,
      requestId: passengerRequestId,
    };

    const passengerFirst =
      await callable(
        passenger,
        "submitRideRating",
        passengerInput,
      );

    assert.equal(passengerFirst.rideId, rideId);
    assert.equal(passengerFirst.rating, 5);
    assert.equal(passengerFirst.raterRole, "passenger");
    assert.equal(
      typeof passengerFirst.submittedAtMillis,
      "number",
    );

    const passengerReplay =
      await callable(
        passenger,
        "submitRideRating",
        passengerInput,
      );

    assert.deepEqual(
      passengerReplay,
      passengerFirst,
    );

    const passengerStatusAfterSubmit =
      await callable(
        passenger,
        "getMyRideRatingStatus",
        {rideId},
      );

    assert.equal(
      passengerStatusAfterSubmit.rideId,
      rideId,
    );
    assert.equal(
      passengerStatusAfterSubmit.hasSubmitted,
      true,
    );
    assert.equal(
      passengerStatusAfterSubmit.rating,
      5,
    );
    assert.equal(
      typeof passengerStatusAfterSubmit.submittedAtMillis,
      "number",
    );
    assert.deepEqual(
      Object.keys(passengerStatusAfterSubmit).sort(),
      [
        "hasSubmitted",
        "rating",
        "rideId",
        "submittedAtMillis",
      ],
    );

    const driverStatusAfterPassengerSubmit =
      await callable(
        driver,
        "getMyRideRatingStatus",
        {rideId},
      );

    assert.deepEqual(
      driverStatusAfterPassengerSubmit,
      {
        rideId,
        hasSubmitted: false,
      },
    );
    await assert.rejects(
      () =>
        callable(passenger, "submitRideRating", {
          rideId,
          rating: 4,
          requestId: requestId("rating_passenger_second"),
        }),
      /status=FAILED_PRECONDITION/u,
    );

    const driverRequestId =
      requestId("rating_driver_submit");

    const driverResult =
      await callable(driver, "submitRideRating", {
        rideId,
        rating: 4,
        requestId: driverRequestId,
      });

    assert.equal(driverResult.rideId, rideId);
    assert.equal(driverResult.rating, 4);
    assert.equal(driverResult.raterRole, "driver");
    assert.equal(
      typeof driverResult.submittedAtMillis,
      "number",
    );

    const driverStatusAfterSubmit =
      await callable(
        driver,
        "getMyRideRatingStatus",
        {rideId},
      );

    assert.equal(
      driverStatusAfterSubmit.rideId,
      rideId,
    );
    assert.equal(
      driverStatusAfterSubmit.hasSubmitted,
      true,
    );
    assert.equal(
      driverStatusAfterSubmit.rating,
      4,
    );
    assert.equal(
      typeof driverStatusAfterSubmit.submittedAtMillis,
      "number",
    );
    assert.deepEqual(
      Object.keys(driverStatusAfterSubmit).sort(),
      [
        "hasSubmitted",
        "rating",
        "rideId",
        "submittedAtMillis",
      ],
    );
    const ratings = await firestore
      .collection("rides")
      .doc(rideId)
      .collection("ratings")
      .get();

    assert.equal(ratings.size, 2);

    const passengerRating = await firestore
      .collection("rides")
      .doc(rideId)
      .collection("ratings")
      .doc("passenger")
      .get();

    const driverRating = await firestore
      .collection("rides")
      .doc(rideId)
      .collection("ratings")
      .doc("driver")
      .get();

    assert.equal(passengerRating.exists, true);
    assert.equal(
      passengerRating.get("raterRole"),
      "passenger",
    );
    assert.equal(
      passengerRating.get("raterId"),
      passenger.uid,
    );
    assert.equal(
      passengerRating.get("rateeId"),
      driverId,
    );
    assert.equal(passengerRating.get("rating"), 5);
    assert.ok(
      passengerRating.get("createdAt") instanceof Timestamp,
    );

    assert.equal(driverRating.exists, true);
    assert.equal(
      driverRating.get("raterRole"),
      "driver",
    );
    assert.equal(
      driverRating.get("raterId"),
      driverId,
    );
    assert.equal(
      driverRating.get("rateeId"),
      passenger.uid,
    );
    assert.equal(driverRating.get("rating"), 4);
    assert.ok(
      driverRating.get("createdAt") instanceof Timestamp,
    );

    const passengerOperation = await firestore
      .collection("rideOperations")
      .doc(
        rideOperationId(
          passenger.uid,
          "submitRideRating",
          passengerRequestId,
        ),
      )
      .get();

    const driverOperation = await firestore
      .collection("rideOperations")
      .doc(
        rideOperationId(
          driver.uid,
          "submitRideRating",
          driverRequestId,
        ),
      )
      .get();

    assert.equal(passengerOperation.exists, true);
    assert.equal(
      passengerOperation.get("actorUid"),
      passenger.uid,
    );
    assert.equal(
      passengerOperation.get("callableName"),
      "submitRideRating",
    );
    assert.equal(
      passengerOperation.get("status"),
      "completed",
    );

    assert.equal(driverOperation.exists, true);
    assert.equal(
      driverOperation.get("actorUid"),
      driver.uid,
    );
    assert.equal(
      driverOperation.get("callableName"),
      "submitRideRating",
    );
    assert.equal(
      driverOperation.get("status"),
      "completed",
    );

    const parentAfterRating =
      await firestore.collection("rides").doc(rideId).get();

    assert.deepEqual(
      parentAfterRating.data(),
      parentBeforeRating.data(),
    );

    assert.equal(
      parentAfterRating.get("passengerRating"),
      undefined,
    );
    assert.equal(
      parentAfterRating.get("driverRating"),
      undefined,
    );
    assert.equal(
      parentAfterRating.get("rating"),
      undefined,
    );
  },
);

test(
  "approved driver reads authoritative driver plan catalog through real callable",
  async () => {
    const driver = await signUp("catalog_driver");
    const fixture = await seedDriverPlanPurchaseFixture(driver.uid);

    const result = await callable(
      driver,
      "getDriverPlanCatalog",
      {},
    );

    assert.deepEqual(
      Object.keys(result).sort(),
      ["catalogVersion", "plans"],
    );

    assert.equal(
      result.catalogVersion,
      fixture.catalogVersion,
    );

    const plans = result.plans;

    assert.equal(
      Array.isArray(plans),
      true,
    );

    assert.deepEqual(
      plans,
      [
        {
          planId: "daily",
          enabled: true,
          amountMinor: fixture.amountMinor,
          currency: fixture.currency,
        },
        {
          planId: "weekly",
          enabled: true,
          amountMinor: 2345,
          currency: fixture.currency,
        },
        {
          planId: "monthly",
          enabled: true,
          amountMinor: 3456,
          currency: fixture.currency,
        },
        {
          planId: "quarterly",
          enabled: true,
          amountMinor: 4567,
          currency: fixture.currency,
        },
      ],
    );

    const operations = await firestore
      .collection("driverPlanPurchaseOperations")
      .where("driverId", "==", fixture.driverId)
      .get();

    assert.equal(
      operations.empty,
      true,
    );

    const passes = await firestore
      .collection("driverAccessPasses")
      .where("driverId", "==", fixture.driverId)
      .get();

    assert.equal(
      passes.empty,
      true,
    );
  },
);
test(
  "approved driver prepares driver plan purchase through real callable",
  async () => {
    const driver = await signUp("purchase_driver");
    const fixture = await seedDriverPlanPurchaseFixture(driver.uid);
    const purchaseRequestId = requestId("driver_plan_purchase");

    const input = {
      planId: "daily",
      requestId: purchaseRequestId,
    };

    const first = await callable(
      driver,
      "prepareDriverPlanPurchase",
      input,
    );

    assert.equal(first.status, "pending");
    assert.equal(first.planId, "daily");
    assert.equal(first.catalogVersion, fixture.catalogVersion);
    assert.equal(first.amountMinor, fixture.amountMinor);
    assert.equal(first.currency, fixture.currency);

    const operationId = requireString(
      first,
      "purchaseOperationId",
      "prepareDriverPlanPurchase result",
    );

    assert.match(operationId, /^[a-f0-9]{64}$/u);

    const replay = await callable(
      driver,
      "prepareDriverPlanPurchase",
      input,
    );

    assert.deepEqual(replay, first);

    const operation = await firestore
      .collection("driverPlanPurchaseOperations")
      .doc(operationId)
      .get();

    assert.equal(operation.exists, true);
    assert.equal(operation.get("actorUid"), driver.uid);
    assert.equal(operation.get("driverId"), fixture.driverId);
    assert.equal(operation.get("status"), "pending");
    assert.equal(operation.get("catalogVersion"), fixture.catalogVersion);
    assert.equal(operation.get("planId"), "daily");
    assert.equal(operation.get("amountMinor"), fixture.amountMinor);
    assert.equal(operation.get("currency"), fixture.currency);
    assert.equal(operation.get("passId"), undefined);
    assert.equal(operation.get("paymentSettlementId"), undefined);

    const operations = await firestore
      .collection("driverPlanPurchaseOperations")
      .where("driverId", "==", fixture.driverId)
      .get();

    assert.equal(operations.size, 1);

    const passes = await firestore
      .collection("driverAccessPasses")
      .where("driverId", "==", fixture.driverId)
      .get();

    assert.equal(passes.empty, true);

    const settlements = await firestore
      .collection("driverPlanPaymentSettlements")
      .where("purchaseOperationId", "==", operationId)
      .get();

    assert.equal(settlements.empty, true);
  },
);
test(
  "terminal ride support callable creates backend-private idempotent case",
  async () => {
    const passenger =
      await signUp("support_passenger");

    const driver =
      await signUp("support_driver");

    const outsider =
      await signUp("support_outsider");

    const fixture =
      await seedMatchingRide(
        passenger.uid,
        driver.uid,
      );

    const {rideId, driverId} = fixture;

    const unauthenticatedResponse =
      await fetch(
        `http://${functionsHost}/${projectId}/${region}/createRideSupportCase`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            data: {
              rideId,
              category: "safety",
              requestId:
                requestId("support_unauthenticated"),
            },
          }),
        },
      );

    const unauthenticatedEnvelope =
      asRecord(
        await unauthenticatedResponse.json(),
        "Unauthenticated support response",
      );

    const unauthenticatedError =
      asRecord(
        unauthenticatedEnvelope.error,
        "Unauthenticated support error",
      );

    assert.equal(
      unauthenticatedError.status,
      "UNAUTHENTICATED",
    );

    await assert.rejects(
      () =>
        callable(
          passenger,
          "createRideSupportCase",
          {
            rideId,
            category: "safety",
            requestId:
              requestId("support_non_terminal"),
          },
        ),
      /status=FAILED_PRECONDITION/u,
    );

    await assert.rejects(
      () =>
        callable(
          passenger,
          "createRideSupportCase",
          {
            rideId,
            category: "invented",
            requestId:
              requestId("support_invalid_category"),
          },
        ),
      /status=INVALID_ARGUMENT/u,
    );

    await assert.rejects(
      () =>
        callable(
          passenger,
          "createRideSupportCase",
          {
            rideId,
            category: "route",
            requestId:
              requestId("support_extra_authority"),
            counterpartyId: driverId,
          },
        ),
      /status=INVALID_ARGUMENT/u,
    );

    await assert.rejects(
      () =>
        callable(
          outsider,
          "createRideSupportCase",
          {
            rideId,
            category: "behavior",
            requestId:
              requestId("support_outsider"),
          },
        ),
      /status=PERMISSION_DENIED/u,
    );

    await callable(
      driver,
      "acceptRide",
      {
        rideId,
        requestId:
          requestId("support_accept"),
        expectedVersion: 1,
      },
    );

    await callable(
      driver,
      "markDriverArrived",
      {
        rideId,
        requestId:
          requestId("support_arrive"),
        expectedVersion: 2,
      },
    );

    await callable(
      driver,
      "startRide",
      {
        rideId,
        requestId:
          requestId("support_start"),
        expectedVersion: 3,
      },
    );

    await callable(
      driver,
      "completeRide",
      {
        rideId,
        requestId:
          requestId("support_complete"),
        expectedVersion: 4,
      },
    );

    const parentBeforeSupport =
      await firestore
        .collection("rides")
        .doc(rideId)
        .get();

    assert.equal(
      parentBeforeSupport.exists,
      true,
    );
    assert.equal(
      parentBeforeSupport.get("status"),
      "completed",
    );
    assert.equal(
      parentBeforeSupport.get("version"),
      5,
    );
    assert.equal(
      parentBeforeSupport.get("passengerId"),
      passenger.uid,
    );
    assert.equal(
      parentBeforeSupport.get("driverId"),
      driverId,
    );

    const parentUpdatedAtBefore =
      parentBeforeSupport.get("updatedAt");

    assert.ok(
      parentUpdatedAtBefore instanceof Timestamp,
    );

    const passengerRequestId =
      requestId("support_passenger_create");

    const passengerInput = {
      rideId,
      category: "safety",
      requestId: passengerRequestId,
    };

    const passengerFirst =
      await callable(
        passenger,
        "createRideSupportCase",
        passengerInput,
      );

    assert.equal(
      passengerFirst.rideId,
      rideId,
    );
    assert.equal(
      passengerFirst.category,
      "safety",
    );
    assert.equal(
      typeof passengerFirst.caseId,
      "string",
    );
    assert.equal(
      typeof passengerFirst.createdAtMillis,
      "number",
    );
    assert.deepEqual(
      Object.keys(passengerFirst).sort(),
      [
        "caseId",
        "category",
        "createdAtMillis",
        "rideId",
      ],
    );

    const passengerReplay =
      await callable(
        passenger,
        "createRideSupportCase",
        passengerInput,
      );

    assert.deepEqual(
      passengerReplay,
      passengerFirst,
    );

    const passengerCase =
      await firestore
        .collection("rides")
        .doc(rideId)
        .collection("supportCases")
        .doc(String(passengerFirst.caseId))
        .get();

    assert.equal(
      passengerCase.exists,
      true,
    );
    assert.deepEqual(
      Object.keys(passengerCase.data() ?? {}).sort(),
      [
        "category",
        "counterpartyId",
        "createdAt",
        "reporterId",
        "reporterRole",
      ],
    );
    assert.equal(
      passengerCase.get("reporterRole"),
      "passenger",
    );
    assert.equal(
      passengerCase.get("reporterId"),
      passenger.uid,
    );
    assert.equal(
      passengerCase.get("counterpartyId"),
      driverId,
    );
    assert.equal(
      passengerCase.get("category"),
      "safety",
    );
    assert.ok(
      passengerCase.get("createdAt") instanceof Timestamp,
    );

    const passengerOperation =
      await firestore
        .collection("rideOperations")
        .doc(String(passengerFirst.caseId))
        .get();

    assert.equal(
      passengerOperation.exists,
      true,
    );
    assert.equal(
      passengerOperation.get("actorUid"),
      passenger.uid,
    );
    assert.equal(
      passengerOperation.get("callableName"),
      "createRideSupportCase",
    );
    assert.equal(
      passengerOperation.get("status"),
      "completed",
    );

    const driverRequestId =
      requestId("support_driver_create");

    const driverResult =
      await callable(
        driver,
        "createRideSupportCase",
        {
          rideId,
          category: "vehicle",
          requestId: driverRequestId,
        },
      );

    assert.equal(
      driverResult.rideId,
      rideId,
    );
    assert.equal(
      driverResult.category,
      "vehicle",
    );
    assert.equal(
      typeof driverResult.caseId,
      "string",
    );

    const driverCase =
      await firestore
        .collection("rides")
        .doc(rideId)
        .collection("supportCases")
        .doc(String(driverResult.caseId))
        .get();

    assert.equal(
      driverCase.exists,
      true,
    );
    assert.deepEqual(
      Object.keys(driverCase.data() ?? {}).sort(),
      [
        "category",
        "counterpartyId",
        "createdAt",
        "reporterId",
        "reporterRole",
      ],
    );
    assert.equal(
      driverCase.get("reporterRole"),
      "driver",
    );
    assert.equal(
      driverCase.get("reporterId"),
      driverId,
    );
    assert.equal(
      driverCase.get("counterpartyId"),
      passenger.uid,
    );
    assert.equal(
      driverCase.get("category"),
      "vehicle",
    );
    assert.ok(
      driverCase.get("createdAt") instanceof Timestamp,
    );

    const supportCases =
      await firestore
        .collection("rides")
        .doc(rideId)
        .collection("supportCases")
        .get();

    assert.equal(
      supportCases.size,
      2,
    );

    const parentAfterSupport =
      await firestore
        .collection("rides")
        .doc(rideId)
        .get();

    assert.equal(
      parentAfterSupport.get("status"),
      "completed",
    );
    assert.equal(
      parentAfterSupport.get("version"),
      5,
    );
    assert.equal(
      parentAfterSupport.get("passengerId"),
      passenger.uid,
    );
    assert.equal(
      parentAfterSupport.get("driverId"),
      driverId,
    );

    const parentUpdatedAtAfter =
      parentAfterSupport.get("updatedAt");

    assert.ok(
      parentUpdatedAtAfter instanceof Timestamp,
    );
    assert.equal(
      parentUpdatedAtAfter.toMillis(),
      parentUpdatedAtBefore.toMillis(),
    );
  },
);
test(
  "active ride support real callable authority",
  async () => {
    const passenger =
      await signUp("active_support_passenger");

    const driver =
      await signUp("active_support_driver");

    const outsider =
      await signUp("active_support_outsider");

    const fixture =
      await seedMatchingRide(
        passenger.uid,
        driver.uid,
      );

    const {rideId, driverId} = fixture;

    const unauthenticatedResponse =
      await fetch(
        `http://${functionsHost}/${projectId}/${region}/createActiveRideSupportCase`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            data: {
              rideId,
              category: "safety",
              requestId:
                requestId(
                  "active_support_unauthenticated",
                ),
            },
          }),
        },
      );

    const unauthenticatedEnvelope =
      asRecord(
        await unauthenticatedResponse.json(),
        "Unauthenticated active support response",
      );

    const unauthenticatedError =
      asRecord(
        unauthenticatedEnvelope.error,
        "Unauthenticated active support error",
      );

    assert.equal(
      unauthenticatedError.status,
      "UNAUTHENTICATED",
    );

    await assert.rejects(
      () =>
        callable(
          passenger,
          "createActiveRideSupportCase",
          {
            rideId,
            category: "safety",
            requestId:
              requestId(
                "active_support_matching",
              ),
          },
        ),
      /status=FAILED_PRECONDITION/u,
    );

    await callable(
      driver,
      "acceptRide",
      {
        rideId,
        requestId:
          requestId(
            "active_support_accept",
          ),
        expectedVersion: 1,
      },
    );

    const driverEnRouteRide =
      await firestore
        .collection("rides")
        .doc(rideId)
        .get();

    assert.equal(
      driverEnRouteRide.get("status"),
      "driverEnRoute",
    );

    await assert.rejects(
      () =>
        callable(
          passenger,
          "createActiveRideSupportCase",
          {
            rideId,
            category: "route",
            requestId:
              requestId(
                "active_support_extra_authority",
              ),
            counterpartyId: driverId,
          },
        ),
      /status=INVALID_ARGUMENT/u,
    );

    await assert.rejects(
      () =>
        callable(
          outsider,
          "createActiveRideSupportCase",
          {
            rideId,
            category: "behavior",
            requestId:
              requestId(
                "active_support_outsider",
              ),
          },
        ),
      /status=PERMISSION_DENIED/u,
    );

    const passengerRequestId =
      requestId(
        "active_support_passenger_enroute",
      );

    const passengerInput = {
      rideId,
      category: "safety",
      requestId: passengerRequestId,
    };

    const passengerFirst =
      await callable(
        passenger,
        "createActiveRideSupportCase",
        passengerInput,
      );

    assert.equal(
      passengerFirst.rideId,
      rideId,
    );

    assert.equal(
      passengerFirst.category,
      "safety",
    );

    assert.equal(
      typeof passengerFirst.caseId,
      "string",
    );

    assert.equal(
      typeof passengerFirst.createdAtMillis,
      "number",
    );

    assert.deepEqual(
      Object.keys(passengerFirst).sort(),
      [
        "caseId",
        "category",
        "createdAtMillis",
        "rideId",
      ],
    );

    const passengerReplay =
      await callable(
        passenger,
        "createActiveRideSupportCase",
        passengerInput,
      );

    assert.deepEqual(
      passengerReplay,
      passengerFirst,
    );

    await assert.rejects(
      () =>
        callable(
          passenger,
          "createActiveRideSupportCase",
          {
            rideId,
            category: "behavior",
            requestId: passengerRequestId,
          },
        ),
      /status=FAILED_PRECONDITION/u,
    );

    const passengerCaseRef =
      firestore
        .collection("rides")
        .doc(rideId)
        .collection("supportCases")
        .doc(String(passengerFirst.caseId));

    const passengerCase =
      await passengerCaseRef.get();

    assert.equal(
      passengerCase.exists,
      true,
    );

    assert.deepEqual(
      Object.keys(
        passengerCase.data() ?? {},
      ).sort(),
      [
        "category",
        "counterpartyId",
        "createdAt",
        "reporterId",
        "reporterRole",
      ],
    );

    assert.equal(
      passengerCase.get("reporterRole"),
      "passenger",
    );

    assert.equal(
      passengerCase.get("reporterId"),
      passenger.uid,
    );

    assert.equal(
      passengerCase.get("counterpartyId"),
      driverId,
    );

    assert.equal(
      passengerCase.get("category"),
      "safety",
    );

    assert.ok(
      passengerCase.get("createdAt") instanceof
        Timestamp,
    );

    const passengerCaseBeforeTerminal =
      passengerCase.data();

    const passengerOperation =
      await firestore
        .collection("rideOperations")
        .doc(String(passengerFirst.caseId))
        .get();

    assert.equal(
      passengerOperation.exists,
      true,
    );

    assert.equal(
      passengerOperation.get("actorUid"),
      passenger.uid,
    );

    assert.equal(
      passengerOperation.get("callableName"),
      "createActiveRideSupportCase",
    );

    assert.equal(
      passengerOperation.get("status"),
      "completed",
    );

    await callable(
      driver,
      "markDriverArrived",
      {
        rideId,
        requestId:
          requestId(
            "active_support_arrive",
          ),
        expectedVersion: 2,
      },
    );

    const arrivedRide =
      await firestore
        .collection("rides")
        .doc(rideId)
        .get();

    assert.equal(
      arrivedRide.get("status"),
      "driverArrived",
    );

    const driverResult =
      await callable(
        driver,
        "createActiveRideSupportCase",
        {
          rideId,
          category: "vehicle",
          requestId:
            requestId(
              "active_support_driver_arrived",
            ),
        },
      );

    assert.equal(
      driverResult.rideId,
      rideId,
    );

    assert.equal(
      driverResult.category,
      "vehicle",
    );

    const driverCase =
      await firestore
        .collection("rides")
        .doc(rideId)
        .collection("supportCases")
        .doc(String(driverResult.caseId))
        .get();

    assert.equal(
      driverCase.exists,
      true,
    );

    assert.equal(
      driverCase.get("reporterRole"),
      "driver",
    );

    assert.equal(
      driverCase.get("reporterId"),
      driverId,
    );

    assert.equal(
      driverCase.get("counterpartyId"),
      passenger.uid,
    );

    await callable(
      driver,
      "startRide",
      {
        rideId,
        requestId:
          requestId(
            "active_support_start",
          ),
        expectedVersion: 3,
      },
    );

    const inProgressRide =
      await firestore
        .collection("rides")
        .doc(rideId)
        .get();

    assert.equal(
      inProgressRide.get("status"),
      "inProgress",
    );

    const inProgressResult =
      await callable(
        passenger,
        "createActiveRideSupportCase",
        {
          rideId,
          category: "route",
          requestId:
            requestId(
              "active_support_in_progress",
            ),
        },
      );

    assert.equal(
      inProgressResult.rideId,
      rideId,
    );

    assert.equal(
      inProgressResult.category,
      "route",
    );

    const supportCasesBeforeTerminal =
      await firestore
        .collection("rides")
        .doc(rideId)
        .collection("supportCases")
        .get();

    assert.equal(
      supportCasesBeforeTerminal.size,
      3,
    );

    await callable(
      driver,
      "completeRide",
      {
        rideId,
        requestId:
          requestId(
            "active_support_complete",
          ),
        expectedVersion: 4,
      },
    );

    const completedRide =
      await firestore
        .collection("rides")
        .doc(rideId)
        .get();

    assert.equal(
      completedRide.get("status"),
      "completed",
    );

    await assert.rejects(
      () =>
        callable(
          passenger,
          "createActiveRideSupportCase",
          {
            rideId,
            category: "technical",
            requestId:
              requestId(
                "active_support_after_complete",
              ),
          },
        ),
      /status=FAILED_PRECONDITION/u,
    );

    const passengerCaseAfterTerminal =
      await passengerCaseRef.get();

    assert.equal(
      passengerCaseAfterTerminal.exists,
      true,
    );

    assert.deepEqual(
      passengerCaseAfterTerminal.data(),
      passengerCaseBeforeTerminal,
    );

    const supportCasesAfterTerminal =
      await firestore
        .collection("rides")
        .doc(rideId)
        .collection("supportCases")
        .get();

    assert.equal(
      supportCasesAfterTerminal.size,
      3,
    );

    const purchaseOperations =
      await firestore
        .collection(
          "driverPlanPurchaseOperations",
        )
        .get();

    const paymentSettlements =
      await firestore
        .collection(
          "driverPlanPaymentSettlements",
        )
        .get();

    assert.equal(
      purchaseOperations.empty,
      true,
    );

    assert.equal(
      paymentSettlements.empty,
      true,
    );
  },
);
test(
  "active ride tracking real callable enforces participant scope freshness and terminal cutoff",
  async () => {
    const passenger =
      await signUp("tracking_passenger");
    const driver =
      await signUp("tracking_driver");
    const outsider =
      await signUp("tracking_outsider");

    const fixture =
      await seedMatchingRide(
        passenger.uid,
        driver.uid,
      );

    const {rideId, driverId} = fixture;

    const unauthenticatedResponse =
      await fetch(
        `http://${functionsHost}/${projectId}/${region}/getActiveRideDriverTracking`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            data: {rideId},
          }),
        },
      );

    const unauthenticatedEnvelope =
      asRecord(
        await unauthenticatedResponse.json(),
        "Unauthenticated tracking response",
      );

    const unauthenticatedError =
      asRecord(
        unauthenticatedEnvelope.error,
        "Unauthenticated tracking error",
      );

    assert.equal(
      unauthenticatedError.status,
      "UNAUTHENTICATED",
    );

    await assert.rejects(
      () =>
        callable(
          passenger,
          "getActiveRideDriverTracking",
          {
            rideId,
            driverId,
          },
        ),
      /status=INVALID_ARGUMENT/u,
    );

    await assert.rejects(
      () =>
        callable(
          passenger,
          "getActiveRideDriverTracking",
          {rideId},
        ),
      /status=FAILED_PRECONDITION/u,
    );

    const accepted =
      await callable(
        driver,
        "acceptRide",
        {
          rideId,
          requestId:
            requestId("tracking_accept"),
          expectedVersion: 1,
        },
      );

    assert.equal(
      accepted.status,
      "driverEnRoute",
    );

    await firestore
      .collection("driverLivePresences")
      .doc(driverId)
      .set({
        driverId,
        latitude: 41.0082,
        longitude: 28.9784,
        updatedAt: Timestamp.now(),
      });

    const trackingEtaDriverEnRouteNow =
      Timestamp.now();

    await firestore
      .collection("rideLiveTrackingEtaCaches")
      .doc(rideId)
      .set({
        rideId,
        driverId,
        status: "driverEnRoute",
        etaSeconds: 180,
        etaUpdatedAt:
          trackingEtaDriverEnRouteNow,
        refreshLeaseUntil:
          Timestamp.fromMillis(
            trackingEtaDriverEnRouteNow.toMillis() +
              30_000,
          ),
        updatedAt:
          trackingEtaDriverEnRouteNow,
        testMarker:
          "tracking_eta_driver_en_route_cache",
      });

    const passengerFresh =
      await callable(
        passenger,
        "getActiveRideDriverTracking",
        {rideId},
      );

    assert.equal(
      passengerFresh.latitude,
      41.0082,
    );
    assert.equal(
      passengerFresh.longitude,
      28.9784,
    );
    assert.equal(
      typeof passengerFresh.updatedAtMillis,
      "number",
    );
    assert.equal(
      passengerFresh.etaSeconds,
      180,
    );
    assert.equal(
      typeof passengerFresh.etaUpdatedAtMillis,
      "number",
    );

    const driverFresh =
      await callable(
        driver,
        "getActiveRideDriverTracking",
        {rideId},
      );

    assert.equal(
      driverFresh.latitude,
      41.0082,
    );
    assert.equal(
      driverFresh.longitude,
      28.9784,
    );
    assert.equal(
      typeof driverFresh.updatedAtMillis,
      "number",
    );
    assert.equal(
      driverFresh.etaSeconds,
      180,
    );
    assert.equal(
      typeof driverFresh.etaUpdatedAtMillis,
      "number",
    );

    await assert.rejects(
      () =>
        callable(
          outsider,
          "getActiveRideDriverTracking",
          {rideId},
        ),
      /status=PERMISSION_DENIED/u,
    );

    await firestore
      .collection("driverLivePresences")
      .doc(driverId)
      .set({
        driverId,
        latitude: 41.0082,
        longitude: 28.9784,
        updatedAt:
          Timestamp.fromMillis(
            Date.now() - 21_000,
          ),
      });

    const stale =
      await callable(
        passenger,
        "getActiveRideDriverTracking",
        {rideId},
      );

    assert.deepEqual(
      stale,
      {
        latitude: null,
        longitude: null,
        updatedAtMillis: null,
        etaSeconds: null,
        etaUpdatedAtMillis: null,
      },
    );

    await callable(
      driver,
      "markDriverArrived",
      {
        rideId,
        requestId:
          requestId("tracking_arrive"),
        expectedVersion: 2,
      },
    );

    await firestore
      .collection("driverLivePresences")
      .doc(driverId)
      .set({
        driverId,
        latitude: 41.009,
        longitude: 28.979,
        updatedAt: Timestamp.now(),
      });

    const driverArrivedTracking =
      await callable(
        passenger,
        "getActiveRideDriverTracking",
        {rideId},
      );

    assert.equal(
      driverArrivedTracking.latitude,
      41.009,
    );
    assert.equal(
      driverArrivedTracking.longitude,
      28.979,
    );
    assert.equal(
      driverArrivedTracking.etaSeconds,
      null,
    );
    assert.equal(
      driverArrivedTracking.etaUpdatedAtMillis,
      null,
    );

    await callable(
      driver,
      "startRide",
      {
        rideId,
        requestId:
          requestId("tracking_start"),
        expectedVersion: 3,
      },
    );

    await firestore
      .collection("driverLivePresences")
      .doc(driverId)
      .set({
        driverId,
        latitude: 41.0101,
        longitude: 28.9801,
        updatedAt: Timestamp.now(),
      });

    const trackingEtaInProgressNow =
      Timestamp.now();

    await firestore
      .collection("rideLiveTrackingEtaCaches")
      .doc(rideId)
      .set({
        rideId,
        driverId,
        status: "inProgress",
        etaSeconds: 420,
        etaUpdatedAt:
          trackingEtaInProgressNow,
        refreshLeaseUntil:
          Timestamp.fromMillis(
            trackingEtaInProgressNow.toMillis() +
              30_000,
          ),
        updatedAt:
          trackingEtaInProgressNow,
        testMarker:
          "tracking_eta_in_progress_cache",
      });

    const inProgress =
      await callable(
        passenger,
        "getActiveRideDriverTracking",
        {rideId},
      );

    assert.equal(
      inProgress.latitude,
      41.0101,
    );
    assert.equal(
      inProgress.longitude,
      28.9801,
    );
    assert.equal(
      inProgress.etaSeconds,
      420,
    );
    assert.equal(
      typeof inProgress.etaUpdatedAtMillis,
      "number",
    );

    await callable(
      driver,
      "completeRide",
      {
        rideId,
        requestId:
          requestId("tracking_complete"),
        expectedVersion: 4,
      },
    );

    await assert.rejects(
      () =>
        callable(
          passenger,
          "getActiveRideDriverTracking",
          {rideId},
        ),
      /status=FAILED_PRECONDITION/u,
    );

    await assert.rejects(
      () =>
        callable(
          driver,
          "getActiveRideDriverTracking",
          {rideId},
        ),
      /status=FAILED_PRECONDITION/u,
    );
  },
);
test(
  "midtrip route change real callable safely enforces lifecycle frozen return route persistence and legacy fail closed",
  async () => {
    const passenger =
      await signUp("midtrip_passenger");

    const driver =
      await signUp("midtrip_driver");

    const fixture =
      await seedMatchingRide(
        passenger.uid,
        driver.uid,
      );

    const {rideId} =
      fixture;

    const newDropoff = {
      latitude: 41.03,
      longitude: 29.03,
      addressLabel: "Midtrip New Dropoff",
    };

    await assert.rejects(
      () =>
        callable(
          passenger,
          "proposeRideDropoffChange",
          {
            rideId,
            newDropoff,
            requestId:
              requestId(
                "midtrip_matching_propose",
              ),
          },
        ),
      /status=FAILED_PRECONDITION/u,
    );

    await callable(
      driver,
      "acceptRide",
      {
        rideId,
        requestId:
          requestId(
            "midtrip_accept",
          ),
        expectedVersion: 1,
      },
    );

    const acceptedRide =
      await firestore
        .collection("rides")
        .doc(rideId)
        .get();

    assert.equal(
      acceptedRide.exists,
      true,
    );

    assert.equal(
      acceptedRide.get("status"),
      "driverEnRoute",
    );

    assert.equal(
      acceptedRide.get("version"),
      2,
    );

    const frozenReturnRouteId =
      acceptedRide.get(
        "returnRouteId",
      );

    assert.equal(
      typeof frozenReturnRouteId,
      "string",
    );

    assert.equal(
      (
        frozenReturnRouteId as string
      ).length > 0,
      true,
    );

    const frozenReturnRoute =
      await firestore
        .collection(
          "driverReturnRoutes",
        )
        .doc(
          frozenReturnRouteId as string,
        )
        .get();

    assert.equal(
      frozenReturnRoute.exists,
      true,
    );

    await callable(
      driver,
      "markDriverArrived",
      {
        rideId,
        requestId:
          requestId(
            "midtrip_arrive",
          ),
        expectedVersion: 2,
      },
    );

    await callable(
      driver,
      "startRide",
      {
        rideId,
        requestId:
          requestId(
            "midtrip_start",
          ),
        expectedVersion: 3,
      },
    );

    const inProgressRide =
      await firestore
        .collection("rides")
        .doc(rideId)
        .get();

    assert.equal(
      inProgressRide.get("status"),
      "inProgress",
    );

    assert.equal(
      inProgressRide.get("version"),
      4,
    );

    assert.equal(
      inProgressRide.get(
        "returnRouteId",
      ),
      frozenReturnRouteId,
    );

    const canonicalDriverId =
      inProgressRide.get(
        "driverId",
      );

    assert.equal(
      typeof canonicalDriverId,
      "string",
    );

    assert.equal(
      (
        canonicalDriverId as string
      ).length > 0,
      true,
    );

    const canonicalDropoffBeforeAck =
      inProgressRide.get(
        "dropoff",
      );

    const canonicalRouteBeforeAck =
      inProgressRide.get(
        "route",
      ) as {
        distanceMeters?: unknown;
        durationSeconds?: unknown;
        encodedPolyline?: unknown;
      };

    const pendingProposalId =
      "midtrip_pending_ack_proposal";

    const pendingProposalNow =
      Timestamp.now();

    await firestore
      .collection("rides")
      .doc(rideId)
      .collection(
        "routeChangeProposals",
      )
      .doc(pendingProposalId)
      .set({
        proposerRole:
          "passenger",
        proposerId:
          passenger.uid,
        counterpartyId:
          canonicalDriverId,
        driverId:
          canonicalDriverId,
        returnRouteId:
          frozenReturnRouteId,
        requestedDropoff:
          newDropoff,
        proposedRoute: {
          distanceMeters:
            4321,
          durationSeconds:
            654,
          encodedPolyline:
            "seeded_incompatible_midtrip_route",
          computedAt:
            pendingProposalNow,
        },
        pickupDetourMeters:
          3001,
        pickupDetourSeconds:
          900,
        dropoffDetourMeters:
          3000,
        dropoffDetourSeconds:
          900,
        compatible:
          false,
        status:
          "pendingAcknowledgement",
        baseRideVersion:
          4,
        createdAt:
          pendingProposalNow,
        resolvedAt:
          null,
      });

    await assert.rejects(
      () =>
        callable(
          passenger,
          "acknowledgeRideDropoffChange",
          {
            rideId,
            proposalId:
              pendingProposalId,
            decision:
              "reject",
            requestId:
              requestId(
                "midtrip_ack_proposer_forbidden",
              ),
          },
        ),
      /status=PERMISSION_DENIED/u,
    );

    const stillPendingProposal =
      await firestore
        .collection("rides")
        .doc(rideId)
        .collection(
          "routeChangeProposals",
        )
        .doc(pendingProposalId)
        .get();

    assert.equal(
      stillPendingProposal.get(
        "status",
      ),
      "pendingAcknowledgement",
    );

    const pendingReadResult =
      await callable(
        driver,
        "getPendingRideDropoffChangeProposal",
        {
          rideId,
          proposalId:
            pendingProposalId,
        },
      );

    assert.deepEqual(
      pendingReadResult,
      {
        rideId,
        proposalId:
          pendingProposalId,
        status:
          "pendingAcknowledgement",
        requestedDropoff:
          newDropoff,
      },
    );

    await assert.rejects(
      () =>
        callable(
          passenger,
          "getPendingRideDropoffChangeProposal",
          {
            rideId,
            proposalId:
              pendingProposalId,
          },
        ),
      /status=PERMISSION_DENIED reason=route_change_counterparty_required/u,
    );
    const ackRejectRequestId =
      requestId(
        "midtrip_ack_reject",
      );

    const rejectResult =
      await callable(
        driver,
        "acknowledgeRideDropoffChange",
        {
          rideId,
          proposalId:
            pendingProposalId,
          decision:
            "reject",
          requestId:
            ackRejectRequestId,
        },
      );

    assert.deepEqual(
      rejectResult,
      {
        rideId,
        proposalId:
          pendingProposalId,
        status:
          "rejectedIncompatible",
        decision:
          "reject",
        version:
          4,
        yoldaalRegimeEnded:
          false,
      },
    );

    const rejectedProposal =
      await firestore
        .collection("rides")
        .doc(rideId)
        .collection(
          "routeChangeProposals",
        )
        .doc(pendingProposalId)
        .get();

    assert.equal(
      rejectedProposal.get(
        "status",
      ),
      "rejectedIncompatible",
    );

    assert.equal(
      rejectedProposal.get(
        "resolvedAt",
      ) instanceof Timestamp,
      true,
    );

    await assert.rejects(
      () =>
        callable(
          driver,
          "getPendingRideDropoffChangeProposal",
          {
            rideId,
            proposalId:
              pendingProposalId,
          },
        ),
      /status=FAILED_PRECONDITION reason=route_change_proposal_already_resolved/u,
    );
    const rejectedRide =
      await firestore
        .collection("rides")
        .doc(rideId)
        .get();

    assert.equal(
      rejectedRide.get(
        "status",
      ),
      "inProgress",
    );

    assert.equal(
      rejectedRide.get(
        "version",
      ),
      4,
    );

    assert.deepEqual(
      rejectedRide.get(
        "dropoff",
      ),
      canonicalDropoffBeforeAck,
    );

    const canonicalRouteAfterReject =
      rejectedRide.get(
        "route",
      ) as {
        distanceMeters?: unknown;
        durationSeconds?: unknown;
        encodedPolyline?: unknown;
      };

    assert.equal(
      canonicalRouteAfterReject
        .distanceMeters,
      canonicalRouteBeforeAck
        .distanceMeters,
    );

    assert.equal(
      canonicalRouteAfterReject
        .durationSeconds,
      canonicalRouteBeforeAck
        .durationSeconds,
    );

    assert.equal(
      canonicalRouteAfterReject
        .encodedPolyline,
      canonicalRouteBeforeAck
        .encodedPolyline,
    );

    assert.equal(
      rejectedRide.get(
        "returnRouteId",
      ),
      frozenReturnRouteId,
    );

    assert.equal(
      rejectedRide.get(
        "yoldaalRegimeEnd",
      ),
      undefined,
    );

    const replayResult =
      await callable(
        driver,
        "acknowledgeRideDropoffChange",
        {
          rideId,
          proposalId:
            pendingProposalId,
          decision:
            "reject",
          requestId:
            ackRejectRequestId,
        },
      );

    assert.deepEqual(
      replayResult,
      rejectResult,
    );

    await assert.rejects(
      () =>
        callable(
          driver,
          "acknowledgeRideDropoffChange",
          {
            rideId,
            proposalId:
              pendingProposalId,
            decision:
              "accept",
            requestId:
              ackRejectRequestId,
          },
        ),
      /status=FAILED_PRECONDITION.*reason=idempotency_payload_mismatch/u,
    );

    await firestore
      .collection("rides")
      .doc(rideId)
      .update({
        returnRouteId: null,
      });

    await assert.rejects(
      () =>
        callable(
          passenger,
          "proposeRideDropoffChange",
          {
            rideId,
            newDropoff,
            requestId:
              requestId(
                "midtrip_legacy_missing_frozen_context",
              ),
          },
        ),
      /status=FAILED_PRECONDITION/u,
    );

    // Restore only the frozen historical route reference after the
    // intentional legacy fail-closed assertion above. This is emulator
    // fixture setup only; production authority is not bypassed.
    await firestore
      .collection("rides")
      .doc(rideId)
      .update({
        returnRouteId:
          frozenReturnRouteId,
      });

    const pendingAcceptProposalId =
      "midtrip_pending_ack_accept_proposal";

    const pendingAcceptProposalNow =
      Timestamp.now();

    const acceptedSeedRoute = {
      distanceMeters:
        5432,
      durationSeconds:
        765,
      encodedPolyline:
        "seeded_accepted_incompatible_midtrip_route",
      computedAt:
        pendingAcceptProposalNow,
    };

    await firestore
      .collection("rides")
      .doc(rideId)
      .collection(
        "routeChangeProposals",
      )
      .doc(pendingAcceptProposalId)
      .set({
        proposerRole:
          "passenger",
        proposerId:
          passenger.uid,
        counterpartyId:
          canonicalDriverId,
        driverId:
          canonicalDriverId,
        returnRouteId:
          frozenReturnRouteId,
        requestedDropoff:
          newDropoff,
        proposedRoute:
          acceptedSeedRoute,
        pickupDetourMeters:
          3001,
        pickupDetourSeconds:
          900,
        dropoffDetourMeters:
          3000,
        dropoffDetourSeconds:
          900,
        compatible:
          false,
        status:
          "pendingAcknowledgement",
        baseRideVersion:
          4,
        createdAt:
          pendingAcceptProposalNow,
        resolvedAt:
          null,
      });

    const ackAcceptRequestId =
      requestId(
        "midtrip_ack_accept",
      );

    const acceptResult =
      await callable(
        driver,
        "acknowledgeRideDropoffChange",
        {
          rideId,
          proposalId:
            pendingAcceptProposalId,
          decision:
            "accept",
          requestId:
            ackAcceptRequestId,
        },
      );

    assert.deepEqual(
      acceptResult,
      {
        rideId,
        proposalId:
          pendingAcceptProposalId,
        status:
          "acceptedIncompatible",
        decision:
          "accept",
        version:
          5,
        yoldaalRegimeEnded:
          true,
      },
    );

    const acceptReplayResult =
      await callable(
        driver,
        "acknowledgeRideDropoffChange",
        {
          rideId,
          proposalId:
            pendingAcceptProposalId,
          decision:
            "accept",
          requestId:
            ackAcceptRequestId,
        },
      );

    assert.deepEqual(
      acceptReplayResult,
      acceptResult,
    );

    const acceptedProposal =
      await firestore
        .collection("rides")
        .doc(rideId)
        .collection(
          "routeChangeProposals",
        )
        .doc(pendingAcceptProposalId)
        .get();

    assert.equal(
      acceptedProposal.get(
        "status",
      ),
      "acceptedIncompatible",
    );

    assert.equal(
      acceptedProposal.get(
        "resolvedAt",
      ) instanceof Timestamp,
      true,
    );

    const acceptedRideAfterAck =
      await firestore
        .collection("rides")
        .doc(rideId)
        .get();

    assert.equal(
      acceptedRideAfterAck.get("status"),
      "inProgress",
    );

    assert.equal(
      acceptedRideAfterAck.get("version"),
      5,
    );

    assert.deepEqual(
      acceptedRideAfterAck.get("dropoff"),
      newDropoff,
    );

    const acceptedCanonicalRoute =
      acceptedRideAfterAck.get("route") as {
        distanceMeters?: unknown;
        durationSeconds?: unknown;
        encodedPolyline?: unknown;
      };

    assert.equal(
      acceptedCanonicalRoute
        .distanceMeters,
      5432,
    );

    assert.equal(
      acceptedCanonicalRoute
        .durationSeconds,
      765,
    );

    assert.equal(
      acceptedCanonicalRoute
        .encodedPolyline,
      "seeded_accepted_incompatible_midtrip_route",
    );

    assert.equal(
      acceptedRideAfterAck.get(
        "returnRouteId",
      ),
      frozenReturnRouteId,
    );

    const regimeEnd =
      acceptedRideAfterAck.get(
        "yoldaalRegimeEnd",
      ) as {
        reason?: unknown;
        proposalId?: unknown;
        endedAt?: unknown;
      };

    assert.equal(
      regimeEnd.reason,
      "incompatible_midtrip_dropoff_change",
    );

    assert.equal(
      regimeEnd.proposalId,
      pendingAcceptProposalId,
    );

    assert.equal(
      regimeEnd.endedAt instanceof Timestamp,
      true,
    );

    const midtripEvents =
      await firestore
        .collection("rides")
        .doc(rideId)
        .collection("events")
        .get();

    const acceptedEvents =
      midtripEvents.docs.filter(
        (document) =>
          document.get("type") ===
            "rideDropoffChangeAcceptedIncompatible" &&
          document.get("proposalId") ===
            pendingAcceptProposalId,
      );

    assert.equal(
      acceptedEvents.length,
      1,
    );

    const acceptedEvent =
      acceptedEvents[0];

    assert.equal(
      acceptedEvent.get("fromStatus"),
      "inProgress",
    );

    assert.equal(
      acceptedEvent.get("toStatus"),
      "inProgress",
    );

    assert.equal(
      acceptedEvent.get("actorType"),
      "driver",
    );

    assert.equal(
      acceptedEvent.get("actorId"),
      driver.uid,
    );

    assert.equal(
      acceptedEvent.get("createdAt") instanceof
        Timestamp,
      true,
    );
    const purchaseOperations =
      await firestore
        .collection(
          "driverPlanPurchaseOperations",
        )
        .get();

    const paymentSettlements =
      await firestore
        .collection(
          "driverPlanPaymentSettlements",
        )
        .get();

    assert.equal(
      purchaseOperations.empty,
      true,
    );

    assert.equal(
      paymentSettlements.empty,
      true,
    );
  },
);
