import {HttpsError} from "firebase-functions/v2/https";

export const RIDE_HISTORY_SCOPES = ["passenger", "driver"] as const;
export type RideHistoryScope = typeof RIDE_HISTORY_SCOPES[number];

export type RideHistoryCursor = {
  updatedAtMillis: number;
  rideId: string;
};

export type RideHistoryInput = {
  scope: RideHistoryScope;
  pageSize: number;
  cursor: RideHistoryCursor | null;
};

const invalid = (): never => {
  throw new HttpsError(
    "invalid-argument",
    "Ride history request is invalid.",
    {reason: "invalid_ride_history_payload"},
  );
};

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const exactKeys = (
  value: Record<string, unknown>,
  expected: readonly string[],
): boolean => {
  const keys = Object.keys(value).sort();
  return keys.length === expected.length &&
    keys.every((key, index) => key === [...expected].sort()[index]);
};

const parseCursor = (value: unknown): RideHistoryCursor | null => {
  if (value === null) return null;
  if (!isRecord(value) ||
      !exactKeys(value, ["rideId", "updatedAtMillis"])) {
    return invalid();
  }

  const updatedAtMillis = value.updatedAtMillis;
  const rideId = value.rideId;

  if (typeof updatedAtMillis !== "number" ||
      !Number.isSafeInteger(updatedAtMillis) ||
      updatedAtMillis < 0 ||
      typeof rideId !== "string" ||
      rideId.length < 1 ||
      rideId.length > 128 ||
      !/^[A-Za-z0-9_-]+$/u.test(rideId)) {
    return invalid();
  }

  return {updatedAtMillis, rideId};
};

export const validateRideHistoryPayload = (
  value: unknown,
): RideHistoryInput => {
  if (!isRecord(value) ||
      !exactKeys(value, ["cursor", "pageSize", "scope"])) {
    return invalid();
  }

  const scope = value.scope;
  const pageSize = value.pageSize;

  if (!RIDE_HISTORY_SCOPES.includes(scope as RideHistoryScope) ||
      typeof pageSize !== "number" ||
      !Number.isInteger(pageSize) ||
      pageSize < 1 ||
      pageSize > 20) {
    return invalid();
  }

  return {
    scope: scope as RideHistoryScope,
    pageSize,
    cursor: parseCursor(value.cursor),
  };
};
