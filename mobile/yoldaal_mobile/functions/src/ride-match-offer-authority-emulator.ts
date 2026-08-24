/* eslint-disable max-len */
import assert from "node:assert/strict";
import test, {after, beforeEach} from "node:test";
import {
  deleteApp,
  initializeApp,
} from "firebase-admin/app";
import {
  getFirestore,
  Timestamp,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {acceptRideForDriver} from "./ride-lifecycle-orchestration.js";
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
  const value = process.env[key]?.trim();

  if (value && value !== PROJECT_ID) {
    throw new Error(
      `${key} must be ${PROJECT_ID}.`,
    );
  }
}

const app =
  initializeApp(
    {projectId: PROJECT_ID},
    `ride-match-offer-authority-${Date.now()}`,
  );

const firestore =
  getFirestore(app);

after(async () => {
  await deleteApp(app);
});

beforeEach(async () => {
  await firestore
    .collection("platformConfig")
    .doc("driverAccess")
    .delete();
});

let sequence = 0;

const unique = (label: string): string => {
  sequence += 1;

  return [
    label,
    Date.now(),
    sequence,
  ].join("_");
};

const point = (
  latitude: number,
  longitude: number,
) => ({
  latitude,
  longitude,
});

type Scenario = {
  driverUid: string;
  driverId: string;
  passengerId: string;
  rideId: string;
  returnRouteId: string;
  offerId: string;
  passId: string;
};

const measurement = {
  pickupRouteIndex: 2,
  dropoffRouteIndex: 8,
  pickupDetourMeters: 900,
  pickupDetourSeconds: 180,
  dropoffDetourMeters: 1300,
  dropoffDetourSeconds: 260,
};

const seedScenario = async (
  options: {
    withOffer?: boolean;
    expiredPass?: boolean;
    withPass?: boolean;
    accessMode?: "launchFree" | "paid";
  } = {},
): Promise<Scenario> => {
  const driverUid =
    unique("driver_uid");

  const driverId =
    unique("driver_profile");

  const passengerId =
    unique("passenger_uid");

  const rideId =
    unique("ride");

  const returnRouteId =
    unique("return_route");

  const passId =
    unique("driver_pass");

  const offerId =
    rideMatchOfferDocumentId(
      driverId,
      rideId,
    );

  const now = Timestamp.now();

  const activatedAt =
    Timestamp.fromMillis(
      now.toMillis() - 60_000,
    );

  const routeExpiresAt =
    Timestamp.fromMillis(
      now.toMillis() + 3_600_000,
    );

  const passExpiresAt =
    options.expiredPass ?
      now :
      Timestamp.fromMillis(
        now.toMillis() + 3_600_000,
      );

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
        purchasedAt:
          Timestamp.fromMillis(
            now.toMillis() - 120_000,
          ),
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
      origin: point(
        41.0082,
        28.9784,
      ),
      destination: point(
        41.0400,
        29.0100,
      ),
      status: "active",
      createdAt: activatedAt,
      activatedAt,
      expiresAt: routeExpiresAt,
      routeDistanceMeters: 6200,
      routeDurationSeconds: 1100,
      encodedPolyline: "synthetic_polyline",
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
      expiresAt: routeExpiresAt,
    },
  );

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
        ...point(
          41.0120,
          28.9820,
        ),
        addressLabel:
          "Synthetic pickup",
      },
      dropoff: {
        ...point(
          41.0300,
          29.0000,
        ),
        addressLabel:
          "Synthetic dropoff",
      },
      createdAt: now,
      updatedAt: now,
    },
  );

  batch.set(
    firestore
      .collection("passengerActiveRides")
      .doc(passengerId),
    {
      rideId,
      status: "matching",
      updatedAt: now,
    },
  );

  if (options.withOffer ?? true) {
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
        measurement,
      }),
    );
  }

  await batch.commit();

  return {
    driverUid,
    driverId,
    passengerId,
    rideId,
    returnRouteId,
    offerId,
    passId,
  };
};

const mutation = (
  rideId: string,
  label: string,
) => ({
  rideId,
  requestId:
    `${unique(label)}_123456789`,
  expectedVersion: 1,
});

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

const rejectWithReason = async (
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
  "approved driver cannot accept arbitrary matching ride without offer",
  async () => {
    const scenario =
      await seedScenario({
        withOffer: false,
      });

    await rejectWithReason(
      acceptRideForDriver(
        {firestore},
        scenario.driverUid,
        mutation(
          scenario.rideId,
          "missing_offer",
        ),
      ),
      "ride_match_offer_required",
    );

    const ride = await firestore
      .collection("rides")
      .doc(scenario.rideId)
      .get();

    assert.equal(
      ride.get("status"),
      "matching",
    );

    assert.equal(
      ride.get("version"),
      1,
    );

    assert.equal(
      (
        await firestore
          .collection("driverActiveRides")
          .doc(scenario.driverId)
          .get()
      ).exists,
      false,
    );
  },
);

test(
  "launchFree permits offer acceptance without driver pass",
  async () => {
    const scenario =
      await seedScenario({
        withPass: false,
        accessMode: "launchFree",
      });

    const accepted =
      await acceptRideForDriver(
        {firestore},
        scenario.driverUid,
        mutation(
          scenario.rideId,
          "launch_free_accept",
        ),
      );

    assert.equal(
      accepted.status,
      "driverEnRoute",
    );

    assert.equal(
      accepted.version,
      2,
    );

    assert.equal(
      (
        await firestore
          .collection("driverAccessPasses")
          .where(
            "driverId",
            "==",
            scenario.driverId,
          )
          .get()
      ).empty,
      true,
    );

    const offer =
      await firestore
        .collection("driverRideMatchOffers")
        .doc(scenario.offerId)
        .get();

    assert.equal(
      offer.get("status"),
      "consumed",
    );
  },
);

test(
  "expired driver pass prevents offer acceptance",
  async () => {
    const scenario =
      await seedScenario({
        expiredPass: true,
      });

    await rejectWithReason(
      acceptRideForDriver(
        {firestore},
        scenario.driverUid,
        mutation(
          scenario.rideId,
          "expired_pass",
        ),
      ),
      "subscription_required",
    );

    const offer = await firestore
      .collection("driverRideMatchOffers")
      .doc(scenario.offerId)
      .get();

    assert.equal(
      offer.get("status"),
      "active",
    );

    assert.equal(
      offer.get("consumedAt"),
      null,
    );
  },
);

test(
  "active return route replacement invalidates old offer",
  async () => {
    const scenario =
      await seedScenario();

    const now =
      Timestamp.now();

    const activatedAt =
      Timestamp.fromMillis(
        now.toMillis() - 30_000,
      );

    const expiresAt =
      Timestamp.fromMillis(
        now.toMillis() + 3_600_000,
      );

    const replacementRouteId =
      unique("replacement_route");

    const batch =
      firestore.batch();

    batch.set(
      firestore
        .collection("driverReturnRoutes")
        .doc(replacementRouteId),
      {
        driverId: scenario.driverId,
        origin: point(
          41.0100,
          28.9800,
        ),
        destination: point(
          41.0500,
          29.0200,
        ),
        status: "active",
        createdAt: activatedAt,
        activatedAt,
        expiresAt,
        routeDistanceMeters: 7000,
        routeDurationSeconds: 1200,
        encodedPolyline:
          "replacement_polyline",
        pricingVersion: null,
      },
    );

    batch.set(
      firestore
        .collection("driverActiveReturnRoutes")
        .doc(scenario.driverId),
      {
        routeId: replacementRouteId,
        activatedAt,
        expiresAt,
      },
    );

    await batch.commit();

    await rejectWithReason(
      acceptRideForDriver(
        {firestore},
        scenario.driverUid,
        mutation(
          scenario.rideId,
          "route_changed",
        ),
      ),
      "ride_match_offer_route_changed",
    );

    const offer = await firestore
      .collection("driverRideMatchOffers")
      .doc(scenario.offerId)
      .get();

    assert.equal(
      offer.get("status"),
      "active",
    );
  },
);

test(
  "valid authoritative offer is consumed atomically and replay remains idempotent",
  async () => {
    const scenario =
      await seedScenario();

    const input =
      mutation(
        scenario.rideId,
        "valid_accept",
      );

    const first =
      await acceptRideForDriver(
        {firestore},
        scenario.driverUid,
        input,
      );

    assert.equal(
      first.rideId,
      scenario.rideId,
    );

    assert.equal(
      first.status,
      "driverEnRoute",
    );

    assert.equal(
      first.version,
      2,
    );

    const [
      ride,
      passengerPointer,
      driverPointer,
      offer,
      events,
    ] = await Promise.all([
      firestore
        .collection("rides")
        .doc(scenario.rideId)
        .get(),
      firestore
        .collection("passengerActiveRides")
        .doc(scenario.passengerId)
        .get(),
      firestore
        .collection("driverActiveRides")
        .doc(scenario.driverId)
        .get(),
      firestore
        .collection("driverRideMatchOffers")
        .doc(scenario.offerId)
        .get(),
      firestore
        .collection("rides")
        .doc(scenario.rideId)
        .collection("events")
        .get(),
    ]);

    assert.equal(
      ride.get("driverId"),
      scenario.driverId,
    );

    assert.equal(
      ride.get("status"),
      "driverEnRoute",
    );

    assert.equal(
      ride.get("version"),
      2,
    );

    assert.equal(
      passengerPointer.get("status"),
      "driverEnRoute",
    );

    assert.equal(
      driverPointer.get("rideId"),
      scenario.rideId,
    );

    assert.equal(
      driverPointer.get("status"),
      "driverEnRoute",
    );

    assert.equal(
      offer.get("status"),
      "consumed",
    );

    assert.ok(
      offer.get("consumedAt") instanceof
        Timestamp,
    );

    assert.equal(
      events.docs.filter(
        (event) =>
          event.get("type") ===
          "rideDriverAccepted",
      ).length,
      1,
    );

    const consumedAt =
      (
        offer.get("consumedAt") as Timestamp
      ).toMillis();

    const replay =
      await acceptRideForDriver(
        {firestore},
        scenario.driverUid,
        input,
      );

    assert.deepEqual(
      replay,
      first,
    );

    const [
      replayOffer,
      replayEvents,
    ] = await Promise.all([
      firestore
        .collection("driverRideMatchOffers")
        .doc(scenario.offerId)
        .get(),
      firestore
        .collection("rides")
        .doc(scenario.rideId)
        .collection("events")
        .get(),
    ]);

    assert.equal(
      (
        replayOffer.get(
          "consumedAt",
        ) as Timestamp
      ).toMillis(),
      consumedAt,
    );

    assert.equal(
      replayEvents.docs.filter(
        (event) =>
          event.get("type") ===
          "rideDriverAccepted",
      ).length,
      1,
    );
  },
);
/* eslint-enable max-len */
