/* eslint-disable max-len */
import assert from "node:assert/strict";
import test, {
  after,
  beforeEach,
} from "node:test";
import {
  deleteApp,
  initializeApp,
} from "firebase-admin/app";
import {
  getFirestore,
  Timestamp,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  discoverRideMatchOffersForDriver,
} from "./ride-match-offer-discovery.js";
import {
  buildRideMatchOffer,
  rideMatchOfferDocumentId,
} from "./ride-match-offer-helpers.js";
import {
  acceptRideForDriver,
  cancelRideForActor,
} from "./ride-lifecycle-orchestration.js";

const PROJECT_ID = "demo-gosmart";

const firestoreHost =
  process.env.FIRESTORE_EMULATOR_HOST?.trim();

if (!firestoreHost) {
  throw new Error(
    "FIRESTORE_EMULATOR_HOST is required.",
  );
}

const hostOnly =
  firestoreHost
    .replace(/^\[/u, "")
    .replace(/\].*$/u, "")
    .split(":")[0];

if (
  hostOnly !== "127.0.0.1" &&
  hostOnly !== "localhost" &&
  hostOnly !== "::1"
) {
  throw new Error(
    "Firestore emulator must use loopback.",
  );
}

for (const key of [
  "GCLOUD_PROJECT",
  "GOOGLE_CLOUD_PROJECT",
  "FIREBASE_PROJECT_ID",
]) {
  const value =
    process.env[key]?.trim();

  if (
    value &&
    value !== PROJECT_ID
  ) {
    throw new Error(
      `${key} must be ${PROJECT_ID}.`,
    );
  }
}

const app =
  initializeApp(
    {
      projectId: PROJECT_ID,
    },
    `ride-match-discovery-${Date.now()}`,
  );

const firestore =
  getFirestore(app);

after(async () => {
  await deleteApp(app);
});

const COLLECTIONS = [
  "driverProfiles",
  "driverAccessPasses",
  "platformConfig",
  "driverActiveRides",
  "driverReturnRoutes",
  "driverActiveReturnRoutes",
  "rides",
  "passengerActiveRides",
  "driverRideMatchOffers",
] as const;

const clearCollections = async (): Promise<void> => {
  for (const collectionName of COLLECTIONS) {
    const snapshot =
      await firestore
        .collection(collectionName)
        .get();

    if (snapshot.empty) {
      continue;
    }

    const batch =
      firestore.batch();

    for (const document of snapshot.docs) {
      batch.delete(document.ref);
    }

    await batch.commit();
  }
};

beforeEach(async () => {
  await clearCollections();
});

let sequence = 0;

const unique = (
  label: string,
): string => {
  sequence += 1;

  return [
    label,
    Date.now(),
    sequence,
  ].join("_");
};

const ROUTE_POLYLINE =
  "_p~iF~ps|U_ulLnnqC_mqNvxq`@";

const routePoint0 = {
  latitude: 38.5,
  longitude: -120.2,
};

const routePoint2 = {
  latitude: 43.252,
  longitude: -126.453,
};

type Fixture = {
  driverUid: string;
  driverId: string;
  returnRouteId: string;
  passId: string;
  activatedAt: Timestamp;
  expiresAt: Timestamp;
};

const seedDriverContext = async (
  options: {
    expiredPass?: boolean;
    activeRide?: boolean;
    withPass?: boolean;
    accessMode?: "launchFree" | "paid";
  } = {},
): Promise<Fixture> => {
  const driverUid =
    unique("driver_uid");

  const driverId =
    unique("driver_profile");

  const returnRouteId =
    unique("return_route");

  const passId =
    unique("pass");

  const now =
    Timestamp.now();

  const activatedAt =
    Timestamp.fromMillis(
      now.toMillis() - 60_000,
    );

  const expiresAt =
    Timestamp.fromMillis(
      now.toMillis() + 3_600_000,
    );

  const passExpiresAt =
    options.expiredPass ?
      now :
      expiresAt;

  const batch =
    firestore.batch();

  if (options.accessMode) {
    batch.set(
      firestore
        .collection("platformConfig")
        .doc("driverAccess"),
      {
        mode: options.accessMode,
      },
    );
  }

  batch.set(
    firestore
      .collection("driverProfiles")
      .doc(driverId),
    {
      authUserId: driverUid,
      status: "approved",
    },
  );

  if (options.withPass ?? true) {
    batch.set(
      firestore
        .collection("driverAccessPasses")
        .doc(passId),
      {
        driverId,
        status: "active",
        purchasedAt: now,
        activatedAt,
        expiresAt: passExpiresAt,
      },
    );
  }

  batch.set(
    firestore
      .collection("driverReturnRoutes")
      .doc(returnRouteId),
    {
      driverId,
      origin: {
        latitude: routePoint0.latitude + 0.0001,
        longitude: routePoint0.longitude + 0.0001,
      },
      destination: {
        latitude: routePoint2.latitude - 0.0001,
        longitude: routePoint2.longitude - 0.0001,
      },
      status: "active",
      createdAt: activatedAt,
      activatedAt,
      expiresAt,
      routeDistanceMeters: 100000,
      routeDurationSeconds: 7200,
      encodedPolyline: ROUTE_POLYLINE,
      pricingVersion: null,
    },
  );

  batch.set(
    firestore
      .collection("driverActiveReturnRoutes")
      .doc(driverId),
    {
      routeId: returnRouteId,
      activatedAt,
      expiresAt,
    },
  );

  if (options.activeRide) {
    batch.set(
      firestore
        .collection("driverActiveRides")
        .doc(driverId),
      {
        rideId: unique("active_ride"),
        status: "driverEnRoute",
        updatedAt: now,
      },
    );
  }

  await batch.commit();

  return {
    driverUid,
    driverId,
    returnRouteId,
    passId,
    activatedAt,
    expiresAt,
  };
};

type SeedRideInput = {
  passengerId?: string;
  pickup?: {
    latitude: number;
    longitude: number;
  };
  dropoff?: {
    latitude: number;
    longitude: number;
  };
  pointerStatus?: string;
  pointerRideId?: string;
  createdAtOffsetMillis?: number;
  updatedAtOffsetMillis?: number;
};

const seedMatchingRide = async (
  input: SeedRideInput = {},
): Promise<{
  rideId: string;
  passengerId: string;
}> => {
  const rideId =
    unique("ride");

  const passengerId =
    input.passengerId ??
    unique("passenger");

  const now =
    Timestamp.now();

  const createdAt =
    Timestamp.fromMillis(
      now.toMillis() +
      (
        input.createdAtOffsetMillis ??
        0
      ),
    );

  const updatedAt =
    Timestamp.fromMillis(
      now.toMillis() +
      (
        input.updatedAtOffsetMillis ??
        0
      ),
    );

  const pickup =
    input.pickup ??
    routePoint0;

  const dropoff =
    input.dropoff ??
    routePoint2;

  const batch =
    firestore.batch();

  batch.set(
    firestore
      .collection("rides")
      .doc(rideId),
    {
      passengerId,
      driverId: null,
      status: "matching",
      version: 1,
      pickup: {
        ...pickup,
        addressLabel:
          `Pickup ${rideId}`,
      },
      dropoff: {
        ...dropoff,
        addressLabel:
          `Dropoff ${rideId}`,
      },
      route: {
        distanceMeters: 10000,
        durationSeconds: 1200,
        encodedPolyline:
          "synthetic_passenger_route",
        computedAt: now,
      },
      createdAt,
      updatedAt,
      acceptedAt: null,
      driverEnRouteAt: null,
      arrivedAt: null,
      startedAt: null,
      completedAt: null,
      cancelledAt: null,
      expiredAt: null,
      cancelledBy: null,
      terminalReason: null,
    },
  );

  batch.set(
    firestore
      .collection("passengerActiveRides")
      .doc(passengerId),
    {
      rideId:
        input.pointerRideId ??
        rideId,
      status:
        input.pointerStatus ??
        "matching",
      updatedAt: now,
    },
  );

  await batch.commit();

  return {
    rideId,
    passengerId,
  };
};

const reason = (
  error: unknown,
): string | undefined => {
  if (!(error instanceof HttpsError)) {
    return undefined;
  }

  return (
    error.details as {
      reason?: string;
    } | undefined
  )?.reason;
};

const rejectsWithReason = async (
  promise: Promise<unknown>,
  expectedReason: string,
): Promise<void> => {
  await assert.rejects(
    promise,
    (error: unknown) =>
      reason(error) === expectedReason,
  );
};

test(
  "eligible forward ride persists one authoritative offer and reversed ride is skipped",
  async () => {
    const fixture =
      await seedDriverContext();

    const eligible =
      await seedMatchingRide({
        pickup: routePoint0,
        dropoff: routePoint2,
        updatedAtOffsetMillis: 1000,
      });

    const reversed =
      await seedMatchingRide({
        pickup: routePoint2,
        dropoff: routePoint0,
        updatedAtOffsetMillis: 2000,
      });

    let measurementCalls = 0;

    const result =
      await discoverRideMatchOffersForDriver(
        {
          firestore,
          measureDeviation: async (input) => {
            measurementCalls += 1;

            assert.equal(
              input.pickupRouteIndex,
              0,
            );

            assert.equal(
              input.dropoffRouteIndex,
              2,
            );

            assert.deepEqual(
              input.pickupAnchor,
              {
                latitude: routePoint0.latitude + 0.0001,
                longitude: routePoint0.longitude + 0.0001,
              },
            );

            assert.deepEqual(
              input.dropoffAnchor,
              {
                latitude: routePoint2.latitude - 0.0001,
                longitude: routePoint2.longitude - 0.0001,
              },
            );

            return {
              pickupDetourMeters: 900,
              pickupDetourSeconds: 180,
              dropoffDetourMeters: 1200,
              dropoffDetourSeconds: 240,
            };
          },
        },
        fixture.driverUid,
      );

    assert.equal(
      measurementCalls,
      1,
    );

    assert.equal(
      result.offers.length,
      1,
    );

    assert.equal(
      result.offers[0].rideId,
      eligible.rideId,
    );

    assert.equal(
      result.offers[0].rideVersion,
      1,
    );

    assert.equal(
      result.offers[0].pickupDetourMeters,
      900,
    );

    assert.equal(
      result.offers[0].pickupDetourSeconds,
      180,
    );

    assert.equal(
      result.offers[0].dropoffDetourMeters,
      1200,
    );

    assert.equal(
      result.offers[0].dropoffDetourSeconds,
      240,
    );

    assert.equal(
      result.offers[0].passengerTripDistanceMeters,
      10000,
    );

    assert.equal(
      result.offers[0].passengerTripDurationSeconds,
      1200,
    );

    const offerId =
      rideMatchOfferDocumentId(
        fixture.driverId,
        eligible.rideId,
        1,
      );

    const offer =
      await firestore
        .collection(
          "driverRideMatchOffers",
        )
        .doc(offerId)
        .get();

    assert.equal(
      offer.exists,
      true,
    );

    assert.equal(
      offer.get("driverId"),
      fixture.driverId,
    );

    assert.equal(
      offer.get("rideId"),
      eligible.rideId,
    );

    assert.equal(
      offer.get("rideVersion"),
      1,
    );

    assert.equal(
      offer.get("returnRouteId"),
      fixture.returnRouteId,
    );

    assert.equal(
      offer.get("status"),
      "active",
    );

    assert.equal(
      offer.get(
        "measurement.pickupRouteIndex",
      ),
      0,
    );

    assert.equal(
      offer.get(
        "measurement.dropoffRouteIndex",
      ),
      2,
    );

    assert.equal(
      offer.get(
        "measurement.pickupDetourMeters",
      ),
      900,
    );

    const expiresAt =
      offer.get("expiresAt");

    assert.ok(
      expiresAt instanceof Timestamp,
    );

    assert.ok(
      expiresAt.toMillis() <=
      fixture.expiresAt.toMillis(),
    );

    const reversedOffer =
      await firestore
        .collection(
          "driverRideMatchOffers",
        )
        .doc(
          rideMatchOfferDocumentId(
            fixture.driverId,
            reversed.rideId,
            1,
          ),
        )
        .get();

    assert.equal(
      reversedOffer.exists,
      false,
    );
  },
);

test(
  "launchFree permits discovery without driver pass",
  async () => {
    const fixture =
      await seedDriverContext({
        withPass: false,
        accessMode: "launchFree",
      });

    await seedMatchingRide();

    let measurementCalls = 0;

    await discoverRideMatchOffersForDriver(
      {
        firestore,
        measureDeviation: async () => {
          measurementCalls += 1;

          return {
            pickupDetourMeters: 0,
            pickupDetourSeconds: 0,
            dropoffDetourMeters: 0,
            dropoffDetourSeconds: 0,
          };
        },
      },
      fixture.driverUid,
    );

    assert.ok(
      measurementCalls > 0,
    );

    assert.equal(
      (
        await firestore
          .collection("driverAccessPasses")
          .where(
            "driverId",
            "==",
            fixture.driverId,
          )
          .get()
      ).empty,
      true,
    );

    assert.equal(
      (
        await firestore
          .collection("driverRideMatchOffers")
          .get()
      ).empty,
      false,
    );
  },
);

test(
  "expired pass rejects discovery before deviation measurement",
  async () => {
    const fixture =
      await seedDriverContext({
        expiredPass: true,
      });

    await seedMatchingRide();

    let measurementCalls = 0;

    await rejectsWithReason(
      discoverRideMatchOffersForDriver(
        {
          firestore,
          measureDeviation: async () => {
            measurementCalls += 1;

            return {
              pickupDetourMeters: 0,
              pickupDetourSeconds: 0,
              dropoffDetourMeters: 0,
              dropoffDetourSeconds: 0,
            };
          },
        },
        fixture.driverUid,
      ),
      "subscription_required",
    );

    assert.equal(
      measurementCalls,
      0,
    );

    assert.equal(
      (
        await firestore
          .collection(
            "driverRideMatchOffers",
          )
          .get()
      ).empty,
      true,
    );
  },
);

test(
  "existing driver active ride rejects discovery before candidate measurement",
  async () => {
    const fixture =
      await seedDriverContext({
        activeRide: true,
      });

    await seedMatchingRide();

    let measurementCalls = 0;

    await rejectsWithReason(
      discoverRideMatchOffersForDriver(
        {
          firestore,
          measureDeviation: async () => {
            measurementCalls += 1;

            return {
              pickupDetourMeters: 0,
              pickupDetourSeconds: 0,
              dropoffDetourMeters: 0,
              dropoffDetourSeconds: 0,
            };
          },
        },
        fixture.driverUid,
      ),
      "driver_active_ride_exists",
    );

    assert.equal(
      measurementCalls,
      0,
    );

    assert.equal(
      (
        await firestore
          .collection(
            "driverRideMatchOffers",
          )
          .get()
      ).empty,
      true,
    );
  },
);

test(
  "stale passenger active pointer prevents offer persistence after measurement",
  async () => {
    const fixture =
      await seedDriverContext();

    const candidate =
      await seedMatchingRide({
        pointerStatus: "driverEnRoute",
      });

    let measurementCalls = 0;

    const result =
      await discoverRideMatchOffersForDriver(
        {
          firestore,
          measureDeviation: async () => {
            measurementCalls += 1;

            return {
              pickupDetourMeters: 1000,
              pickupDetourSeconds: 200,
              dropoffDetourMeters: 1000,
              dropoffDetourSeconds: 200,
            };
          },
        },
        fixture.driverUid,
      );

    assert.equal(
      measurementCalls,
      1,
    );

    assert.deepEqual(
      result,
      {
        offers: [],
      },
    );

    const offer =
      await firestore
        .collection(
          "driverRideMatchOffers",
        )
        .doc(
          rideMatchOfferDocumentId(
            fixture.driverId,
            candidate.rideId,
            1,
          ),
        )
        .get();

    assert.equal(
      offer.exists,
      false,
    );
  },
);
test(
  "consumed offer is never resurrected by discovery refresh",
  async () => {
    const fixture =
      await seedDriverContext();

    const candidate =
      await seedMatchingRide();

    const offerId =
      rideMatchOfferDocumentId(
        fixture.driverId,
        candidate.rideId,
        1,
      );

    const consumedAt =
      Timestamp.now();

    const createdAt =
      Timestamp.fromMillis(
        consumedAt.toMillis() - 1000,
      );

    const activeOffer =
      buildRideMatchOffer({
        driverId:
          fixture.driverId,
        rideId:
          candidate.rideId,
        rideVersion: 1,
        returnRouteId:
          fixture.returnRouteId,
        routeExpiresAt:
          fixture.expiresAt,
        now:
          createdAt,
        measurement: {
          pickupRouteIndex: 0,
          dropoffRouteIndex: 2,
          pickupDetourMeters: 700,
          pickupDetourSeconds: 140,
          dropoffDetourMeters: 800,
          dropoffDetourSeconds: 160,
        },
      });

    await firestore
      .collection(
        "driverRideMatchOffers",
      )
      .doc(offerId)
      .set({
        ...activeOffer,
        status: "consumed",
        consumedAt,
      });

    let measurementCalls = 0;

    const result =
      await discoverRideMatchOffersForDriver(
        {
          firestore,
          measureDeviation: async () => {
            measurementCalls += 1;

            return {
              pickupDetourMeters: 100,
              pickupDetourSeconds: 20,
              dropoffDetourMeters: 100,
              dropoffDetourSeconds: 20,
            };
          },
        },
        fixture.driverUid,
      );

    assert.equal(
      measurementCalls,
      1,
    );

    assert.deepEqual(
      result,
      {
        offers: [],
      },
    );

    const persisted =
      await firestore
        .collection(
          "driverRideMatchOffers",
        )
        .doc(offerId)
        .get();

    assert.equal(
      persisted.exists,
      true,
    );

    assert.equal(
      persisted.get("status"),
      "consumed",
    );

    const persistedConsumedAt =
      persisted.get("consumedAt");

    assert.ok(
      persistedConsumedAt instanceof Timestamp,
    );

    assert.equal(
      persistedConsumedAt.toMillis(),
      consumedAt.toMillis(),
    );

    const persistedCreatedAt =
      persisted.get("createdAt");

    assert.ok(
      persistedCreatedAt instanceof Timestamp,
    );

    assert.equal(
      persistedCreatedAt.toMillis(),
      createdAt.toMillis(),
    );
  },
);

test(
  "driver rematch creates a new version-scoped offer while old consumed offer stays immutable",
  async () => {
    const fixture =
      await seedDriverContext();

    const candidate =
      await seedMatchingRide();

    const firstDiscovery =
      await discoverRideMatchOffersForDriver(
        {
          firestore,
          measureDeviation: async () => ({
            pickupDetourMeters: 100,
            pickupDetourSeconds: 20,
            dropoffDetourMeters: 100,
            dropoffDetourSeconds: 20,
          }),
        },
        fixture.driverUid,
      );

    assert.equal(
      firstDiscovery.offers.length,
      1,
    );

    assert.equal(
      firstDiscovery.offers[0].rideId,
      candidate.rideId,
    );

    const oldOfferId =
      rideMatchOfferDocumentId(
        fixture.driverId,
        candidate.rideId,
        1,
      );

    const oldOfferBeforeAccept =
      await firestore
        .collection("driverRideMatchOffers")
        .doc(oldOfferId)
        .get();

    assert.equal(
      oldOfferBeforeAccept.exists,
      true,
    );

    assert.equal(
      oldOfferBeforeAccept.get("status"),
      "active",
    );

    assert.equal(
      oldOfferBeforeAccept.get("rideVersion"),
      1,
    );

    const accepted =
      await acceptRideForDriver(
        {firestore},
        fixture.driverUid,
        {
          rideId: candidate.rideId,
          requestId:
            `${unique("gap9_integrated_accept")}_123456789`,
          expectedVersion: 1,
        },
      );

    assert.equal(
      accepted.rideId,
      candidate.rideId,
    );

    assert.equal(
      accepted.status,
      "driverEnRoute",
    );

    assert.equal(
      accepted.version,
      2,
    );

    const oldConsumed =
      await firestore
        .collection("driverRideMatchOffers")
        .doc(oldOfferId)
        .get();

    assert.equal(
      oldConsumed.exists,
      true,
    );

    assert.equal(
      oldConsumed.get("status"),
      "consumed",
    );

    assert.equal(
      oldConsumed.get("rideVersion"),
      1,
    );

    const oldConsumedAt =
      oldConsumed.get("consumedAt");

    const oldCreatedAt =
      oldConsumed.get("createdAt");

    assert.ok(
      oldConsumedAt instanceof Timestamp,
    );

    assert.ok(
      oldCreatedAt instanceof Timestamp,
    );

    const rematched =
      await cancelRideForActor(
        {firestore},
        fixture.driverUid,
        {
          rideId: candidate.rideId,
          requestId:
            `${unique("gap9_integrated_cancel")}_123456789`,
          expectedVersion: 2,
          reasonCode: "driver_cancelled",
        },
      );

    assert.equal(
      rematched.rideId,
      candidate.rideId,
    );

    assert.equal(
      rematched.status,
      "matching",
    );

    assert.equal(
      rematched.version,
      3,
    );

    assert.equal(
      rematched.matchRound,
      2,
    );

    const rematchedRide =
      await firestore
        .collection("rides")
        .doc(candidate.rideId)
        .get();

    assert.equal(
      rematchedRide.get("status"),
      "matching",
    );

    assert.equal(
      rematchedRide.get("version"),
      3,
    );

    assert.equal(
      rematchedRide.get("matchRound"),
      2,
    );

    assert.equal(
      rematchedRide.get("driverId"),
      null,
    );

    assert.equal(
      (
        await firestore
          .collection("driverActiveRides")
          .doc(fixture.driverId)
          .get()
      ).exists,
      false,
    );

    const passengerPointer =
      await firestore
        .collection("passengerActiveRides")
        .doc(candidate.passengerId)
        .get();

    assert.equal(
      passengerPointer.exists,
      true,
    );

    assert.equal(
      passengerPointer.get("rideId"),
      candidate.rideId,
    );

    assert.equal(
      passengerPointer.get("status"),
      "matching",
    );

    await assert.rejects(
      acceptRideForDriver(
        {firestore},
        fixture.driverUid,
        {
          rideId: candidate.rideId,
          requestId:
            `${unique("gap9_integrated_stale_accept")}_123456789`,
          expectedVersion: 3,
        },
      ),
      (error: unknown) =>
        error instanceof HttpsError &&
        error.code === "failed-precondition",
    );

    const afterStaleAttempt =
      await firestore
        .collection("rides")
        .doc(candidate.rideId)
        .get();

    assert.equal(
      afterStaleAttempt.get("status"),
      "matching",
    );

    assert.equal(
      afterStaleAttempt.get("version"),
      3,
    );

    const newOfferId =
      rideMatchOfferDocumentId(
        fixture.driverId,
        candidate.rideId,
        3,
      );

    assert.notEqual(
      newOfferId,
      oldOfferId,
    );

    assert.equal(
      (
        await firestore
          .collection("driverRideMatchOffers")
          .doc(newOfferId)
          .get()
      ).exists,
      false,
    );

    const secondDiscovery =
      await discoverRideMatchOffersForDriver(
        {
          firestore,
          measureDeviation: async () => ({
            pickupDetourMeters: 120,
            pickupDetourSeconds: 24,
            dropoffDetourMeters: 140,
            dropoffDetourSeconds: 28,
          }),
        },
        fixture.driverUid,
      );

    assert.equal(
      secondDiscovery.offers.length,
      1,
    );

    assert.equal(
      secondDiscovery.offers[0].rideId,
      candidate.rideId,
    );

    const newOffer =
      await firestore
        .collection("driverRideMatchOffers")
        .doc(newOfferId)
        .get();

    assert.equal(
      newOffer.exists,
      true,
    );

    assert.equal(
      newOffer.get("status"),
      "active",
    );

    assert.equal(
      newOffer.get("rideId"),
      candidate.rideId,
    );

    assert.equal(
      newOffer.get("driverId"),
      fixture.driverId,
    );

    assert.equal(
      newOffer.get("rideVersion"),
      3,
    );

    const oldConsumedAfterRediscovery =
      await firestore
        .collection("driverRideMatchOffers")
        .doc(oldOfferId)
        .get();

    assert.equal(
      oldConsumedAfterRediscovery.exists,
      true,
    );

    assert.equal(
      oldConsumedAfterRediscovery.get("status"),
      "consumed",
    );

    assert.equal(
      oldConsumedAfterRediscovery.get("rideVersion"),
      1,
    );

    const oldConsumedAtAfterRediscovery =
      oldConsumedAfterRediscovery.get(
        "consumedAt",
      );

    const oldCreatedAtAfterRediscovery =
      oldConsumedAfterRediscovery.get(
        "createdAt",
      );

    assert.ok(
      oldConsumedAtAfterRediscovery instanceof Timestamp,
    );

    assert.ok(
      oldCreatedAtAfterRediscovery instanceof Timestamp,
    );

    assert.equal(
      oldConsumedAtAfterRediscovery.toMillis(),
      oldConsumedAt.toMillis(),
    );

    assert.equal(
      oldCreatedAtAfterRediscovery.toMillis(),
      oldCreatedAt.toMillis(),
    );

    const rematchEvents =
      (
        await firestore
          .collection("rides")
          .doc(candidate.rideId)
          .collection("events")
          .get()
      ).docs.filter(
        (event) =>
          event.get("type") ===
          "rideDriverCancelledForRematch",
      );

    assert.equal(
      rematchEvents.length,
      1,
    );

    assert.equal(
      rematchEvents[0].get("matchRound"),
      2,
    );
  },
);

test(
  "W1B Firestore candidate five reserves two aged fairness and three best route slots",
  async () => {
    const fixture =
      await seedDriverContext();

    const specs = [
      {
        label: "fair-oldest",
        createdAtOffsetMillis:
          -20 * 60 * 1000,
        pickupDelta: 0.0010,
        measurement: {
          pickupDetourMeters: 2700,
          pickupDetourSeconds: 810,
          dropoffDetourMeters: 2700,
          dropoffDetourSeconds: 810,
        },
      },
      {
        label: "fair-second",
        createdAtOffsetMillis:
          -18 * 60 * 1000,
        pickupDelta: 0.0011,
        measurement: {
          pickupDetourMeters: 2850,
          pickupDetourSeconds: 855,
          dropoffDetourMeters: 2850,
          dropoffDetourSeconds: 855,
        },
      },
      {
        label: "route-a-hard-ineligible",
        createdAtOffsetMillis:
          -1 * 60 * 1000,
        pickupDelta: 0.0001,
        measurement: {
          pickupDetourMeters: 3001,
          pickupDetourSeconds: 100,
          dropoffDetourMeters: 100,
          dropoffDetourSeconds: 100,
        },
      },
      {
        label: "route-b-best",
        createdAtOffsetMillis:
          -2 * 60 * 1000,
        pickupDelta: 0.0002,
        measurement: {
          pickupDetourMeters: 600,
          pickupDetourSeconds: 180,
          dropoffDetourMeters: 600,
          dropoffDetourSeconds: 180,
        },
      },
      {
        label: "route-c-second",
        createdAtOffsetMillis:
          -3 * 60 * 1000,
        pickupDelta: 0.0003,
        measurement: {
          pickupDetourMeters: 900,
          pickupDetourSeconds: 270,
          dropoffDetourMeters: 900,
          dropoffDetourSeconds: 270,
        },
      },
      {
        label: "route-d-not-selected",
        createdAtOffsetMillis:
          -4 * 60 * 1000,
        pickupDelta: 0.0004,
        measurement: {
          pickupDetourMeters: 300,
          pickupDetourSeconds: 90,
          dropoffDetourMeters: 300,
          dropoffDetourSeconds: 90,
        },
      },
      {
        label: "route-e-not-selected",
        createdAtOffsetMillis:
          -5 * 60 * 1000,
        pickupDelta: 0.0005,
        measurement: {
          pickupDetourMeters: 100,
          pickupDetourSeconds: 30,
          dropoffDetourMeters: 100,
          dropoffDetourSeconds: 30,
        },
      },
    ];

    const seeded: Array<{
      label: string;
      createdAtOffsetMillis: number;
      pickupDelta: number;
      measurement: {
        pickupDetourMeters: number;
        pickupDetourSeconds: number;
        dropoffDetourMeters: number;
        dropoffDetourSeconds: number;
      };
      rideId: string;
      passengerId: string;
      pickup: {
        latitude: number;
        longitude: number;
      };
      dropoff: {
        latitude: number;
        longitude: number;
      };
    }> = [];

    for (const spec of specs) {
      const pickup = {
        latitude:
          routePoint0.latitude +
          spec.pickupDelta,
        longitude:
          routePoint0.longitude,
      };

      const dropoff = {
        latitude:
          routePoint2.latitude -
          spec.pickupDelta,
        longitude:
          routePoint2.longitude,
      };

      const ride =
        await seedMatchingRide({
          pickup,
          dropoff,
          createdAtOffsetMillis:
            spec.createdAtOffsetMillis,
        });

      seeded.push({
        ...spec,
        ...ride,
        pickup,
        dropoff,
      });
    }

    const discoveryNow =
      Timestamp.now();

    const measuredLabels: string[] = [];

    const result =
      await discoverRideMatchOffersForDriver(
        {
          firestore,
          now: () => discoveryNow,
          measureDeviation: async (input) => {
            const matched =
              seeded.find(
                (item) =>
                  Math.abs(
                    item.pickup.latitude -
                    input.pickup.latitude,
                  ) < 1e-12 &&
                  Math.abs(
                    item.dropoff.latitude -
                    input.dropoff.latitude,
                  ) < 1e-12,
              );

            assert.ok(matched);

            measuredLabels.push(
              matched.label,
            );

            return matched.measurement;
          },
        },
        fixture.driverUid,
      );

    assert.deepEqual(
      measuredLabels,
      [
        "fair-oldest",
        "fair-second",
        "route-a-hard-ineligible",
        "route-b-best",
        "route-c-second",
      ],
    );

    assert.equal(
      measuredLabels.length,
      5,
    );

    const byLabel =
      new Map(
        seeded.map(
          (item) => [
            item.label,
            item.rideId,
          ],
        ),
      );

    assert.deepEqual(
      result.offers.map(
        (offer) =>
          offer.rideId,
      ),
      [
        byLabel.get("fair-oldest"),
        byLabel.get("fair-second"),
        byLabel.get("route-b-best"),
      ],
    );

    assert.equal(
      result.offers.length,
      3,
    );

    assert.equal(
      result.offers.some(
        (offer) =>
          offer.rideId ===
          byLabel.get(
            "route-a-hard-ineligible",
          ),
      ),
      false,
    );

    assert.equal(
      measuredLabels.includes(
        "route-d-not-selected",
      ),
      false,
    );

    assert.equal(
      measuredLabels.includes(
        "route-e-not-selected",
      ),
      false,
    );

    const persisted =
      await firestore
        .collection(
          "driverRideMatchOffers",
        )
        .where(
          "driverId",
          "==",
          fixture.driverId,
        )
        .get();

    assert.equal(
      persisted.size,
      3,
    );

    assert.deepEqual(
      persisted.docs
        .map(
          (document) =>
            document.get("rideId"),
        )
        .sort(),
      result.offers
        .map(
          (offer) =>
            offer.rideId,
        )
        .sort(),
    );
  },
);

test(
  "W1B Firestore unused fairness slot spills into fourth best route measurement slot",
  async () => {
    const fixture =
      await seedDriverContext();

    const specs = [
      {
        label: "fair-only",
        createdAtOffsetMillis:
          -20 * 60 * 1000,
        pickupDelta: 0.0010,
        measurement: {
          pickupDetourMeters: 2700,
          pickupDetourSeconds: 810,
          dropoffDetourMeters: 2700,
          dropoffDetourSeconds: 810,
        },
      },
      {
        label: "route-a",
        createdAtOffsetMillis:
          -1 * 60 * 1000,
        pickupDelta: 0.0001,
        measurement: {
          pickupDetourMeters: 1200,
          pickupDetourSeconds: 360,
          dropoffDetourMeters: 1200,
          dropoffDetourSeconds: 360,
        },
      },
      {
        label: "route-b-best",
        createdAtOffsetMillis:
          -2 * 60 * 1000,
        pickupDelta: 0.0002,
        measurement: {
          pickupDetourMeters: 300,
          pickupDetourSeconds: 90,
          dropoffDetourMeters: 300,
          dropoffDetourSeconds: 90,
        },
      },
      {
        label: "route-c-second",
        createdAtOffsetMillis:
          -3 * 60 * 1000,
        pickupDelta: 0.0003,
        measurement: {
          pickupDetourMeters: 600,
          pickupDetourSeconds: 180,
          dropoffDetourMeters: 600,
          dropoffDetourSeconds: 180,
        },
      },
      {
        label: "route-d-fourth-slot",
        createdAtOffsetMillis:
          -4 * 60 * 1000,
        pickupDelta: 0.0004,
        measurement: {
          pickupDetourMeters: 900,
          pickupDetourSeconds: 270,
          dropoffDetourMeters: 900,
          dropoffDetourSeconds: 270,
        },
      },
      {
        label: "route-e-not-selected",
        createdAtOffsetMillis:
          -5 * 60 * 1000,
        pickupDelta: 0.0005,
        measurement: {
          pickupDetourMeters: 100,
          pickupDetourSeconds: 30,
          dropoffDetourMeters: 100,
          dropoffDetourSeconds: 30,
        },
      },
    ];

    const seeded: Array<{
      label: string;
      createdAtOffsetMillis: number;
      pickupDelta: number;
      measurement: {
        pickupDetourMeters: number;
        pickupDetourSeconds: number;
        dropoffDetourMeters: number;
        dropoffDetourSeconds: number;
      };
      rideId: string;
      passengerId: string;
      pickup: {
        latitude: number;
        longitude: number;
      };
      dropoff: {
        latitude: number;
        longitude: number;
      };
    }> = [];

    for (const spec of specs) {
      const pickup = {
        latitude:
          routePoint0.latitude +
          spec.pickupDelta,
        longitude:
          routePoint0.longitude,
      };

      const dropoff = {
        latitude:
          routePoint2.latitude -
          spec.pickupDelta,
        longitude:
          routePoint2.longitude,
      };

      const ride =
        await seedMatchingRide({
          pickup,
          dropoff,
          createdAtOffsetMillis:
            spec.createdAtOffsetMillis,
        });

      seeded.push({
        ...spec,
        ...ride,
        pickup,
        dropoff,
      });
    }

    const discoveryNow =
      Timestamp.now();

    const measuredLabels: string[] = [];

    const result =
      await discoverRideMatchOffersForDriver(
        {
          firestore,
          now: () => discoveryNow,
          measureDeviation: async (input) => {
            const matched =
              seeded.find(
                (item) =>
                  Math.abs(
                    item.pickup.latitude -
                    input.pickup.latitude,
                  ) < 1e-12 &&
                  Math.abs(
                    item.dropoff.latitude -
                    input.dropoff.latitude,
                  ) < 1e-12,
              );

            assert.ok(matched);

            measuredLabels.push(
              matched.label,
            );

            return matched.measurement;
          },
        },
        fixture.driverUid,
      );

    assert.deepEqual(
      measuredLabels,
      [
        "fair-only",
        "route-a",
        "route-b-best",
        "route-c-second",
        "route-d-fourth-slot",
      ],
    );

    assert.equal(
      measuredLabels.length,
      5,
    );

    assert.equal(
      measuredLabels.includes(
        "route-e-not-selected",
      ),
      false,
    );

    const byLabel =
      new Map(
        seeded.map(
          (item) => [
            item.label,
            item.rideId,
          ],
        ),
      );

    assert.deepEqual(
      result.offers.map(
        (offer) =>
          offer.rideId,
      ),
      [
        byLabel.get("fair-only"),
        byLabel.get("route-b-best"),
        byLabel.get("route-c-second"),
      ],
    );

    assert.equal(
      result.offers.length,
      3,
    );
  },
);
/* eslint-enable max-len */
