import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

export type ActiveReturnRouteSnapshot = {
  exists: boolean;
  get(fieldPath: string): unknown;
  data(): Record<string, unknown> | undefined;
};

export type ActiveReturnRouteRecoveryDependencies = {
  loadDriverId(uid: string): Promise<string>;
  readLock(driverId: string): Promise<ActiveReturnRouteSnapshot>;
  readRoute(routeId: string): Promise<ActiveReturnRouteSnapshot>;
  now(): Timestamp;
};

export type ActiveReturnRouteCoordinate = {
  latitude: number;
  longitude: number;
};

export type RecoveredActiveReturnRoute = {
  routeId: string;
  driverId: string;
  status: "active";
  origin: ActiveReturnRouteCoordinate;
  destination: ActiveReturnRouteCoordinate;
  createdAtMillis: number;
  activatedAtMillis: number;
  expiresAtMillis: number;
  distanceMeters: number;
  durationSeconds: number;
  encodedPolyline: string;
};

const inconsistent = (): HttpsError =>
  new HttpsError(
    "failed-precondition",
    "Aktif dönüş rotası bilgisi tutarsız.",
    {
      reason: "active_return_route_inconsistent",
    },
  );

const parseNonEmptyString = (
  value: unknown,
): string | null => {
  if (typeof value !== "string") {
    return null;
  }

  const trimmed = value.trim();

  return trimmed.length === 0 ? null : value;
};

const parsePositiveInteger = (
  value: unknown,
): number | null => {
  if (
    typeof value !== "number" ||
    !Number.isInteger(value) ||
    value <= 0
  ) {
    return null;
  }

  return value;
};

const parseCoordinate = (
  value: unknown,
): ActiveReturnRouteCoordinate | null => {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value)
  ) {
    return null;
  }

  const raw =
    value as Record<string, unknown>;

  const latitude = raw.latitude;
  const longitude = raw.longitude;

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
    return null;
  }

  return {
    latitude,
    longitude,
  };
};

const timestampMillis = (
  value: unknown,
): number | null =>
  value instanceof Timestamp ?
    value.toMillis() :
    null;

export const recoverActiveReturnRoute = async (
  dependencies: ActiveReturnRouteRecoveryDependencies,
  uid: string,
): Promise<RecoveredActiveReturnRoute | null> => {
  const driverId =
    await dependencies.loadDriverId(uid);

  const lock =
    await dependencies.readLock(driverId);

  if (!lock.exists) {
    return null;
  }

  const routeId =
    parseNonEmptyString(
      lock.get("routeId"),
    );

  const lockActivatedAtMillis =
    timestampMillis(
      lock.get("activatedAt"),
    );

  const lockExpiresAtMillis =
    timestampMillis(
      lock.get("expiresAt"),
    );

  if (
    routeId === null ||
    lockActivatedAtMillis === null ||
    lockExpiresAtMillis === null ||
    lockExpiresAtMillis <= lockActivatedAtMillis
  ) {
    throw inconsistent();
  }

  const nowMillis =
    dependencies.now().toMillis();

  if (nowMillis >= lockExpiresAtMillis) {
    return null;
  }

  if (nowMillis < lockActivatedAtMillis) {
    throw inconsistent();
  }

  const route =
    await dependencies.readRoute(routeId);

  const data =
    route.data();

  if (!route.exists || data === undefined) {
    throw inconsistent();
  }

  const routeDriverId =
    parseNonEmptyString(
      data.driverId,
    );

  const status =
    data.status;

  const origin =
    parseCoordinate(
      data.origin,
    );

  const destination =
    parseCoordinate(
      data.destination,
    );

  const createdAtMillis =
    timestampMillis(
      data.createdAt,
    );

  const activatedAtMillis =
    timestampMillis(
      data.activatedAt,
    );

  const expiresAtMillis =
    timestampMillis(
      data.expiresAt,
    );

  const distanceMeters =
    parsePositiveInteger(
      data.routeDistanceMeters,
    );

  const durationSeconds =
    parsePositiveInteger(
      data.routeDurationSeconds,
    );

  const encodedPolyline =
    parseNonEmptyString(
      data.encodedPolyline,
    );

  if (
    routeDriverId !== driverId ||
    status !== "active" ||
    origin === null ||
    destination === null ||
    createdAtMillis === null ||
    activatedAtMillis === null ||
    expiresAtMillis === null ||
    distanceMeters === null ||
    durationSeconds === null ||
    encodedPolyline === null ||
    createdAtMillis > activatedAtMillis ||
    activatedAtMillis !== lockActivatedAtMillis ||
    expiresAtMillis !== lockExpiresAtMillis ||
    expiresAtMillis <= activatedAtMillis ||
    nowMillis < activatedAtMillis ||
    nowMillis >= expiresAtMillis
  ) {
    throw inconsistent();
  }

  return {
    routeId,
    driverId,
    status: "active",
    origin,
    destination,
    createdAtMillis,
    activatedAtMillis,
    expiresAtMillis,
    distanceMeters,
    durationSeconds,
    encodedPolyline,
  };
};
