import {protos} from "@googlemaps/routing";
import {HttpsError} from "firebase-functions/v2/https";

export type CoordinateInput = {
  latitude: number;
  longitude: number;
};

const invalidCoordinatesError = () => new HttpsError(
  "invalid-argument",
  "Geçerli koordinatlar gereklidir.",
);

export const validateCoordinate = (value: unknown): CoordinateInput => {
  if (typeof value !== "object" || value === null) {
    throw invalidCoordinatesError();
  }

  const coordinate = value as Record<string, unknown>;
  const {latitude, longitude} = coordinate;

  if (
    typeof latitude !== "number" ||
    typeof longitude !== "number" ||
    !Number.isFinite(latitude) ||
    !Number.isFinite(longitude) ||
    latitude < -90 ||
    latitude > 90 ||
    longitude < -180 ||
    longitude > 180
  ) {
    throw invalidCoordinatesError();
  }

  return {latitude, longitude};
};

export const validateRouteIndex = (value: unknown): number => {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
    throw new HttpsError(
      "invalid-argument",
      "Geçerli rota indeksleri gereklidir.",
    );
  }

  return value;
};

export const validateDirection = (
  pickupRouteIndex: number,
  dropoffRouteIndex: number,
): void => {
  if (pickupRouteIndex >= dropoffRouteIndex) {
    throw new HttpsError(
      "failed-precondition",
      "Rota noktalarının yön sırası uyumlu değildir.",
      {reason: "incompatible_direction"},
    );
  }
};

export const coordinatesEqual = (
  first: CoordinateInput,
  second: CoordinateInput,
): boolean => first.latitude === second.latitude &&
  first.longitude === second.longitude;

export const durationToSeconds = (
  duration: protos.google.protobuf.IDuration | null | undefined,
): number | null => {
  if (duration?.seconds === null || duration?.seconds === undefined) {
    return null;
  }

  const seconds = typeof duration.seconds === "number" ?
    duration.seconds :
    Number(duration.seconds.toString());
  const nanos = duration.nanos ?? 0;

  if (
    !Number.isFinite(seconds) ||
    !Number.isFinite(nanos) ||
    nanos < 0 ||
    nanos >= 1_000_000_000
  ) {
    return null;
  }

  const totalSeconds = seconds + nanos / 1_000_000_000;
  if (!Number.isFinite(totalSeconds) || totalSeconds < 0) {
    return null;
  }

  return Math.round(totalSeconds);
};

export const validateNonNegativeInteger = (
  value: unknown,
): number | null => typeof value === "number" &&
  Number.isInteger(value) &&
  value >= 0 ? value : null;
