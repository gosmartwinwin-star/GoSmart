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

  batch.set(
    firestore
      .collection("driverProfiles")
      .doc(driverId),
    {
      authUserId: driverUid,
      status: "approved",
    },
  );

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

  batch.set(
    firestore
      .collection("driverReturnRoutes")
      .doc(returnRouteId),
    {
      driverId,
      origin: routePoint0,
      destination: routePoint2,
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
      createdAt: now,
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
              routePoint0,
            );

            assert.deepEqual(
              input.dropoffAnchor,
              routePoint2,
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

    const offerId =
      rideMatchOfferDocumentId(
        fixture.driverId,
        eligible.rideId,
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
/* eslint-enable max-len */
