import {
  encodeNearbyDriverGeoHash,
} from "./nearby-driver-geo-index-helpers.js";

import type {
  NearbyDriverGeoCoordinate,
} from "./nearby-driver-geo-index-helpers.js";

import {
  buildNearbyDriverGeoHashPrefixRange,
} from "./nearby-driver-geo-query-helpers.js";

import type {
  NearbyDriverGeoHashPrefixRange,
} from "./nearby-driver-geo-query-helpers.js";

import {
  decodeNearbyDriverGeoHashCellBounds,
} from "./nearby-driver-geohash-bounds-helpers.js";

import {
  deriveNearbyDriverAdjacentGeoHash,
} from "./nearby-driver-geohash-adjacency-helpers.js";

import {
  measureNearbyDriverGeoHashCoverage,
} from "./nearby-driver-geohash-coverage-measurement-helpers.js";

const EARTH_RADIUS_METERS =
  6_371_000;

export type NearbyDriverGeoHashCoveragePlanCell = {
  geohash: string;
  range: NearbyDriverGeoHashPrefixRange;
};

export type NearbyDriverGeoHashCoveragePlan = {
  precision: number;
  rangeCountUpperBound: number;
  cells: NearbyDriverGeoHashCoveragePlanCell[];
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

const longitudeDeltaEast = (
  fromLongitude: number,
  toLongitude: number,
): number => {
  let delta =
    normalizeLongitude(
      toLongitude -
      fromLongitude,
    );

  if (delta < 0) {
    delta +=
      360;
  }

  return delta;
};

const cellCenter = (
  geohash: string,
): NearbyDriverGeoCoordinate => {
  const bounds =
    decodeNearbyDriverGeoHashCellBounds(
      geohash,
    );

  return {
    latitude:
      (
        bounds.latitudeMinimum +
        bounds.latitudeMaximum
      ) / 2,
    longitude:
      normalizeLongitude(
        (
          bounds.longitudeMinimum +
          bounds.longitudeMaximum
        ) / 2,
      ),
  };
};

const rowIntersectsLatitudeBand = (
  geohash: string,
  latitudeMinimum: number,
  latitudeMaximum: number,
): boolean => {
  const bounds =
    decodeNearbyDriverGeoHashCellBounds(
      geohash,
    );

  return (
    bounds.latitudeMaximum >=
      latitudeMinimum &&
    bounds.latitudeMinimum <=
      latitudeMaximum
  );
};

export const buildNearbyDriverGeoHashCoveragePlan = (
  coordinate: NearbyDriverGeoCoordinate,
  radiusMeters: number,
  precision: number,
): NearbyDriverGeoHashCoveragePlan | null => {
  const measurement =
    measureNearbyDriverGeoHashCoverage(
      coordinate,
      radiusMeters,
      precision,
    );

  if (measurement === null) {
    return null;
  }

  const angularRadius =
    radiusMeters /
    EARTH_RADIUS_METERS;

  const centerLatitudeRadians =
    degreesToRadians(
      coordinate.latitude,
    );

  const latitudeMinimum =
    radiansToDegrees(
      centerLatitudeRadians -
      angularRadius,
    );

  const latitudeMaximum =
    radiansToDegrees(
      centerLatitudeRadians +
      angularRadius,
    );

  const centerGeoHash =
    encodeNearbyDriverGeoHash(
      coordinate,
      precision,
    );

  const rowSeeds = [
    centerGeoHash,
  ];

  let north =
    centerGeoHash;

  for (;;) {
    const next =
      deriveNearbyDriverAdjacentGeoHash(
        north,
        1,
        0,
      );

    if (next === null) {
      break;
    }

    if (
      !rowIntersectsLatitudeBand(
        next,
        latitudeMinimum,
        latitudeMaximum,
      )
    ) {
      break;
    }

    rowSeeds.push(
      next,
    );

    north =
      next;
  }

  let south =
    centerGeoHash;

  for (;;) {
    const next =
      deriveNearbyDriverAdjacentGeoHash(
        south,
        -1,
        0,
      );

    if (next === null) {
      break;
    }

    if (
      !rowIntersectsLatitudeBand(
        next,
        latitudeMinimum,
        latitudeMaximum,
      )
    ) {
      break;
    }

    rowSeeds.push(
      next,
    );

    south =
      next;
  }

  const selected =
    new Set<string>();

  for (const rowSeed of rowSeeds) {
    selected.add(
      rowSeed,
    );

    if (
      selected.size >
      measurement.rangeCount
    ) {
      return null;
    }

    const rowCenter =
      cellCenter(
        rowSeed,
      );

    const rowLatitudeRadians =
      degreesToRadians(
        rowCenter.latitude,
      );

    const cosineLatitude =
      Math.cos(
        rowLatitudeRadians,
      );

    if (
      !Number.isFinite(
        cosineLatitude,
      ) ||
      cosineLatitude <= 0
    ) {
      return null;
    }

    const longitudeRadiusDegrees =
      radiansToDegrees(
        radiusMeters /
        (
          EARTH_RADIUS_METERS *
          cosineLatitude
        ),
      );

    const westTarget =
      normalizeLongitude(
        coordinate.longitude -
        longitudeRadiusDegrees,
      );

    const eastTarget =
      normalizeLongitude(
        coordinate.longitude +
        longitudeRadiusDegrees,
      );

    let east =
      rowSeed;

    for (;;) {
      const bounds =
        decodeNearbyDriverGeoHashCellBounds(
          east,
        );

      const eastEdge =
        normalizeLongitude(
          bounds.longitudeMaximum,
        );

      const remaining =
        longitudeDeltaEast(
          eastEdge,
          eastTarget,
        );

      if (
        remaining === 0 ||
        remaining > 180
      ) {
        break;
      }

      const next =
        deriveNearbyDriverAdjacentGeoHash(
          east,
          0,
          1,
        );

      if (next === null) {
        return null;
      }

      if (
        selected.has(
          next,
        )
      ) {
        break;
      }

      selected.add(
        next,
      );

      if (
        selected.size >
        measurement.rangeCount
      ) {
        return null;
      }

      east =
        next;
    }

    let west =
      rowSeed;

    for (;;) {
      const bounds =
        decodeNearbyDriverGeoHashCellBounds(
          west,
        );

      const westEdge =
        normalizeLongitude(
          bounds.longitudeMinimum,
        );

      const remaining =
        longitudeDeltaEast(
          westTarget,
          westEdge,
        );

      if (
        remaining === 0 ||
        remaining > 180
      ) {
        break;
      }

      const next =
        deriveNearbyDriverAdjacentGeoHash(
          west,
          0,
          -1,
        );

      if (next === null) {
        return null;
      }

      if (
        selected.has(
          next,
        )
      ) {
        break;
      }

      selected.add(
        next,
      );

      if (
        selected.size >
        measurement.rangeCount
      ) {
        return null;
      }

      west =
        next;
    }
  }

  const geohashes =
    Array.from(
      selected,
    ).sort();

  return {
    precision:
      measurement.precision,
    rangeCountUpperBound:
      measurement.rangeCount,
    cells:
      geohashes.map(
        (geohash) => ({
          geohash,
          range:
            buildNearbyDriverGeoHashPrefixRange(
              geohash,
            ),
        }),
      ),
  };
};
