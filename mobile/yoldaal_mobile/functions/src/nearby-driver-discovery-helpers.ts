import {Timestamp} from "firebase-admin/firestore";

import {
  RIDE_LIVE_TRACKING_STALE_AFTER_SECONDS,
} from "./ride-live-tracking-authority.js";

export type NearbyDriverCandidateProjection = {
  latitude: number;
  longitude: number;
  updatedAtMillis: number;
};

export type NearbyDriverCandidateInput = {
  driverId: string;
  returnRouteId: string;
  presenceData: unknown;
  activeReturnRouteData: unknown;
  returnRouteData: unknown;
  now: Timestamp;
};

const plainRecord = (
  value: unknown,
): Record<string, unknown> | null => {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value) ||
    Object.getPrototypeOf(value) !== Object.prototype
  ) {
    return null;
  }

  return value as Record<string, unknown>;
};

const nonEmptyString = (
  value: unknown,
): value is string =>
  typeof value === "string" &&
  value.trim().length > 0;

const positiveInteger = (
  value: unknown,
): value is number =>
  typeof value === "number" &&
  Number.isInteger(value) &&
  value > 0;

const validCoordinate = (
  latitude: unknown,
  longitude: unknown,
): latitude is number =>
  typeof latitude === "number" &&
  typeof longitude === "number" &&
  Number.isFinite(latitude) &&
  Number.isFinite(longitude) &&
  latitude >= -90 &&
  latitude <= 90 &&
  longitude >= -180 &&
  longitude <= 180;

const sameTimestamp = (
  first: unknown,
  second: unknown,
): boolean =>
  first instanceof Timestamp &&
  second instanceof Timestamp &&
  first.toMillis() === second.toMillis();

const exactPresenceKeys = (
  presence: Record<string, unknown>,
): boolean => {
  const keys = Object.keys(presence).sort();

  return (
    keys.length === 4 &&
    keys[0] === "driverId" &&
    keys[1] === "latitude" &&
    keys[2] === "longitude" &&
    keys[3] === "updatedAt"
  );
};

export const projectNearbyDriverCandidate = (
  input: NearbyDriverCandidateInput,
): NearbyDriverCandidateProjection | null => {
  if (
    !nonEmptyString(input.driverId) ||
    !nonEmptyString(input.returnRouteId) ||
    !(input.now instanceof Timestamp)
  ) {
    return null;
  }

  const presence =
    plainRecord(input.presenceData);

  const activeReturnRoute =
    plainRecord(input.activeReturnRouteData);

  const returnRoute =
    plainRecord(input.returnRouteData);

  if (
    presence === null ||
    activeReturnRoute === null ||
    returnRoute === null
  ) {
    return null;
  }

  if (
    !exactPresenceKeys(presence) ||
    presence.driverId !== input.driverId ||
    !validCoordinate(
      presence.latitude,
      presence.longitude,
    ) ||
    !(presence.updatedAt instanceof Timestamp)
  ) {
    return null;
  }

  const nowMillis =
    input.now.toMillis();

  const updatedAtMillis =
    presence.updatedAt.toMillis();

  if (
    updatedAtMillis > nowMillis ||
    nowMillis - updatedAtMillis >
      RIDE_LIVE_TRACKING_STALE_AFTER_SECONDS * 1000
  ) {
    return null;
  }

  const lockRouteId =
    activeReturnRoute.routeId;

  const lockActivatedAt =
    activeReturnRoute.activatedAt;

  const lockExpiresAt =
    activeReturnRoute.expiresAt;

  if (
    lockRouteId !== input.returnRouteId ||
    !(lockActivatedAt instanceof Timestamp) ||
    !(lockExpiresAt instanceof Timestamp)
  ) {
    return null;
  }

  if (
    nowMillis < lockActivatedAt.toMillis() ||
    nowMillis >= lockExpiresAt.toMillis()
  ) {
    return null;
  }

  const routeActivatedAt =
    returnRoute.activatedAt;

  const routeExpiresAt =
    returnRoute.expiresAt;

  if (
    returnRoute.driverId !== input.driverId ||
    returnRoute.status !== "active" ||
    !sameTimestamp(
      routeActivatedAt,
      lockActivatedAt,
    ) ||
    !sameTimestamp(
      routeExpiresAt,
      lockExpiresAt,
    ) ||
    !positiveInteger(
      returnRoute.routeDistanceMeters,
    ) ||
    !positiveInteger(
      returnRoute.routeDurationSeconds,
    ) ||
    !nonEmptyString(
      returnRoute.encodedPolyline,
    )
  ) {
    return null;
  }

  return {
    latitude: presence.latitude,
    longitude: presence.longitude as number,
    updatedAtMillis,
  };
};
