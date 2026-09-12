import assert from "node:assert/strict";
import test from "node:test";

import {
  measureNearbyDriverGeoHashCoverage,
} from "./nearby-driver-geohash-coverage-measurement-helpers.js";

const istanbul = {
  latitude: 41.0082,
  longitude: 28.9784,
};

test(
  "reproduces verified Istanbul 3000 meter range counts",
  () => {
    const expected = [
      {
        precision: 4,
        rangeCount: 9,
      },
      {
        precision: 5,
        rangeCount: 16,
      },
      {
        precision: 6,
        rangeCount: 108,
      },
      {
        precision: 7,
        rangeCount: 2310,
      },
    ];

    for (const item of expected) {
      const measurement =
        measureNearbyDriverGeoHashCoverage(
          istanbul,
          3000,
          item.precision,
        );

      assert.notEqual(
        measurement,
        null,
      );

      assert.equal(
        measurement?.rangeCount,
        item.rangeCount,
      );
    }
  },
);

test(
  "produces finite overfetch ratios at least one",
  () => {
    for (
      const precision of
      [
        4,
        5,
        6,
        7,
      ]
    ) {
      const measurement =
        measureNearbyDriverGeoHashCoverage(
          istanbul,
          3000,
          precision,
        );

      assert.notEqual(
        measurement,
        null,
      );

      assert.equal(
        Number.isFinite(
          measurement?.overfetchAreaRatio,
        ),
        true,
      );

      assert.ok(
        (
          measurement?.overfetchAreaRatio ??
          0
        ) >= 1,
      );
    }
  },
);

test(
  "ordinary Istanbul overfetch decreases from precision four through seven",
  () => {
    const ratios =
      [
        4,
        5,
        6,
        7,
      ].map(
        (precision) =>
          measureNearbyDriverGeoHashCoverage(
            istanbul,
            3000,
            precision,
          )?.overfetchAreaRatio ??
          Number.POSITIVE_INFINITY,
      );

    assert.ok(
      ratios[0] >
      ratios[1],
    );

    assert.ok(
      ratios[1] >
      ratios[2],
    );

    assert.ok(
      ratios[2] >
      ratios[3],
    );
  },
);

test(
  "reproduces verified latitude dependent precision five fanout",
  () => {
    const fixtures = [
      {
        latitude: 0,
        rangeCount: 16,
      },
      {
        latitude: 60,
        rangeCount: 20,
      },
      {
        latitude: 75,
        rangeCount: 28,
      },
      {
        latitude: 85,
        rangeCount: 68,
      },
    ];

    for (const fixture of fixtures) {
      const measurement =
        measureNearbyDriverGeoHashCoverage(
          {
            latitude:
              fixture.latitude,
            longitude: 28,
          },
          3000,
          5,
        );

      assert.equal(
        measurement?.rangeCount,
        fixture.rangeCount,
      );
    }
  },
);

test(
  "is symmetric across the dateline",
  () => {
    const east =
      measureNearbyDriverGeoHashCoverage(
        {
          latitude: 41.0082,
          longitude: 179.999,
        },
        3000,
        5,
      );

    const west =
      measureNearbyDriverGeoHashCoverage(
        {
          latitude: 41.0082,
          longitude: -179.999,
        },
        3000,
        5,
      );

    assert.notEqual(
      east,
      null,
    );

    assert.notEqual(
      west,
      null,
    );

    assert.equal(
      east?.rangeCount,
      west?.rangeCount,
    );

    assert.ok(
      Math.abs(
        (
          east?.overfetchAreaRatio ??
          0
        ) -
        (
          west?.overfetchAreaRatio ??
          0
        ),
      ) <
      1e-12,
    );
  },
);

test(
  "fails closed when the requested circle reaches a pole",
  () => {
    assert.equal(
      measureNearbyDriverGeoHashCoverage(
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
      measureNearbyDriverGeoHashCoverage(
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
  "rejects invalid radius values",
  () => {
    for (
      const radius of
      [
        0,
        -1,
        Number.NaN,
        Number.POSITIVE_INFINITY,
      ]
    ) {
      assert.throws(
        () =>
          measureNearbyDriverGeoHashCoverage(
            istanbul,
            radius,
            5,
          ),
        TypeError,
      );
    }
  },
);

test(
  "rejects invalid precision values",
  () => {
    for (
      const precision of
      [
        0,
        13,
        4.5,
        Number.NaN,
      ]
    ) {
      assert.throws(
        () =>
          measureNearbyDriverGeoHashCoverage(
            istanbul,
            3000,
            precision,
          ),
        TypeError,
      );
    }
  },
);

test(
  "rejects invalid coordinates through the existing encoder",
  () => {
    assert.throws(
      () =>
        measureNearbyDriverGeoHashCoverage(
          {
            latitude: 91,
            longitude: 0,
          },
          3000,
          5,
        ),
      TypeError,
    );

    assert.throws(
      () =>
        measureNearbyDriverGeoHashCoverage(
          {
            latitude: 0,
            longitude: 181,
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

    measureNearbyDriverGeoHashCoverage(
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
