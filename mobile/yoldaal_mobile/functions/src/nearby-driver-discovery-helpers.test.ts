import assert from "node:assert/strict";
import test from "node:test";
import {Timestamp} from "firebase-admin/firestore";

import {
  projectNearbyDriverCandidate,
} from "./nearby-driver-discovery-helpers.js";

const now =
  Timestamp.fromMillis(1_000_000);

const activatedAt =
  Timestamp.fromMillis(900_000);

const expiresAt =
  Timestamp.fromMillis(2_000_000);

const validPresence = (
  updatedAt: Timestamp = now,
): Record<string, unknown> => ({
  driverId: "driver-1",
  latitude: 41.0082,
  longitude: 28.9784,
  updatedAt,
});

const validLock = (): Record<string, unknown> => ({
  routeId: "route-1",
  activatedAt,
  expiresAt,
});

const validRoute = (): Record<string, unknown> => ({
  driverId: "driver-1",
  status: "active",
  activatedAt,
  expiresAt,
  routeDistanceMeters: 12000,
  routeDurationSeconds: 1800,
  encodedPolyline: "encoded-route",
});

const project = (
  overrides: Partial<{
    driverId: string;
    returnRouteId: string;
    presenceData: unknown;
    activeReturnRouteData: unknown;
    returnRouteData: unknown;
    now: Timestamp;
  }> = {},
) => projectNearbyDriverCandidate({
  driverId: "driver-1",
  returnRouteId: "route-1",
  presenceData: validPresence(),
  activeReturnRouteData: validLock(),
  returnRouteData: validRoute(),
  now,
  ...overrides,
});

test(
  "projects only privacy-safe live location fields",
  () => {
    const result = project();

    assert.deepEqual(result, {
      latitude: 41.0082,
      longitude: 28.9784,
      updatedAtMillis: now.toMillis(),
    });

    assert.deepEqual(
      Object.keys(result ?? {}).sort(),
      [
        "latitude",
        "longitude",
        "updatedAtMillis",
      ],
    );

    assert.equal(
      "driverId" in (result ?? {}),
      false,
    );

    assert.equal(
      "returnRouteId" in (result ?? {}),
      false,
    );

    assert.equal(
      "encodedPolyline" in (result ?? {}),
      false,
    );

    assert.equal(
      "rating" in (result ?? {}),
      false,
    );
  },
);

test(
  "accepts presence exactly at the 20 second freshness boundary",
  () => {
    const result = project({
      presenceData: validPresence(
        Timestamp.fromMillis(
          now.toMillis() - 20_000,
        ),
      ),
    });

    assert.notEqual(result, null);
  },
);

test(
  "drops stale presence beyond the 20 second boundary",
  () => {
    const result = project({
      presenceData: validPresence(
        Timestamp.fromMillis(
          now.toMillis() - 20_001,
        ),
      ),
    });

    assert.equal(result, null);
  },
);

test(
  "drops future-dated presence",
  () => {
    const result = project({
      presenceData: validPresence(
        Timestamp.fromMillis(
          now.toMillis() + 1,
        ),
      ),
    });

    assert.equal(result, null);
  },
);

test(
  "drops malformed or authority-mismatched presence",
  () => {
    for (const presenceData of [
      null,
      {
        driverId: "other-driver",
        latitude: 41,
        longitude: 29,
        updatedAt: now,
      },
      {
        driverId: "driver-1",
        latitude: 91,
        longitude: 29,
        updatedAt: now,
      },
      {
        driverId: "driver-1",
        latitude: 41,
        longitude: 29,
        updatedAt: now,
        online: true,
      },
    ]) {
      assert.equal(
        project({presenceData}),
        null,
      );
    }
  },
);

test(
  "requires the active lock to identify the loaded return route",
  () => {
    assert.equal(
      project({
        returnRouteId: "route-2",
      }),
      null,
    );

    assert.equal(
      project({
        activeReturnRouteData: {
          ...validLock(),
          routeId: "route-2",
        },
      }),
      null,
    );
  },
);

test(
  "drops inactive expired or not-yet-active route locks",
  () => {
    assert.equal(
      project({
        activeReturnRouteData: {
          routeId: "route-1",
          activatedAt:
            Timestamp.fromMillis(
              now.toMillis() + 1,
            ),
          expiresAt,
        },
      }),
      null,
    );

    assert.equal(
      project({
        activeReturnRouteData: {
          routeId: "route-1",
          activatedAt,
          expiresAt: now,
        },
      }),
      null,
    );
  },
);

test(
  "requires canonical route driver status and lock timestamps",
  () => {
    for (const returnRouteData of [
      {
        ...validRoute(),
        driverId: "other-driver",
      },
      {
        ...validRoute(),
        status: "expired",
      },
      {
        ...validRoute(),
        activatedAt:
          Timestamp.fromMillis(
            activatedAt.toMillis() + 1,
          ),
      },
      {
        ...validRoute(),
        expiresAt:
          Timestamp.fromMillis(
            expiresAt.toMillis() + 1,
          ),
      },
    ]) {
      assert.equal(
        project({returnRouteData}),
        null,
      );
    }
  },
);

test(
  "requires canonical route measurement and polyline integrity",
  () => {
    for (const returnRouteData of [
      {
        ...validRoute(),
        routeDistanceMeters: 0,
      },
      {
        ...validRoute(),
        routeDurationSeconds: 0,
      },
      {
        ...validRoute(),
        encodedPolyline: "",
      },
    ]) {
      assert.equal(
        project({returnRouteData}),
        null,
      );
    }
  },
);

test(
  "does not invent radius limit profile or vehicle projection",
  () => {
    const result = project();

    assert.ok(result);

    for (const forbidden of [
      "distanceMeters",
      "radiusMeters",
      "rank",
      "name",
      "displayName",
      "vehicle",
      "vehiclePlate",
      "plate",
      "rating",
    ]) {
      assert.equal(
        forbidden in result,
        false,
      );
    }
  },
);
