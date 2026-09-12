import assert from "node:assert/strict";
import test from "node:test";

import {
  quantizeNearbyDriverLocation,
} from "./nearby-driver-location-privacy-helpers.js";

const earthRadiusMeters = 6_371_000;

const degreesToRadians = (
  degrees: number,
): number =>
  (degrees * Math.PI) / 180;

const distanceMeters = (
  latitude1: number,
  longitude1: number,
  latitude2: number,
  longitude2: number,
): number => {
  const latitude1Radians =
    degreesToRadians(latitude1);

  const latitude2Radians =
    degreesToRadians(latitude2);

  const latitudeDelta =
    degreesToRadians(
      latitude2 - latitude1,
    );

  const longitudeDelta =
    degreesToRadians(
      longitude2 - longitude1,
    );

  const haversine =
    Math.sin(latitudeDelta / 2) ** 2 +
    Math.cos(latitude1Radians) *
      Math.cos(latitude2Radians) *
      Math.sin(longitudeDelta / 2) ** 2;

  return (
    2 *
    earthRadiusMeters *
    Math.asin(
      Math.min(
        1,
        Math.sqrt(haversine),
      ),
    )
  );
};

test(
  "returns only quantized latitude and longitude",
  () => {
    const result =
      quantizeNearbyDriverLocation(
        41.0082,
        28.9784,
      );

    assert.deepEqual(
      Object.keys(result).sort(),
      [
        "latitude",
        "longitude",
      ],
    );

    assert.notEqual(
      result.latitude,
      41.0082,
    );

    assert.notEqual(
      result.longitude,
      28.9784,
    );
  },
);

test(
  "is deterministic for the same coordinate",
  () => {
    const first =
      quantizeNearbyDriverLocation(
        41.0082,
        28.9784,
      );

    const second =
      quantizeNearbyDriverLocation(
        41.0082,
        28.9784,
      );

    assert.deepEqual(
      second,
      first,
    );
  },
);

test(
  "keeps nearby points inside the same Istanbul cell stable",
  () => {
    const center =
      quantizeNearbyDriverLocation(
        41.0082,
        28.9784,
      );

    const samples = [
      [41.00821, 28.9784],
      [41.00819, 28.9784],
      [41.0082, 28.97841],
      [41.0082, 28.97839],
    ] as const;

    for (
      const [
        latitude,
        longitude,
      ] of samples
    ) {
      assert.deepEqual(
        quantizeNearbyDriverLocation(
          latitude,
          longitude,
        ),
        center,
      );
    }
  },
);

test(
  "keeps representative displacement within the 71 meter bound",
  () => {
    const fixtures = [
      [0, 0],
      [41.0082, 28.9784],
      [60, 10],
      [85, 10],
      [89.999, 120],
      [90, 179],
      [-90, -179],
    ] as const;

    for (
      const [
        latitude,
        longitude,
      ] of fixtures
    ) {
      const quantized =
        quantizeNearbyDriverLocation(
          latitude,
          longitude,
        );

      assert.ok(
        distanceMeters(
          latitude,
          longitude,
          quantized.latitude,
          quantized.longitude,
        ) <= 71,
      );
    }
  },
);

test(
  "wraps the dateline without creating a large physical gap",
  () => {
    const east =
      quantizeNearbyDriverLocation(
        41.0082,
        179.9999,
      );

    const west =
      quantizeNearbyDriverLocation(
        41.0082,
        -179.9999,
      );

    assert.ok(
      distanceMeters(
        east.latitude,
        east.longitude,
        west.latitude,
        west.longitude,
      ) <= 101,
    );
  },
);

test(
  "normalizes positive and negative dateline representations consistently",
  () => {
    const positive =
      quantizeNearbyDriverLocation(
        41.0082,
        180,
      );

    const negative =
      quantizeNearbyDriverLocation(
        41.0082,
        -180,
      );

    assert.deepEqual(
      positive,
      negative,
    );
  },
);

test(
  "produces finite valid coordinates at both poles",
  () => {
    for (
      const latitude of [
        -90,
        90,
      ]
    ) {
      const result =
        quantizeNearbyDriverLocation(
          latitude,
          179,
        );

      assert.ok(
        Number.isFinite(
          result.latitude,
        ),
      );

      assert.ok(
        Number.isFinite(
          result.longitude,
        ),
      );

      assert.ok(
        result.latitude >= -90 &&
          result.latitude <= 90,
      );

      assert.ok(
        result.longitude >= -180 &&
          result.longitude < 180,
      );
    }
  },
);

test(
  "rejects invalid coordinates fail closed",
  () => {
    const invalidCoordinates = [
      [91, 0],
      [-91, 0],
      [0, 181],
      [0, -181],
      [Number.NaN, 0],
      [0, Number.NaN],
      [Number.POSITIVE_INFINITY, 0],
      [0, Number.POSITIVE_INFINITY],
    ] as const;

    for (
      const [
        latitude,
        longitude,
      ] of invalidCoordinates
    ) {
      assert.throws(
        () =>
          quantizeNearbyDriverLocation(
            latitude,
            longitude,
          ),
        TypeError,
      );
    }
  },
);
