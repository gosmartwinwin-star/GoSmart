import {
  encodeNearbyDriverGeoHash,
} from "./nearby-driver-geo-index-helpers.js";

import type {
  NearbyDriverGeoCoordinate,
} from "./nearby-driver-geo-index-helpers.js";

import {
  decodeNearbyDriverGeoHashCellBounds,
} from "./nearby-driver-geohash-bounds-helpers.js";

import type {
  NearbyDriverGeoPrecisionMeasurement,
} from "./nearby-driver-geohash-precision-selection-helpers.js";

const EARTH_RADIUS_METERS =
  6_371_000;

const degreesToRadians = (
  degrees: number,
): number =>
  degrees *
  Math.PI /
  180;

const requireRadiusMeters = (
  value: number,
): number => {
  if (
    !Number.isFinite(value) ||
    value <= 0
  ) {
    throw new TypeError(
      "radiusMeters must be finite and positive",
    );
  }

  return value;
};

const requirePrecision = (
  value: number,
): number => {
  if (
    !Number.isInteger(value) ||
    value < 1 ||
    value > 12
  ) {
    throw new TypeError(
      "precision must be an integer within [1, 12]",
    );
  }

  return value;
};

export const measureNearbyDriverGeoHashCoverage = (
  coordinate: NearbyDriverGeoCoordinate,
  radiusMetersValue: number,
  precisionValue: number,
): NearbyDriverGeoPrecisionMeasurement | null => {
  const radiusMeters =
    requireRadiusMeters(
      radiusMetersValue,
    );

  const precision =
    requirePrecision(
      precisionValue,
    );

  const centerGeoHash =
    encodeNearbyDriverGeoHash(
      coordinate,
      precision,
    );

  const centerCell =
    decodeNearbyDriverGeoHashCellBounds(
      centerGeoHash,
    );

  const latitudeRadians =
    degreesToRadians(
      coordinate.latitude,
    );

  const angularRadiusRadians =
    radiusMeters /
    EARTH_RADIUS_METERS;

  const distanceToNearestPoleRadians =
    Math.PI / 2 -
    Math.abs(
      latitudeRadians,
    );

  if (
    angularRadiusRadians >=
    distanceToNearestPoleRadians
  ) {
    return null;
  }

  const latitudeMinimumRadians =
    latitudeRadians -
    angularRadiusRadians;

  const latitudeMaximumRadians =
    latitudeRadians +
    angularRadiusRadians;

  const maximumAbsoluteLatitude =
    Math.max(
      Math.abs(
        latitudeMinimumRadians,
      ),
      Math.abs(
        latitudeMaximumRadians,
      ),
    );

  const minimumAbsoluteLatitude =
    latitudeMinimumRadians <= 0 &&
    latitudeMaximumRadians >= 0 ?
      0 :
      Math.min(
        Math.abs(
          latitudeMinimumRadians,
        ),
        Math.abs(
          latitudeMaximumRadians,
        ),
      );

  const latitudeCellSpanRadians =
    degreesToRadians(
      centerCell.latitudeMaximum -
      centerCell.latitudeMinimum,
    );

  const longitudeCellSpanRadians =
    degreesToRadians(
      centerCell.longitudeMaximum -
      centerCell.longitudeMinimum,
    );

  const cellHeightMeters =
    EARTH_RADIUS_METERS *
    latitudeCellSpanRadians;

  const minimumCellWidthMeters =
    EARTH_RADIUS_METERS *
    Math.cos(
      maximumAbsoluteLatitude,
    ) *
    longitudeCellSpanRadians;

  const maximumCellWidthMeters =
    EARTH_RADIUS_METERS *
    Math.cos(
      minimumAbsoluteLatitude,
    ) *
    longitudeCellSpanRadians;

  if (
    !Number.isFinite(
      cellHeightMeters,
    ) ||
    !Number.isFinite(
      minimumCellWidthMeters,
    ) ||
    !Number.isFinite(
      maximumCellWidthMeters,
    ) ||
    cellHeightMeters <= 0 ||
    minimumCellWidthMeters <= 0 ||
    maximumCellWidthMeters <= 0
  ) {
    return null;
  }

  const diameterMeters =
    radiusMeters * 2;

  const latitudeRangeCount =
    Math.ceil(
      diameterMeters /
      cellHeightMeters,
    ) + 2;

  const longitudeRangeCount =
    Math.ceil(
      diameterMeters /
      minimumCellWidthMeters,
    ) + 2;

  const rangeCount =
    latitudeRangeCount *
    longitudeRangeCount;

  if (
    !Number.isSafeInteger(
      rangeCount,
    ) ||
    rangeCount < 1
  ) {
    return null;
  }

  const coveredAreaUpperBound =
    rangeCount *
    cellHeightMeters *
    maximumCellWidthMeters;

  const circleArea =
    Math.PI *
    radiusMeters *
    radiusMeters;

  const rawOverfetchAreaRatio =
    coveredAreaUpperBound /
    circleArea;

  if (
    !Number.isFinite(
      rawOverfetchAreaRatio,
    )
  ) {
    return null;
  }

  return {
    precision,
    rangeCount,
    overfetchAreaRatio:
      Math.max(
        1,
        rawOverfetchAreaRatio,
      ),
  };
};
