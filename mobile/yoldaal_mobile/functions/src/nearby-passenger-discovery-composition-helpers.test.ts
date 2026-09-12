import assert from "node:assert/strict";
import test from "node:test";

import {
  composeNearbyPassengerDiscovery,
  PASSENGER_DISCOVERY_MAX_RESULTS,
  PASSENGER_DISCOVERY_RADIUS_METERS,
} from "./nearby-passenger-discovery-composition-helpers.js";

import type {
  NearbyPassengerDiscoveryCandidate,
} from "./nearby-passenger-discovery-composition-helpers.js";

import type {
  RideMatchMeasurement,
} from "./ride-match-offer-helpers.js";

const pickup = {
  latitude: 41.0082,
  longitude: 28.9784,
};

const latitudeOffsetForMeters = (
  meters: number,
): number =>
  (
    meters /
    6_371_000
  ) *
  180 /
  Math.PI;

const compatibleMeasurement = (
  overrides:
    Partial<RideMatchMeasurement> =
  {},
): RideMatchMeasurement => ({
  pickupRouteIndex: 1,
  dropoffRouteIndex: 2,
  pickupDetourMeters: 500,
  pickupDetourSeconds: 120,
  dropoffDetourMeters: 600,
  dropoffDetourSeconds: 150,
  ...overrides,
});

const candidate = (
  internalDriverId: string,
  northMeters: number,
  updatedAtMillis: number,
  measurement:
    RideMatchMeasurement =
  compatibleMeasurement(),
): NearbyPassengerDiscoveryCandidate => ({
  internalDriverId,
  projection: {
    latitude:
      pickup.latitude +
      latitudeOffsetForMeters(
        northMeters,
      ),
    longitude:
      pickup.longitude,
    updatedAtMillis,
  },
  measurement,
});

test(
  "freezes passenger discovery radius and max results",
  () => {
    assert.equal(
      PASSENGER_DISCOVERY_RADIUS_METERS,
      3000,
    );

    assert.equal(
      PASSENGER_DISCOVERY_MAX_RESULTS,
      8,
    );
  },
);

test(
  "excludes return-route incompatible candidates",
  () => {
    const result =
      composeNearbyPassengerDiscovery(
        pickup,
        [
          candidate(
            "incompatible",
            20,
            9000,
            compatibleMeasurement({
              pickupRouteIndex: 2,
              dropoffRouteIndex: 1,
            }),
          ),
          candidate(
            "compatible",
            400,
            5000,
          ),
        ],
      );

    assert.equal(
      result.length,
      1,
    );

    assert.equal(
      result[0].updatedAtMillis,
      5000,
    );
  },
);

test(
  "excludes compatible candidates outside exact 3000 meter radius",
  () => {
    const result =
      composeNearbyPassengerDiscovery(
        pickup,
        [
          candidate(
            "inside",
            2900,
            5000,
          ),
          candidate(
            "outside",
            3100,
            9000,
          ),
        ],
      );

    assert.equal(
      result.length,
      1,
    );

    assert.equal(
      result[0].updatedAtMillis,
      5000,
    );
  },
);

test(
  "orders by exact server distance ascending before freshness",
  () => {
    const result =
      composeNearbyPassengerDiscovery(
        pickup,
        [
          candidate(
            "far-fresh",
            900,
            9000,
          ),
          candidate(
            "near-old",
            300,
            1000,
          ),
        ],
      );

    assert.deepEqual(
      result.map(
        (item) =>
          item.updatedAtMillis,
      ),
      [
        1000,
        9000,
      ],
    );
  },
);

test(
  "uses updatedAtMillis descending when exact distances tie",
  () => {
    const result =
      composeNearbyPassengerDiscovery(
        pickup,
        [
          candidate(
            "old",
            400,
            1000,
          ),
          candidate(
            "fresh",
            400,
            2000,
          ),
        ],
      );

    assert.deepEqual(
      result.map(
        (item) =>
          item.updatedAtMillis,
      ),
      [
        2000,
        1000,
      ],
    );
  },
);

test(
  "uses internal driver id as deterministic final tie break",
  () => {
    const result =
      composeNearbyPassengerDiscovery(
        pickup,
        [
          candidate(
            "driver-b",
            500,
            2000,
          ),
          candidate(
            "driver-a",
            -500,
            2000,
          ),
        ],
      );

    assert.equal(
      result.length,
      2,
    );

    assert.ok(
      result[0].latitude <
      pickup.latitude,
    );

    assert.ok(
      result[1].latitude >
      pickup.latitude,
    );

    for (const item of result) {
      assert.deepEqual(
        Object.keys(item).sort(),
        [
          "latitude",
          "longitude",
          "updatedAtMillis",
        ],
      );

      assert.equal(
        Object.prototype.hasOwnProperty.call(
          item,
          "driverId",
        ),
        false,
      );

      assert.equal(
        Object.prototype.hasOwnProperty.call(
          item,
          "internalDriverId",
        ),
        false,
      );
    }
  },
);

test(
  "limits public results to eight after filtering and ordering",
  () => {
    const candidates =
      Array.from(
        {
          length: 12,
        },
        (
          _,
          index,
        ) =>
          candidate(
            `driver-${index}`,
            100 + index * 100,
            10_000 - index,
          ),
      );

    const result =
      composeNearbyPassengerDiscovery(
        pickup,
        candidates,
      );

    assert.equal(
      result.length,
      8,
    );

    assert.deepEqual(
      result.map(
        (item) =>
          item.updatedAtMillis,
      ),
      [
        10000,
        9999,
        9998,
        9997,
        9996,
        9995,
        9994,
        9993,
      ],
    );
  },
);

test(
  "applies privacy quantization to selected public coordinates only",
  () => {
    const source =
      candidate(
        "driver-a",
        432,
        5000,
      );

    const result =
      composeNearbyPassengerDiscovery(
        pickup,
        [
          source,
        ],
      );

    assert.equal(
      result.length,
      1,
    );

    assert.equal(
      result[0].updatedAtMillis,
      source.projection.updatedAtMillis,
    );

    assert.ok(
      result[0].latitude !==
        source.projection.latitude ||
      result[0].longitude !==
        source.projection.longitude,
    );

    assert.equal(
      Object.prototype.hasOwnProperty.call(
        result[0],
        "distanceMeters",
      ),
      false,
    );

    assert.equal(
      Object.prototype.hasOwnProperty.call(
        result[0],
        "measurement",
      ),
      false,
    );
  },
);

test(
  "fails closed for invalid internal ids and invalid exact coordinates",
  () => {
    const blankId =
      candidate(
        "   ",
        200,
        5000,
      );

    assert.deepEqual(
      composeNearbyPassengerDiscovery(
        pickup,
        [
          blankId,
        ],
      ),
      [],
    );

    const invalidCoordinate =
      candidate(
        "driver-invalid",
        200,
        5000,
      );

    invalidCoordinate.projection.latitude =
      91;

    assert.throws(
      () =>
        composeNearbyPassengerDiscovery(
          pickup,
          [
            invalidCoordinate,
          ],
        ),
      TypeError,
    );
  },
);

test(
  "does not mutate caller candidates",
  () => {
    const first =
      candidate(
        "driver-b",
        800,
        1000,
      );

    const second =
      candidate(
        "driver-a",
        300,
        2000,
      );

    const input = [
      first,
      second,
    ];

    const before =
      JSON.stringify(input);

    composeNearbyPassengerDiscovery(
      pickup,
      input,
    );

    assert.equal(
      JSON.stringify(input),
      before,
    );
  },
);
