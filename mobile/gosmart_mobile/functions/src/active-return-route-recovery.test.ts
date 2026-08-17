/* eslint-disable require-jsdoc */
import assert from "node:assert/strict";
import test from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  ActiveReturnRouteRecoveryDependencies,
  ActiveReturnRouteSnapshot,
  recoverActiveReturnRoute,
} from "./active-return-route-recovery.js";

const nowMillis = 1_800_000_000_000;

class Snapshot
implements ActiveReturnRouteSnapshot {
  constructor(
    private readonly values:
      Record<string, unknown> | null,
  ) {}

  get exists(): boolean {
    return this.values !== null;
  }

  get(fieldPath: string): unknown {
    return this.values?.[fieldPath];
  }

  data(): Record<string, unknown> | undefined {
    return this.values ?? undefined;
  }
}

const lock = (
  overrides: Record<string, unknown> = {},
): Snapshot =>
  new Snapshot({
    routeId: "route-1",
    activatedAt:
      Timestamp.fromMillis(
        nowMillis - 60_000,
      ),
    expiresAt:
      Timestamp.fromMillis(
        nowMillis + 3_600_000,
      ),
    ...overrides,
  });

const route = (
  overrides: Record<string, unknown> = {},
): Snapshot =>
  new Snapshot({
    driverId: "driver-1",
    origin: {
      latitude: 41.0,
      longitude: 29.0,
    },
    destination: {
      latitude: 41.1,
      longitude: 29.1,
    },
    status: "active",
    createdAt:
      Timestamp.fromMillis(
        nowMillis - 120_000,
      ),
    activatedAt:
      Timestamp.fromMillis(
        nowMillis - 60_000,
      ),
    expiresAt:
      Timestamp.fromMillis(
        nowMillis + 3_600_000,
      ),
    routeDistanceMeters: 12000,
    routeDurationSeconds: 1800,
    encodedPolyline:
      "_p~iF~ps|U_ulLnnqC_mqNvxq`@",
    pricingVersion: null,
    ...overrides,
  });

const dependencies = (
  overrides:
    Partial<ActiveReturnRouteRecoveryDependencies> = {},
): ActiveReturnRouteRecoveryDependencies => ({
  loadDriverId: async () => "driver-1",
  readLock: async () => lock(),
  readRoute: async () => route(),
  now: () =>
    Timestamp.fromMillis(
      nowMillis,
    ),
  ...overrides,
});

const assertReason = async (
  action: () => Promise<unknown>,
  reason: string,
): Promise<void> => {
  await assert.rejects(
    action,
    (error: unknown) => {
      assert.ok(
        error instanceof HttpsError,
      );

      const details =
        error.details as
          | {reason?: unknown}
          | undefined;

      assert.equal(
        details?.reason,
        reason,
      );

      return true;
    },
  );
};

test(
  "missing active route lock returns null",
  async () => {
    let routeReads = 0;

    const result =
      await recoverActiveReturnRoute(
        dependencies({
          readLock: async () =>
            new Snapshot(null),
          readRoute: async () => {
            routeReads++;
            return route();
          },
        }),
        "uid-1",
      );

    assert.equal(result, null);
    assert.equal(routeReads, 0);
  },
);

test(
  "expired canonical lock returns null without route read",
  async () => {
    let routeReads = 0;

    const result =
      await recoverActiveReturnRoute(
        dependencies({
          readLock: async () =>
            lock({
              expiresAt:
                Timestamp.fromMillis(
                  nowMillis,
                ),
            }),
          readRoute: async () => {
            routeReads++;
            return route();
          },
        }),
        "uid-1",
      );

    assert.equal(result, null);
    assert.equal(routeReads, 0);
  },
);

test(
  "valid lock and route produce narrow recovery dto",
  async () => {
    const result =
      await recoverActiveReturnRoute(
        dependencies(),
        "uid-1",
      );

    assert.deepEqual(
      result,
      {
        routeId: "route-1",
        driverId: "driver-1",
        status: "active",
        origin: {
          latitude: 41.0,
          longitude: 29.0,
        },
        destination: {
          latitude: 41.1,
          longitude: 29.1,
        },
        createdAtMillis:
          nowMillis - 120_000,
        activatedAtMillis:
          nowMillis - 60_000,
        expiresAtMillis:
          nowMillis + 3_600_000,
        distanceMeters: 12000,
        durationSeconds: 1800,
        encodedPolyline:
          "_p~iF~ps|U_ulLnnqC_mqNvxq`@",
      },
    );
  },
);

test(
  "malformed lock fails closed",
  async () => {
    await assertReason(
      () =>
        recoverActiveReturnRoute(
          dependencies({
            readLock: async () =>
              lock({
                routeId: "",
              }),
          }),
          "uid-1",
        ),
      "active_return_route_inconsistent",
    );
  },
);

test(
  "future lock activation fails closed",
  async () => {
    await assertReason(
      () =>
        recoverActiveReturnRoute(
          dependencies({
            readLock: async () =>
              lock({
                activatedAt:
                  Timestamp.fromMillis(
                    nowMillis + 1_000,
                  ),
              }),
          }),
          "uid-1",
        ),
      "active_return_route_inconsistent",
    );
  },
);

test(
  "missing canonical route fails closed",
  async () => {
    await assertReason(
      () =>
        recoverActiveReturnRoute(
          dependencies({
            readRoute: async () =>
              new Snapshot(null),
          }),
          "uid-1",
        ),
      "active_return_route_inconsistent",
    );
  },
);

test(
  "driver mismatch fails closed",
  async () => {
    await assertReason(
      () =>
        recoverActiveReturnRoute(
          dependencies({
            readRoute: async () =>
              route({
                driverId: "driver-2",
              }),
          }),
          "uid-1",
        ),
      "active_return_route_inconsistent",
    );
  },
);

test(
  "lock and route timestamp mismatch fails closed",
  async () => {
    await assertReason(
      () =>
        recoverActiveReturnRoute(
          dependencies({
            readRoute: async () =>
              route({
                expiresAt:
                  Timestamp.fromMillis(
                    nowMillis + 7_200_000,
                  ),
              }),
          }),
          "uid-1",
        ),
      "active_return_route_inconsistent",
    );
  },
);

test(
  "invalid persisted route measurement fails closed",
  async () => {
    await assertReason(
      () =>
        recoverActiveReturnRoute(
          dependencies({
            readRoute: async () =>
              route({
                routeDistanceMeters: 0,
              }),
          }),
          "uid-1",
        ),
      "active_return_route_inconsistent",
    );
  },
);
