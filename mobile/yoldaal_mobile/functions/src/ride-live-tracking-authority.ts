import {Firestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {loadApprovedDriverId} from "./ride-driver-identity.js";
import {parseRideStatus} from "./ride-lifecycle-helpers.js";

export const RIDE_LIVE_TRACKING_STALE_AFTER_SECONDS = 20;

export const ACTIVE_RIDE_LIVE_TRACKING_STATUSES = [
  "driverEnRoute",
  "driverArrived",
  "inProgress",
] as const;

export type RideLiveTrackingResult = {
  latitude: number | null;
  longitude: number | null;
  updatedAtMillis: number | null;
  etaSeconds: number | null;
  etaUpdatedAtMillis: number | null;
};

export type RideLiveTrackingEtaResolverInput = {
  rideId: string;
  driverId: string;
  status:
    | "driverEnRoute"
    | "driverArrived"
    | "inProgress";
  origin: {
    latitude: number;
    longitude: number;
  };
  destination: {
    latitude: number;
    longitude: number;
  } | null;
};

export type RideLiveTrackingEtaResolverResult = {
  etaSeconds: number | null;
  etaUpdatedAtMillis: number | null;
};

export type RideLiveTrackingDependencies = {
  firestore: Firestore;
  now?: () => Timestamp;
  loadApprovedDriverIdForActor?: (
    firestore: Firestore,
    actorUid: string,
  ) => Promise<string>;
  resolveEta?: (
    input: RideLiveTrackingEtaResolverInput,
  ) => Promise<RideLiveTrackingEtaResolverResult>;
};

type RideLiveTrackingInput = {
  rideId: string;
};

const failure = (
  code:
    | "invalid-argument"
    | "not-found"
    | "permission-denied"
    | "failed-precondition"
    | "internal",
  reason: string,
): HttpsError =>
  new HttpsError(
    code,
    "Canlı yolculuk konumu alınamadı.",
    {reason},
  );

const validateRideId = (value: unknown): string => {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > 128 ||
    !/^[A-Za-z0-9_-]+$/u.test(value)
  ) {
    throw failure("invalid-argument", "invalid_ride_id");
  }

  return value;
};

export const validateRideLiveTrackingPayload = (
  value: unknown,
): RideLiveTrackingInput => {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value) ||
    Object.getPrototypeOf(value) !== Object.prototype
  ) {
    throw failure(
      "invalid-argument",
      "invalid_ride_live_tracking_payload",
    );
  }

  const input = value as Record<string, unknown>;
  const keys = Object.keys(input);

  if (keys.length !== 1 || keys[0] !== "rideId") {
    throw failure(
      "invalid-argument",
      "invalid_ride_live_tracking_payload",
    );
  }

  return {
    rideId: validateRideId(input.rideId),
  };
};

const noAuthoritativeLocation = (): RideLiveTrackingResult => ({
  latitude: null,
  longitude: null,
  updatedAtMillis: null,
  etaSeconds: null,
  etaUpdatedAtMillis: null,
});

const readRideCoordinate = (
  value: unknown,
): {
  latitude: number;
  longitude: number;
} => {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value)
  ) {
    throw failure(
      "internal",
      "ride_tracking_data_invalid",
    );
  }

  const data =
    value as Record<string, unknown>;

  const latitude = data.latitude;
  const longitude = data.longitude;

  if (
    typeof latitude !== "number" ||
    !Number.isFinite(latitude) ||
    latitude < -90 ||
    latitude > 90 ||
    typeof longitude !== "number" ||
    !Number.isFinite(longitude) ||
    longitude < -180 ||
    longitude > 180
  ) {
    throw failure(
      "internal",
      "ride_tracking_data_invalid",
    );
  }

  return {
    latitude,
    longitude,
  };
};

const requireParticipantAndDriverId = async (
  dependencies: RideLiveTrackingDependencies,
  actorUid: string,
  rideData: Record<string, unknown>,
  isActiveTrackingStatus: boolean,
): Promise<string> => {
  const passengerId = rideData.passengerId;
  const driverId = rideData.driverId;

  if (
    typeof passengerId !== "string" ||
    passengerId.length === 0
  ) {
    throw failure("internal", "ride_tracking_data_invalid");
  }

  if (actorUid === passengerId) {
    if (!isActiveTrackingStatus) {
      throw failure(
        "failed-precondition",
        "ride_tracking_unavailable",
      );
    }

    if (
      typeof driverId !== "string" ||
      driverId.length === 0
    ) {
      throw failure("internal", "ride_tracking_data_invalid");
    }

    return driverId;
  }

  if (
    typeof driverId !== "string" ||
    driverId.length === 0
  ) {
    throw failure(
      "permission-denied",
      "ride_tracking_participant_required",
    );
  }

  const resolveApprovedDriverId =
    dependencies.loadApprovedDriverIdForActor ??
    loadApprovedDriverId;

  let approvedDriverId: string;

  try {
    approvedDriverId = await resolveApprovedDriverId(
      dependencies.firestore,
      actorUid,
    );
  } catch (error: unknown) {
    if (error instanceof HttpsError) {
      throw failure(
        "permission-denied",
        "ride_tracking_participant_required",
      );
    }

    throw error;
  }

  if (approvedDriverId !== driverId) {
    throw failure(
      "permission-denied",
      "ride_tracking_participant_required",
    );
  }

  if (!isActiveTrackingStatus) {
    throw failure(
      "failed-precondition",
      "ride_tracking_unavailable",
    );
  }

  return driverId;
};

const serializeFreshPresence = (
  data: Record<string, unknown>,
  expectedDriverId: string,
  now: Timestamp,
): RideLiveTrackingResult => {
  const driverId = data.driverId;
  const latitude = data.latitude;
  const longitude = data.longitude;
  const updatedAt = data.updatedAt;

  if (
    driverId !== expectedDriverId ||
    typeof latitude !== "number" ||
    !Number.isFinite(latitude) ||
    latitude < -90 ||
    latitude > 90 ||
    typeof longitude !== "number" ||
    !Number.isFinite(longitude) ||
    longitude < -180 ||
    longitude > 180 ||
    !(updatedAt instanceof Timestamp)
  ) {
    throw failure(
      "internal",
      "driver_live_presence_invalid",
    );
  }

  const updatedAtMillis = updatedAt.toMillis();
  const nowMillis = now.toMillis();

  if (updatedAtMillis > nowMillis) {
    throw failure(
      "internal",
      "driver_live_presence_invalid",
    );
  }

  const ageMillis = nowMillis - updatedAtMillis;
  const staleAfterMillis =
    RIDE_LIVE_TRACKING_STALE_AFTER_SECONDS * 1000;

  if (ageMillis > staleAfterMillis) {
    return noAuthoritativeLocation();
  }

  return {
    latitude,
    longitude,
    updatedAtMillis,
    etaSeconds: null,
    etaUpdatedAtMillis: null,
  };
};

export const getActiveRideDriverTrackingForActor = async (
  dependencies: RideLiveTrackingDependencies,
  actorUid: string,
  rawInput: unknown,
): Promise<RideLiveTrackingResult> => {
  const input = validateRideLiveTrackingPayload(rawInput);

  const rideSnapshot = await dependencies.firestore
    .collection("rides")
    .doc(input.rideId)
    .get();

  if (!rideSnapshot.exists) {
    throw failure("not-found", "ride_not_found");
  }

  const rideData = rideSnapshot.data();

  if (!rideData) {
    throw failure("internal", "ride_tracking_data_invalid");
  }

  const status = parseRideStatus(rideData.status);

  const isActiveTrackingStatus =
    ACTIVE_RIDE_LIVE_TRACKING_STATUSES.includes(
      status as
        typeof ACTIVE_RIDE_LIVE_TRACKING_STATUSES[number],
    );

  const driverId = await requireParticipantAndDriverId(
    dependencies,
    actorUid,
    rideData,
    isActiveTrackingStatus,
  );

  const presenceSnapshot = await dependencies.firestore
    .collection("driverLivePresences")
    .doc(driverId)
    .get();

  if (!presenceSnapshot.exists) {
    return noAuthoritativeLocation();
  }

  const presenceData = presenceSnapshot.data();

  if (!presenceData) {
    throw failure(
      "internal",
      "driver_live_presence_invalid",
    );
  }

  const freshPresence =
    serializeFreshPresence(
      presenceData,
      driverId,
      dependencies.now?.() ?? Timestamp.now(),
    );

  if (
    freshPresence.latitude === null ||
    freshPresence.longitude === null ||
    status === "driverArrived" ||
    dependencies.resolveEta === undefined
  ) {
    return freshPresence;
  }

  const origin = {
    latitude: freshPresence.latitude,
    longitude: freshPresence.longitude,
  };

  const destination =
    status === "driverEnRoute" ?
      readRideCoordinate(rideData.pickup) :
      status === "inProgress" ?
        readRideCoordinate(rideData.dropoff) :
        null;

  let eta:
    RideLiveTrackingEtaResolverResult;

  try {
    eta = await dependencies.resolveEta({
      rideId: input.rideId,
      driverId,
      status: status as
        RideLiveTrackingEtaResolverInput["status"],
      origin,
      destination,
    });
  } catch (_error: unknown) {
    return freshPresence;
  }

  return {
    ...freshPresence,
    etaSeconds: eta.etaSeconds,
    etaUpdatedAtMillis:
      eta.etaUpdatedAtMillis,
  };
};
