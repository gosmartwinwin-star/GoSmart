import {Timestamp} from "firebase-admin/firestore";

export type NearbyDriverGeoCoordinate = {
  latitude: number;
  longitude: number;
};

export type NearbyDriverGeoIndexRecord = {
  driverId: string;
  geohash: string;
  updatedAt: Timestamp;
};

const GEOHASH_BASE32 =
  "0123456789bcdefghjkmnpqrstuvwxyz";

const GEOHASH_BITS =
  [16, 8, 4, 2, 1] as const;

const requireCoordinate = (
  value: unknown,
): NearbyDriverGeoCoordinate => {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value)
  ) {
    throw new TypeError(
      "Invalid nearby driver geo coordinate.",
    );
  }

  const coordinate =
    value as Record<string, unknown>;

  if (
    typeof coordinate.latitude !== "number" ||
    !Number.isFinite(coordinate.latitude) ||
    coordinate.latitude < -90 ||
    coordinate.latitude > 90 ||
    typeof coordinate.longitude !== "number" ||
    !Number.isFinite(coordinate.longitude) ||
    coordinate.longitude < -180 ||
    coordinate.longitude > 180
  ) {
    throw new TypeError(
      "Invalid nearby driver geo coordinate.",
    );
  }

  return {
    latitude: coordinate.latitude,
    longitude: coordinate.longitude,
  };
};

const requirePrecision = (
  value: unknown,
): number => {
  if (
    typeof value !== "number" ||
    !Number.isInteger(value) ||
    value < 1 ||
    value > 12
  ) {
    throw new TypeError(
      "Invalid geohash precision.",
    );
  }

  return value;
};

export const encodeNearbyDriverGeoHash = (
  coordinateValue: NearbyDriverGeoCoordinate,
  precisionValue: number,
): string => {
  const coordinate =
    requireCoordinate(coordinateValue);

  const precision =
    requirePrecision(precisionValue);

  let latitudeMinimum = -90;
  let latitudeMaximum = 90;
  let longitudeMinimum = -180;
  let longitudeMaximum = 180;

  let longitudeTurn = true;
  let bitIndex = 0;
  let characterValue = 0;
  let geohash = "";

  while (geohash.length < precision) {
    if (longitudeTurn) {
      const midpoint =
        (
          longitudeMinimum +
          longitudeMaximum
        ) / 2;

      if (coordinate.longitude >= midpoint) {
        characterValue |=
          GEOHASH_BITS[bitIndex];

        longitudeMinimum =
          midpoint;
      } else {
        longitudeMaximum =
          midpoint;
      }
    } else {
      const midpoint =
        (
          latitudeMinimum +
          latitudeMaximum
        ) / 2;

      if (coordinate.latitude >= midpoint) {
        characterValue |=
          GEOHASH_BITS[bitIndex];

        latitudeMinimum =
          midpoint;
      } else {
        latitudeMaximum =
          midpoint;
      }
    }

    longitudeTurn =
      !longitudeTurn;

    if (bitIndex < 4) {
      bitIndex += 1;
      continue;
    }

    geohash +=
      GEOHASH_BASE32[characterValue];

    bitIndex = 0;
    characterValue = 0;
  }

  return geohash;
};

export const buildNearbyDriverGeoIndexRecord = (
  driverId: string,
  coordinate: NearbyDriverGeoCoordinate,
  updatedAt: Timestamp,
  precision: number,
): NearbyDriverGeoIndexRecord => {
  if (
    typeof driverId !== "string" ||
    driverId.trim().length === 0 ||
    !(updatedAt instanceof Timestamp)
  ) {
    throw new TypeError(
      "Invalid nearby driver geo index record.",
    );
  }

  return {
    driverId,
    geohash:
      encodeNearbyDriverGeoHash(
        coordinate,
        precision,
      ),
    updatedAt,
  };
};
