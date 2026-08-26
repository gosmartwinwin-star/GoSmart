import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  CoordinateInput,
  validateCoordinate,
} from "./route-helpers.js";

export type DriverLiveLocationInput = CoordinateInput;

export type DriverLivePresenceRecord = {
  driverId: string;
  latitude: number;
  longitude: number;
  updatedAt: Timestamp;
};

const invalidLocation = () => new HttpsError(
  "invalid-argument",
  "Geçerli sürücü konumu gereklidir.",
  {reason: "invalid_driver_live_location"},
);

const invalidServerRecord = () => new HttpsError(
  "internal",
  "Sürücü canlı konum verisi doğrulanamadı.",
  {reason: "driver_live_presence_data_invalid"},
);

export const validateDriverLiveLocationInput = (
  value: unknown,
): DriverLiveLocationInput => {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value) ||
    Object.getPrototypeOf(value) !== Object.prototype
  ) {
    throw invalidLocation();
  }

  const input = value as Record<string, unknown>;
  const keys = Object.keys(input);

  if (
    keys.length !== 2 ||
    !keys.includes("latitude") ||
    !keys.includes("longitude")
  ) {
    throw invalidLocation();
  }

  try {
    return validateCoordinate(input);
  } catch (error: unknown) {
    if (error instanceof HttpsError) {
      throw invalidLocation();
    }
    throw error;
  }
};

export const buildDriverLivePresenceRecord = (
  driverId: string,
  location: DriverLiveLocationInput,
  updatedAt: Timestamp,
): DriverLivePresenceRecord => {
  if (
    typeof driverId !== "string" ||
    driverId.trim().length === 0 ||
    !(updatedAt instanceof Timestamp)
  ) {
    throw invalidServerRecord();
  }

  let coordinate: CoordinateInput;
  try {
    coordinate = validateCoordinate(location);
  } catch (error: unknown) {
    if (error instanceof HttpsError) {
      throw invalidServerRecord();
    }
    throw error;
  }

  return {
    driverId,
    latitude: coordinate.latitude,
    longitude: coordinate.longitude,
    updatedAt,
  };
};
