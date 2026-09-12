import assert from "node:assert/strict";
import test from "node:test";

import {
  encodeNearbyDriverGeoHash,
} from "./nearby-driver-geo-index-helpers.js";

import {
  buildNearbyDriverGeoHashCoveragePlan,
} from "./nearby-driver-geohash-coverage-plan-helpers.js";

const EARTH_RADIUS_METERS =
  6_371_000;

const istanbul = {
  latitude: 41.0082,
  longitude: 28.9784,
};

const degreesToRadians = (
  degrees: number,
): number =>
  degrees *
  Math.PI /
  180;

const radiansToDegrees = (
  radians: number,
): number =>
  radians *
  180 /
  Math.PI;

const normalizeLongitude = (
  value: number,
): number => {
  let result =
    value;

  while (result < -180) {
    result +=
      360;
  }

  while (result >= 180) {
    result -=
      360;
  }

  return result;
};

const destinationPoint = (
  center: {
    latitude: number;
    longitude: number;
  },
  distanceMeters: number,
  bearingRadians: number,
): {
  latitude: number;
  longitude: number;
} => {
  const angularDistance =
    distanceMeters /
    EARTH_RADIUS_METERS;

  const latitude1 =
    degreesToRadians(
      center.latitude,
    );

  const longitude1 =
    degreesToRadians(
      center.longitude,
    );

  const latitude2 =
    Math.asin(
      Math.sin(
        latitude1,
      ) *
        Math.cos(
          angularDistance,
        ) +
      Math.cos(
        latitude1,
      ) *
        Math.sin(
          angularDistance,
        ) *
        Math.cos(
          bearingRadians,
        ),
    );

  const longitude2 =
    longitude1 +
    Math.atan2(
      Math.sin(
        bearingRadians,
      ) *
        Math.sin(
          angularDistance,
        ) *
        Math.cos(
          latitude1,
        ),
      Math.cos(
        angularDistance,
      ) -
        Math.sin(
          latitude1,
        ) *
          Math.sin(
            latitude2,
          ),
    );

  return {
    latitude:
      radiansToDegrees(
        latitude2,
      ),
    longitude:
      normalizeLongitude(
        radiansToDegrees(
          longitude2,
        ),
      ),
  };
};

const assertSampleCoverage = (
  center: {
    latitude: number;
    longitude: number;
  },
  radiusMeters: number,
  precision: number,
): number => {
  const plan =
    buildNearbyDriverGeoHashCoveragePlan(
      center,
      radiusMeters,
      precision,
    );

  assert.notEqual(
    plan,
    null,
  );

  const selected =
    new Set(
      plan?.cells.map(
        (cell) =>
          cell.geohash,
      ),
    );

  let samples =
    0;

  const radialFractions = [
    0,
    0.25,
    0.5,
    0.75,
    1,
  ];

  for (
    let bearingDegrees = 0;
    bearingDegrees < 360;
    bearingDegrees += 5
  ) {
    const bearingRadians =
      degreesToRadians(
        bearingDegrees,
      );

    for (
      const fraction of
      radialFractions
    ) {
      const point =
        destinationPoint(
          center,
          radiusMeters *
            fraction,
          bearingRadians,
        );

      const geohash =
        encodeNearbyDriverGeoHash(
          point,
          precision,
        );

      assert.equal(
        selected.has(
          geohash,
        ),
        true,
      );

      samples +=
        1;
    }
  }

  return samples;
};

test(
  "covers sampled Istanbul circles at precisions four through six",
  () => {
    let samples =
      0;

    for (
      const precision of
      [
        4,
        5,
        6,
      ]
    ) {
      samples +=
        assertSampleCoverage(
          istanbul,
          3000,
          precision,
        );
    }

    assert.equal(
      samples,
      1080,
    );
  },
);

test(
  "covers sampled latitude dependent precision five circles",
  () => {
    let samples =
      0;

    for (
      const latitude of
      [
        60,
        75,
        85,
      ]
    ) {
      samples +=
        assertSampleCoverage(
          {
            latitude,
            longitude: 28,
          },
          3000,
          5,
        );
    }

    assert.equal(
      samples,
      1080,
    );
  },
);

test(
  "covers sampled circles on both sides of the dateline",
  () => {
    const eastSamples =
      assertSampleCoverage(
        {
          latitude: 41.0082,
          longitude: 179.999,
        },
        3000,
        5,
      );

    const westSamples =
      assertSampleCoverage(
        {
          latitude: 41.0082,
          longitude: -179.999,
        },
        3000,
        5,
      );

    assert.equal(
      eastSamples +
      westSamples,
      720,
    );
  },
);

test(
  "returns deterministic unique lexicographically sorted cells",
  () => {
    const first =
      buildNearbyDriverGeoHashCoveragePlan(
        istanbul,
        3000,
        5,
      );

    const second =
      buildNearbyDriverGeoHashCoveragePlan(
        istanbul,
        3000,
        5,
      );

    assert.deepEqual(
      first,
      second,
    );

    const geohashes =
      first?.cells.map(
        (cell) =>
          cell.geohash,
      ) ??
      [];

    assert.deepEqual(
      geohashes,
      [
        ...geohashes,
      ].sort(),
    );

    assert.equal(
      new Set(
        geohashes,
      ).size,
      geohashes.length,
    );
  },
);

test(
  "produces canonical prefix ranges for every planned cell",
  () => {
    const plan =
      buildNearbyDriverGeoHashCoveragePlan(
        istanbul,
        3000,
        5,
      );

    assert.notEqual(
      plan,
      null,
    );

    for (
      const cell of
      plan?.cells ??
      []
    ) {
      assert.equal(
        cell.range.startInclusive,
        cell.geohash,
      );

      assert.equal(
        typeof cell.range.endExclusive,
        "string",
      );

      assert.ok(
        cell.range.startInclusive <
        cell.range.endExclusive,
      );
    }
  },
);

test(
  "never exceeds the conservative measurement range bound",
  () => {
    const fixtures = [
      {
        latitude: 41.0082,
        longitude: 28.9784,
        precision: 4,
      },
      {
        latitude: 41.0082,
        longitude: 28.9784,
        precision: 5,
      },
      {
        latitude: 41.0082,
        longitude: 28.9784,
        precision: 6,
      },
      {
        latitude: 60,
        longitude: 28,
        precision: 5,
      },
      {
        latitude: 75,
        longitude: 28,
        precision: 5,
      },
      {
        latitude: 85,
        longitude: 28,
        precision: 5,
      },
    ];

    for (const fixture of fixtures) {
      const plan =
        buildNearbyDriverGeoHashCoveragePlan(
          {
            latitude:
              fixture.latitude,
            longitude:
              fixture.longitude,
          },
          3000,
          fixture.precision,
        );

      assert.notEqual(
        plan,
        null,
      );

      assert.ok(
        (
          plan?.cells.length ??
          Number.POSITIVE_INFINITY
        ) <=
        (
          plan?.rangeCountUpperBound ??
          0
        ),
      );
    }
  },
);

test(
  "fails closed when the requested circle reaches a pole",
  () => {
    assert.equal(
      buildNearbyDriverGeoHashCoveragePlan(
        {
          latitude: 89.99,
          longitude: 0,
        },
        3000,
        5,
      ),
      null,
    );

    assert.equal(
      buildNearbyDriverGeoHashCoveragePlan(
        {
          latitude: -89.99,
          longitude: 0,
        },
        3000,
        5,
      ),
      null,
    );
  },
);

test(
  "rejects invalid radius precision and coordinate values",
  () => {
    assert.throws(
      () =>
        buildNearbyDriverGeoHashCoveragePlan(
          istanbul,
          0,
          5,
        ),
      TypeError,
    );

    assert.throws(
      () =>
        buildNearbyDriverGeoHashCoveragePlan(
          istanbul,
          3000,
          13,
        ),
      TypeError,
    );

    assert.throws(
      () =>
        buildNearbyDriverGeoHashCoveragePlan(
          {
            latitude: 91,
            longitude: 0,
          },
          3000,
          5,
        ),
      TypeError,
    );
  },
);

test(
  "does not mutate the caller coordinate",
  () => {
    const coordinate = {
      latitude: 41.0082,
      longitude: 28.9784,
    };

    const before =
      JSON.stringify(
        coordinate,
      );

    buildNearbyDriverGeoHashCoveragePlan(
      coordinate,
      3000,
      5,
    );

    assert.equal(
      JSON.stringify(
        coordinate,
      ),
      before,
    );
  },
);
