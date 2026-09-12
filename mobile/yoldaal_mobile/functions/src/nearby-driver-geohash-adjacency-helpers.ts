import {
  encodeNearbyDriverGeoHash,
} from "./nearby-driver-geo-index-helpers.js";

import {
  decodeNearbyDriverGeoHashCellBounds,
} from "./nearby-driver-geohash-bounds-helpers.js";

export type NearbyDriverGeoHashCellDelta =
  -1 | 0 | 1;

const requireCellDelta = (
  value: unknown,
): NearbyDriverGeoHashCellDelta => {
  if (
    value !== -1 &&
    value !== 0 &&
    value !== 1
  ) {
    throw new TypeError(
      "Invalid geohash cell delta.",
    );
  }

  return value;
};

const normalizeLongitude = (
  value: number,
): number => {
  let result = value;

  while (result < -180) {
    result += 360;
  }

  while (result >= 180) {
    result -= 360;
  }

  return result;
};

export const deriveNearbyDriverAdjacentGeoHash = (
  geohash: string,
  latitudeCellDeltaValue: NearbyDriverGeoHashCellDelta,
  longitudeCellDeltaValue: NearbyDriverGeoHashCellDelta,
): string | null => {
  const latitudeCellDelta =
    requireCellDelta(
      latitudeCellDeltaValue,
    );

  const longitudeCellDelta =
    requireCellDelta(
      longitudeCellDeltaValue,
    );

  if (
    latitudeCellDelta === 0 &&
    longitudeCellDelta === 0
  ) {
    throw new TypeError(
      "Adjacent geohash requires a non-zero cell delta.",
    );
  }

  const bounds =
    decodeNearbyDriverGeoHashCellBounds(
      geohash,
    );

  const latitudeSpan =
    bounds.latitudeMaximum -
    bounds.latitudeMinimum;

  const longitudeSpan =
    bounds.longitudeMaximum -
    bounds.longitudeMinimum;

  const latitudeCenter =
    (
      bounds.latitudeMinimum +
      bounds.latitudeMaximum
    ) / 2;

  const longitudeCenter =
    (
      bounds.longitudeMinimum +
      bounds.longitudeMaximum
    ) / 2;

  const targetLatitude =
    latitudeCenter +
    latitudeSpan *
      latitudeCellDelta;

  if (
    targetLatitude < -90 ||
    targetLatitude > 90
  ) {
    return null;
  }

  const targetLongitude =
    normalizeLongitude(
      longitudeCenter +
      longitudeSpan *
        longitudeCellDelta,
    );

  return encodeNearbyDriverGeoHash(
    {
      latitude: targetLatitude,
      longitude: targetLongitude,
    },
    geohash.length,
  );
};
