/* eslint-disable max-len */
import * as assert from "node:assert/strict";
import {test} from "node:test";

import {Firestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {
  getActiveRideDriverTrackingForActor,
  validateRideLiveTrackingPayload,
} from "./ride-live-tracking-authority.js";

type DocumentData = Record<string, unknown>;

const document = (
  value: DocumentData | undefined,
): {
  exists: boolean;
  data: () => DocumentData | undefined;
} => ({
  exists: value !== undefined,
  data: () => value,
});

const fakeFirestore = (
  rides: Record<string, DocumentData>,
  presences: Record<string, DocumentData>,
): Firestore =>
  ({
    collection: (collectionName: string) => ({
      doc: (documentId: string) => ({
        get: async () => {
          if (collectionName === "rides") {
            return document(rides[documentId]);
          }

          if (collectionName === "driverLivePresences") {
            return document(presences[documentId]);
          }

          throw new Error(
            `Unexpected collection: ${collectionName}`,
          );
        },
      }),
    }),
  }) as unknown as Firestore;

const ride = (
  status = "driverEnRoute",
  driverId: string | null = "driver-1",
): DocumentData => ({
  passengerId: "passenger-1",
  driverId,
  status,
  pickup: {
    latitude: 41.01,
    longitude: 28.98,
    addressLabel: "Pickup",
  },
  dropoff: {
    latitude: 41.02,
    longitude: 29.01,
    addressLabel: "Dropoff",
  },
});

const presence = (
  updatedAtMillis: number,
): DocumentData => ({
  driverId: "driver-1",
  latitude: 41.0082,
  longitude: 28.9784,
  updatedAt: Timestamp.fromMillis(updatedAtMillis),
});

const reason = async (
  operation: () => Promise<unknown>,
): Promise<string | null> => {
  try {
    await operation();
    return null;
  } catch (error: unknown) {
    if (!(error instanceof HttpsError)) {
      throw error;
    }

    return (
      error.details as {reason?: string} | undefined
    )?.reason ?? null;
  }
};

test("tracking payload accepts exact rideId only", () => {
  assert.deepEqual(
    validateRideLiveTrackingPayload({
      rideId: "ride_123",
    }),
    {rideId: "ride_123"},
  );

  for (const value of [
    {},
    {rideId: ""},
    {rideId: "bad ride id"},
    {rideId: "ride_123", driverId: "driver-1"},
    null,
    [],
  ]) {
    assert.throws(
      () => validateRideLiveTrackingPayload(value),
      HttpsError,
    );
  }
});

test("active passenger receives fresh assigned driver location", async () => {
  const nowMillis = 100_000;

  const result =
    await getActiveRideDriverTrackingForActor(
      {
        firestore: fakeFirestore(
          {"ride-1": ride()},
          {"driver-1": presence(95_000)},
        ),
        now: () => Timestamp.fromMillis(nowMillis),
        loadApprovedDriverIdForActor: async () => {
          throw new Error(
            "Passenger path must not resolve driver identity",
          );
        },
      },
      "passenger-1",
      {rideId: "ride-1"},
    );

  assert.deepEqual(result, {
    latitude: 41.0082,
    longitude: 28.9784,
    updatedAtMillis: 95_000,
    etaSeconds: null,
    etaUpdatedAtMillis: null,
  });
});

test("assigned approved driver receives fresh location", async () => {
  const result =
    await getActiveRideDriverTrackingForActor(
      {
        firestore: fakeFirestore(
          {"ride-1": ride("inProgress")},
          {"driver-1": presence(100_000)},
        ),
        now: () => Timestamp.fromMillis(100_000),
        loadApprovedDriverIdForActor: async (
          _firestore,
          actorUid,
        ) => {
          assert.equal(actorUid, "driver-auth-1");
          return "driver-1";
        },
      },
      "driver-auth-1",
      {rideId: "ride-1"},
    );

  assert.equal(result.latitude, 41.0082);
  assert.equal(result.longitude, 28.9784);
});

test("outsider cannot read active ride tracking", async () => {
  const result = await reason(() =>
    getActiveRideDriverTrackingForActor(
      {
        firestore: fakeFirestore(
          {"ride-1": ride()},
          {"driver-1": presence(100_000)},
        ),
        now: () => Timestamp.fromMillis(100_000),
        loadApprovedDriverIdForActor: async () =>
          "different-driver",
      },
      "outsider-auth",
      {rideId: "ride-1"},
    ),
  );

  assert.equal(
    result,
    "ride_tracking_participant_required",
  );
});

test("non-driver identity failure is normalized to participant denial", async () => {
  const result = await reason(() =>
    getActiveRideDriverTrackingForActor(
      {
        firestore: fakeFirestore(
          {"ride-1": ride()},
          {"driver-1": presence(100_000)},
        ),
        loadApprovedDriverIdForActor: async () => {
          throw new HttpsError(
            "failed-precondition",
            "Driver unavailable",
            {reason: "driver_profile_required"},
          );
        },
      },
      "outsider-auth",
      {rideId: "ride-1"},
    ),
  );

  assert.equal(
    result,
    "ride_tracking_participant_required",
  );
});

test("unassigned matching ride fails closed without leaking to outsider", async () => {
  const firestore = fakeFirestore(
    {"ride-1": ride("matching", null)},
    {},
  );

  const passengerResult = await reason(() =>
    getActiveRideDriverTrackingForActor(
      {firestore},
      "passenger-1",
      {rideId: "ride-1"},
    ),
  );

  assert.equal(
    passengerResult,
    "ride_tracking_unavailable",
  );

  const outsiderResult = await reason(() =>
    getActiveRideDriverTrackingForActor(
      {
        firestore,
        loadApprovedDriverIdForActor: async () =>
          "different-driver",
      },
      "outsider-auth",
      {rideId: "ride-1"},
    ),
  );

  assert.equal(
    outsiderResult,
    "ride_tracking_participant_required",
  );
});
test("matching and terminal rides fail closed for participant", async () => {
  for (const status of [
    "matching",
    "completed",
    "cancelled",
    "expired",
  ]) {
    const result = await reason(() =>
      getActiveRideDriverTrackingForActor(
        {
          firestore: fakeFirestore(
            {"ride-1": ride(status)},
            {"driver-1": presence(100_000)},
          ),
          now: () => Timestamp.fromMillis(100_000),
        },
        "passenger-1",
        {rideId: "ride-1"},
      ),
    );

    assert.equal(result, "ride_tracking_unavailable");
  }
});

test("location is fresh at exact 20 second boundary", async () => {
  const result =
    await getActiveRideDriverTrackingForActor(
      {
        firestore: fakeFirestore(
          {"ride-1": ride("driverArrived")},
          {"driver-1": presence(80_000)},
        ),
        now: () => Timestamp.fromMillis(100_000),
      },
      "passenger-1",
      {rideId: "ride-1"},
    );

  assert.deepEqual(result, {
    latitude: 41.0082,
    longitude: 28.9784,
    updatedAtMillis: 80_000,
    etaSeconds: null,
    etaUpdatedAtMillis: null,
  });
});

test("location older than 20 seconds returns no authoritative location", async () => {
  const result =
    await getActiveRideDriverTrackingForActor(
      {
        firestore: fakeFirestore(
          {"ride-1": ride()},
          {"driver-1": presence(79_999)},
        ),
        now: () => Timestamp.fromMillis(100_000),
      },
      "passenger-1",
      {rideId: "ride-1"},
    );

  assert.deepEqual(result, {
    latitude: null,
    longitude: null,
    updatedAtMillis: null,
    etaSeconds: null,
    etaUpdatedAtMillis: null,
  });
});

test("missing presence returns no authoritative location", async () => {
  const result =
    await getActiveRideDriverTrackingForActor(
      {
        firestore: fakeFirestore(
          {"ride-1": ride()},
          {},
        ),
        now: () => Timestamp.fromMillis(100_000),
      },
      "passenger-1",
      {rideId: "ride-1"},
    );

  assert.deepEqual(result, {
    latitude: null,
    longitude: null,
    updatedAtMillis: null,
    etaSeconds: null,
    etaUpdatedAtMillis: null,
  });
});

test("malformed or future presence fails closed", async () => {
  const malformed = await reason(() =>
    getActiveRideDriverTrackingForActor(
      {
        firestore: fakeFirestore(
          {"ride-1": ride()},
          {
            "driver-1": {
              driverId: "other-driver",
              latitude: 41,
              longitude: 29,
              updatedAt: Timestamp.fromMillis(100_000),
            },
          },
        ),
        now: () => Timestamp.fromMillis(100_000),
      },
      "passenger-1",
      {rideId: "ride-1"},
    ),
  );

  assert.equal(
    malformed,
    "driver_live_presence_invalid",
  );

  const future = await reason(() =>
    getActiveRideDriverTrackingForActor(
      {
        firestore: fakeFirestore(
          {"ride-1": ride()},
          {"driver-1": presence(100_001)},
        ),
        now: () => Timestamp.fromMillis(100_000),
      },
      "passenger-1",
      {rideId: "ride-1"},
    ),
  );

  assert.equal(
    future,
    "driver_live_presence_invalid",
  );
});
test("tracking authority resolves ETA from server ride destination", async () => {
  const calls: Array<Record<string, unknown>> = [];

  const result =
    await getActiveRideDriverTrackingForActor(
      {
        firestore: fakeFirestore(
          {"ride-1": ride("driverEnRoute")},
          {"driver-1": presence(100_000)},
        ),
        now: () =>
          Timestamp.fromMillis(100_000),
        resolveEta: async (input) => {
          calls.push(input);

          return {
            etaSeconds: 120,
            etaUpdatedAtMillis: 100_000,
          };
        },
      },
      "passenger-1",
      {rideId: "ride-1"},
    );

  assert.equal(calls.length, 1);

  assert.deepEqual(calls[0], {
    rideId: "ride-1",
    driverId: "driver-1",
    status: "driverEnRoute",
    origin: {
      latitude: 41.0082,
      longitude: 28.9784,
    },
    destination: {
      latitude: 41.01,
      longitude: 28.98,
    },
  });

  assert.equal(result.etaSeconds, 120);
  assert.equal(
    result.etaUpdatedAtMillis,
    100_000,
  );
});

test("driverArrived returns no ETA without destination authority", async () => {
  let calls = 0;

  const result =
    await getActiveRideDriverTrackingForActor(
      {
        firestore: fakeFirestore(
          {"ride-1": ride("driverArrived")},
          {"driver-1": presence(100_000)},
        ),
        now: () =>
          Timestamp.fromMillis(100_000),
        resolveEta: async () => {
          calls += 1;

          return {
            etaSeconds: 1,
            etaUpdatedAtMillis: 100_000,
          };
        },
      },
      "passenger-1",
      {rideId: "ride-1"},
    );

  assert.equal(calls, 0);
  assert.equal(result.etaSeconds, null);
  assert.equal(
    result.etaUpdatedAtMillis,
    null,
  );
});

test("inProgress ETA destination is server ride dropoff", async () => {
  let destination:
    Record<string, unknown> | null =
      null;

  const result =
    await getActiveRideDriverTrackingForActor(
      {
        firestore: fakeFirestore(
          {"ride-1": ride("inProgress")},
          {"driver-1": presence(100_000)},
        ),
        now: () =>
          Timestamp.fromMillis(100_000),
        resolveEta: async (input) => {
          destination =
            input.destination as
              Record<string, unknown>;

          return {
            etaSeconds: 300,
            etaUpdatedAtMillis: 100_000,
          };
        },
      },
      "passenger-1",
      {rideId: "ride-1"},
    );

  assert.deepEqual(destination, {
    latitude: 41.02,
    longitude: 29.01,
  });

  assert.equal(result.etaSeconds, 300);
});
