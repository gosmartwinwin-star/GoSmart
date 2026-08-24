import {createHash} from "node:crypto";
/* eslint-disable max-len */
import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {CoordinateInput, coordinatesEqual} from "./route-helpers.js";

export const RIDE_STATUSES = ["matching", "driverEnRoute", "driverArrived",
  "inProgress", "completed", "cancelled", "expired"] as const;
export type RideStatus = typeof RIDE_STATUSES[number];
export const TERMINAL_RIDE_STATUSES: readonly RideStatus[] =
  ["completed", "cancelled", "expired"];

export type RideLocationInput = CoordinateInput & {addressLabel: string};
export type CreateRideRequestInput = {requestId: string;
  pickup: RideLocationInput; dropoff: RideLocationInput};
export type CancelRideInput = {rideId: string; requestId: string;
  expectedVersion: number; reasonCode: "passenger_cancelled" | "driver_cancelled"};
export type RideMutationInput = {rideId: string; requestId: string;
  expectedVersion: number};
export type RideRoute = {distanceMeters: number; durationSeconds: number;
  encodedPolyline: string};

const failure = (code: "invalid-argument" | "failed-precondition" | "internal",
  reason: string) => new HttpsError(code, "Yolculuk iÅŸlemi tamamlanamadÄ±.", {reason});

const exactObject = (value: unknown, keys: readonly string[], reason: string) => {
  if (typeof value !== "object" || value === null || Array.isArray(value) ||
      Object.getPrototypeOf(value) !== Object.prototype) {
    throw failure("invalid-argument", reason);
  }
  const input = value as Record<string, unknown>;
  const actual = Object.keys(input);
  if (actual.length !== keys.length || keys.some((key) => !actual.includes(key))) {
    throw failure("invalid-argument", reason);
  }
  return input;
};

export const validateRequestId = (value: unknown): string => {
  if (typeof value !== "string" || value.length < 16 || value.length > 128 ||
      !/^[A-Za-z0-9_-]+$/u.test(value)) {
    throw failure("invalid-argument", "invalid_request_id");
  }
  return value;
};

const validateLocation = (value: unknown, reason: string): RideLocationInput => {
  const input = exactObject(value, ["latitude", "longitude", "addressLabel"], reason);
  const latitude = input.latitude;
  const longitude = input.longitude;
  const addressLabel = input.addressLabel;
  const hasControlCharacter = typeof addressLabel === "string" &&
    [...addressLabel].some((character) => {
      const code = character.codePointAt(0) ?? 0;
      return code <= 31 || code === 127;
    });
  if (typeof latitude !== "number" || !Number.isFinite(latitude) || latitude < -90 ||
      latitude > 90 || typeof longitude !== "number" ||
      !Number.isFinite(longitude) || longitude < -180 || longitude > 180 ||
      typeof addressLabel !== "string" || addressLabel.trim().length === 0 ||
      addressLabel.length > 300 || hasControlCharacter) {
    throw failure("invalid-argument", reason);
  }
  return {latitude, longitude, addressLabel: addressLabel.trim()};
};

export const validateCreateRideRequestPayload =
  (value: unknown): CreateRideRequestInput => {
    const input = exactObject(value, ["requestId", "pickup", "dropoff"],
      "invalid_create_ride_payload");
    const pickup = validateLocation(input.pickup, "invalid_pickup");
    const dropoff = validateLocation(input.dropoff, "invalid_dropoff");
    if (coordinatesEqual(pickup, dropoff)) {
      throw failure("invalid-argument", "identical_ride_locations");
    }
    return {requestId: validateRequestId(input.requestId), pickup, dropoff};
  };

const validateMutationFields = (input: Record<string, unknown>): RideMutationInput => {
  if (typeof input.rideId !== "string" || input.rideId.length === 0 ||
      input.rideId.length > 128 || !/^[A-Za-z0-9_-]+$/u.test(input.rideId)) {
    throw failure("invalid-argument", "invalid_ride_id");
  }
  if (typeof input.expectedVersion !== "number" ||
      !Number.isInteger(input.expectedVersion) || input.expectedVersion < 1) {
    throw failure("invalid-argument", "invalid_ride_version");
  }
  return {rideId: input.rideId, requestId: validateRequestId(input.requestId),
    expectedVersion: input.expectedVersion};
};

export const validateRideMutationPayload = (value: unknown): RideMutationInput => {
  const input = exactObject(value, ["rideId", "requestId", "expectedVersion"],
    "invalid_ride_mutation_payload");
  return validateMutationFields(input);
};

export const validateCancelRidePayload = (value: unknown): CancelRideInput => {
  const input = exactObject(value,
    ["rideId", "requestId", "expectedVersion", "reasonCode"],
    "invalid_cancel_ride_payload");
  const mutation = validateMutationFields(input);
  if (input.reasonCode !== "passenger_cancelled" &&
      input.reasonCode !== "driver_cancelled") {
    throw failure("invalid-argument", "invalid_cancellation_reason");
  }
  return {...mutation, reasonCode: input.reasonCode};
};

export const parseRideStatus = (value: unknown): RideStatus => {
  if (!RIDE_STATUSES.includes(value as RideStatus)) {
    throw failure("internal", "ride_data_invalid");
  }
  return value as RideStatus;
};

export const requirePositiveVersion = (value: unknown): number => {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1) {
    throw failure("internal", "ride_data_invalid");
  }
  return value;
};

export const requirePassengerCancellation = (status: RideStatus): void => {
  if (!["matching", "driverEnRoute", "driverArrived"].includes(status)) {
    throw failure("failed-precondition",
      TERMINAL_RIDE_STATUSES.includes(status) ? "ride_is_terminal" : "ride_cannot_be_cancelled");
  }
};

export const requireDriverCancellation = (status: RideStatus): void => {
  if (!["driverEnRoute", "driverArrived"].includes(status)) {
    throw failure("failed-precondition",
      TERMINAL_RIDE_STATUSES.includes(status) ? "ride_is_terminal" : "ride_cannot_be_cancelled");
  }
};

export const requireRideTransition = (current: RideStatus,
  expected: RideStatus): void => {
  if (current !== expected) {
    throw failure("failed-precondition",
      TERMINAL_RIDE_STATUSES.includes(current) ? "ride_is_terminal" : "invalid_ride_transition");
  }
};

export const buildInitialRide = (passengerId: string,
  input: CreateRideRequestInput, route: RideRoute, now: Timestamp) => ({
  passengerId, driverId: null, status: "matching" as const, version: 1,
  pickup: input.pickup, dropoff: input.dropoff,
  route: {...route, computedAt: now}, createdAt: now, updatedAt: now,
  acceptedAt: null, driverEnRouteAt: null, arrivedAt: null, startedAt: null,
  completedAt: null, cancelledAt: null, expiredAt: null,
  cancelledBy: null, terminalReason: null,
});

const canonicalJson = (value: unknown): string => {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (typeof value === "object" && value !== null) {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record).sort().map((key) =>
      `${JSON.stringify(key)}:${canonicalJson(record[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
};

export const rideOperationId = (actorUid: string, callableName: string,
  requestId: string): string => createHash("sha256")
  .update(`ride-operation:${actorUid}:${callableName}:${requestId}`).digest("hex");
export const rideRequestDigest = (callableName: string, input: unknown): string =>
  createHash("sha256").update(`${callableName}:${canonicalJson(input)}`).digest("hex");

const millis = (value: unknown): number | null => {
  if (value === null) return null;
  if (value instanceof Timestamp) return value.toMillis();
  throw failure("internal", "ride_data_invalid");
};

export const serializeActiveRide = (rideId: string,
  data: Record<string, unknown>) => {
  const location = (value: unknown) => {
    if (typeof value !== "object" || value === null) {
      throw failure("internal", "ride_data_invalid");
    }
    const item = value as Record<string, unknown>;
    if (typeof item.latitude !== "number" || typeof item.longitude !== "number" ||
        typeof item.addressLabel !== "string") {
      throw failure("internal", "ride_data_invalid");
    }
    return {latitude: item.latitude, longitude: item.longitude,
      addressLabel: item.addressLabel};
  };
  const route = data.route as Record<string, unknown> | null;
  if (!route || typeof route.distanceMeters !== "number" ||
      typeof route.durationSeconds !== "number" ||
      typeof route.encodedPolyline !== "string") {
    throw failure("internal", "ride_data_invalid");
  }
  const response: Record<string, unknown> = {rideId,
    status: parseRideStatus(data.status), version: requirePositiveVersion(data.version),
    driverId: typeof data.driverId === "string" ? data.driverId : null,
    pickup: location(data.pickup), dropoff: location(data.dropoff),
    route: {distanceMeters: route.distanceMeters,
      durationSeconds: route.durationSeconds,
      encodedPolyline: route.encodedPolyline,
      computedAtMillis: millis(route.computedAt)},
    createdAtMillis: millis(data.createdAt), updatedAtMillis: millis(data.updatedAt)};
  for (const field of ["acceptedAt", "driverEnRouteAt", "arrivedAt", "startedAt",
    "completedAt", "cancelledAt", "expiredAt"] as const) {
    response[`${field}Millis`] = millis(data[field]);
  }
  response.cancelledBy = data.cancelledBy ?? null;
  response.terminalReason = data.terminalReason ?? null;
  return response;
};
