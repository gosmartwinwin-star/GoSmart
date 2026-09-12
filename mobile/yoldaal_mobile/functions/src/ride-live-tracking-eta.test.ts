/* eslint-disable max-len */
import * as assert from "node:assert/strict";
import {test} from "node:test";

import {
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";

import {
  getRideLiveTrackingEta,
} from "./ride-live-tracking-eta.js";

type Data = Record<string, unknown>;

type FakeReference = {
  path: string;
};

const snapshot = (
  value: Data | undefined,
) => ({
  exists: value !== undefined,
  data: () => value,
});

const fakeFirestore = (
  initial: Record<string, Data> = {},
): {
  firestore: Firestore;
  read: (path: string) => Data | undefined;
} => {
  const store =
    new Map<string, Data>(
      Object.entries(initial),
    );

  const firestore = {
    collection: (name: string) => ({
      doc: (id: string): FakeReference => ({
        path: `${name}/${id}`,
      }),
    }),
    runTransaction: async (
      operation: (
        transaction: {
          get: (
            reference: FakeReference,
          ) => Promise<ReturnType<typeof snapshot>>;
          set: (
            reference: FakeReference,
            data: Data,
            options?: {merge?: boolean},
          ) => void;
        },
      ) => Promise<unknown>,
    ) => {
      const transaction = {
        get: async (
          reference: FakeReference,
        ) =>
          snapshot(store.get(reference.path)),
        set: (
          reference: FakeReference,
          data: Data,
          options?: {merge?: boolean},
        ) => {
          const previous =
            store.get(reference.path) ?? {};

          store.set(
            reference.path,
            options?.merge ?
              {...previous, ...data} :
              {...data},
          );
        },
      };

      return operation(transaction);
    },
  } as unknown as Firestore;

  return {
    firestore,
    read: (path: string) =>
      store.get(path),
  };
};

const origin = {
  latitude: 41.0082,
  longitude: 28.9784,
};

const destination = {
  latitude: 41.015,
  longitude: 28.99,
};

test("driverArrived never computes ETA", async () => {
  const {firestore} = fakeFirestore();

  let calls = 0;

  const result =
    await getRideLiveTrackingEta(
      {
        firestore,
        now: () =>
          Timestamp.fromMillis(100_000),
        computeDrivingMeasurement:
          async () => {
            calls += 1;
            return {
              distanceMeters: 100,
              durationSeconds: 20,
            };
          },
      },
      {
        rideId: "ride-1",
        driverId: "driver-1",
        status: "driverArrived",
        origin,
        destination: null,
      },
    );

  assert.deepEqual(result, {
    etaSeconds: null,
    etaUpdatedAtMillis: null,
  });

  assert.equal(calls, 0);
});

test("stale cache reserves and stores traffic-aware ETA", async () => {
  const {firestore, read} =
    fakeFirestore();

  let calls = 0;

  const result =
    await getRideLiveTrackingEta(
      {
        firestore,
        now: () =>
          Timestamp.fromMillis(100_000),
        createRefreshToken: () =>
          "refresh-1",
        computeDrivingMeasurement:
          async (actualOrigin, actualDestination) => {
            calls += 1;

            assert.deepEqual(
              actualOrigin,
              origin,
            );

            assert.deepEqual(
              actualDestination,
              destination,
            );

            return {
              distanceMeters: 1500,
              durationSeconds: 240,
            };
          },
      },
      {
        rideId: "ride-1",
        driverId: "driver-1",
        status: "driverEnRoute",
        origin,
        destination,
      },
    );

  assert.deepEqual(result, {
    etaSeconds: 240,
    etaUpdatedAtMillis: 100_000,
  });

  assert.equal(calls, 1);

  const stored =
    read(
      "rideLiveTrackingEtaCaches/ride-1",
    );

  assert.equal(stored?.driverId, "driver-1");
  assert.equal(stored?.status, "driverEnRoute");
  assert.equal(stored?.etaSeconds, 240);
  assert.equal(
    (
      stored?.etaUpdatedAt as Timestamp
    ).toMillis(),
    100_000,
  );
});

test("fresh ETA cache suppresses route recomputation for 30 seconds", async () => {
  const {firestore} =
    fakeFirestore({
      "rideLiveTrackingEtaCaches/ride-1": {
        rideId: "ride-1",
        driverId: "driver-1",
        status: "inProgress",
        etaSeconds: 180,
        etaUpdatedAt:
          Timestamp.fromMillis(80_000),
        refreshLeaseUntil:
          Timestamp.fromMillis(110_000),
      },
    });

  let calls = 0;

  const result =
    await getRideLiveTrackingEta(
      {
        firestore,
        now: () =>
          Timestamp.fromMillis(100_000),
        computeDrivingMeasurement:
          async () => {
            calls += 1;
            return {
              distanceMeters: 10,
              durationSeconds: 1,
            };
          },
      },
      {
        rideId: "ride-1",
        driverId: "driver-1",
        status: "inProgress",
        origin,
        destination,
      },
    );

  assert.deepEqual(result, {
    etaSeconds: 180,
    etaUpdatedAtMillis: 80_000,
  });

  assert.equal(calls, 0);
});

test("active refresh lease prevents duplicate provider call", async () => {
  const {firestore} =
    fakeFirestore({
      "rideLiveTrackingEtaCaches/ride-1": {
        rideId: "ride-1",
        driverId: "driver-1",
        status: "driverEnRoute",
        etaSeconds: 400,
        etaUpdatedAt:
          Timestamp.fromMillis(60_000),
        refreshLeaseUntil:
          Timestamp.fromMillis(110_000),
      },
    });

  let calls = 0;

  const result =
    await getRideLiveTrackingEta(
      {
        firestore,
        now: () =>
          Timestamp.fromMillis(100_000),
        computeDrivingMeasurement:
          async () => {
            calls += 1;
            return {
              distanceMeters: 1,
              durationSeconds: 1,
            };
          },
      },
      {
        rideId: "ride-1",
        driverId: "driver-1",
        status: "driverEnRoute",
        origin,
        destination,
      },
    );

  assert.deepEqual(result, {
    etaSeconds: null,
    etaUpdatedAtMillis: null,
  });

  assert.equal(calls, 0);
});

test("status change does not reuse ETA for previous destination", async () => {
  const {firestore} =
    fakeFirestore({
      "rideLiveTrackingEtaCaches/ride-1": {
        rideId: "ride-1",
        driverId: "driver-1",
        status: "driverEnRoute",
        etaSeconds: 30,
        etaUpdatedAt:
          Timestamp.fromMillis(99_000),
        refreshLeaseUntil:
          Timestamp.fromMillis(129_000),
      },
    });

  let calls = 0;

  const result =
    await getRideLiveTrackingEta(
      {
        firestore,
        now: () =>
          Timestamp.fromMillis(100_000),
        createRefreshToken: () =>
          "refresh-status-change",
        computeDrivingMeasurement:
          async () => {
            calls += 1;
            return {
              distanceMeters: 2000,
              durationSeconds: 300,
            };
          },
      },
      {
        rideId: "ride-1",
        driverId: "driver-1",
        status: "inProgress",
        origin,
        destination,
      },
    );

  assert.equal(calls, 1);
  assert.deepEqual(result, {
    etaSeconds: 300,
    etaUpdatedAtMillis: 100_000,
  });
});

test("provider failure is fail-soft and lease prevents immediate retry", async () => {
  const fixture = fakeFirestore();

  let calls = 0;

  const dependencies = {
    firestore: fixture.firestore,
    now: () =>
      Timestamp.fromMillis(100_000),
    createRefreshToken: () =>
      "failed-refresh",
    computeDrivingMeasurement:
      async () => {
        calls += 1;
        throw new Error("provider unavailable");
      },
  };

  const first =
    await getRideLiveTrackingEta(
      dependencies,
      {
        rideId: "ride-1",
        driverId: "driver-1",
        status: "driverEnRoute",
        origin,
        destination,
      },
    );

  const second =
    await getRideLiveTrackingEta(
      dependencies,
      {
        rideId: "ride-1",
        driverId: "driver-1",
        status: "driverEnRoute",
        origin,
        destination,
      },
    );

  assert.deepEqual(first, {
    etaSeconds: null,
    etaUpdatedAtMillis: null,
  });

  assert.deepEqual(second, {
    etaSeconds: null,
    etaUpdatedAtMillis: null,
  });

  assert.equal(calls, 1);
});
