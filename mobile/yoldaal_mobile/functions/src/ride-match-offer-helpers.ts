import {createHash} from "node:crypto";
import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

export const RETURN_ROUTE_MATCH_MAX_DETOUR_METERS = 3000;
export const RETURN_ROUTE_MATCH_MAX_DETOUR_SECONDS = 600;
export const RIDE_MATCH_OFFER_POLICY_VERSION = 1;
export const RIDE_MATCH_OFFER_TTL_SECONDS = 120;

export const RIDE_MATCH_OFFER_STATUSES = [
  "active",
  "consumed",
] as const;

export type RideMatchOfferStatus =
  typeof RIDE_MATCH_OFFER_STATUSES[number];

export type RideMatchMeasurement = {
  pickupRouteIndex: number;
  dropoffRouteIndex: number;
  pickupDetourMeters: number;
  pickupDetourSeconds: number;
  dropoffDetourMeters: number;
  dropoffDetourSeconds: number;
};

export type RideMatchOfferRecord = {
  driverId: string;
  rideId: string;
  rideVersion: number;
  returnRouteId: string;
  policyVersion: number;
  status: RideMatchOfferStatus;
  createdAt: Timestamp;
  expiresAt: Timestamp;
  consumedAt: Timestamp | null;
  measurement: RideMatchMeasurement;
};

type BuildRideMatchOfferInput = {
  driverId: string;
  rideId: string;
  rideVersion: number;
  returnRouteId: string;
  routeExpiresAt: Timestamp;
  now: Timestamp;
  measurement: RideMatchMeasurement;
  ttlSeconds?: number;
};

type RequireRideMatchOfferInput = {
  driverId: string;
  rideId: string;
  rideVersion: number;
  activeReturnRouteId: string;
  now: Timestamp;
};

const isPlainRecord = (
  value: unknown,
): value is Record<string, unknown> =>
  typeof value === "object" &&
  value !== null &&
  !Array.isArray(value);

const offerFailure = (reason: string): HttpsError =>
  new HttpsError(
    "failed-precondition",
    "Yolculuk eşleşme teklifi kullanılamıyor.",
    {reason},
  );

const isNonEmptyIdentifier = (value: unknown): value is string =>
  typeof value === "string" &&
  value.length > 0 &&
  value.length <= 1500 &&
  !value.includes("/");

const isNonNegativeInteger = (
  value: unknown,
): value is number =>
  typeof value === "number" &&
  Number.isInteger(value) &&
  value >= 0;

const isPositiveInteger = (
  value: unknown,
): value is number =>
  typeof value === "number" &&
  Number.isInteger(value) &&
  value > 0;

const parseMeasurement = (
  value: unknown,
): RideMatchMeasurement => {
  if (!isPlainRecord(value)) {
    throw offerFailure("ride_match_offer_invalid");
  }

  const measurement = {
    pickupRouteIndex: value.pickupRouteIndex,
    dropoffRouteIndex: value.dropoffRouteIndex,
    pickupDetourMeters: value.pickupDetourMeters,
    pickupDetourSeconds: value.pickupDetourSeconds,
    dropoffDetourMeters: value.dropoffDetourMeters,
    dropoffDetourSeconds: value.dropoffDetourSeconds,
  };

  if (
    !isNonNegativeInteger(measurement.pickupRouteIndex) ||
    !isNonNegativeInteger(measurement.dropoffRouteIndex) ||
    !isNonNegativeInteger(measurement.pickupDetourMeters) ||
    !isNonNegativeInteger(measurement.pickupDetourSeconds) ||
    !isNonNegativeInteger(measurement.dropoffDetourMeters) ||
    !isNonNegativeInteger(measurement.dropoffDetourSeconds)
  ) {
    throw offerFailure("ride_match_offer_invalid");
  }

  return measurement as RideMatchMeasurement;
};

export const isRideMatchMeasurementEligible = (
  measurement: RideMatchMeasurement,
): boolean =>
  measurement.pickupRouteIndex <
    measurement.dropoffRouteIndex &&
  measurement.pickupDetourMeters <=
    RETURN_ROUTE_MATCH_MAX_DETOUR_METERS &&
  measurement.pickupDetourSeconds <=
    RETURN_ROUTE_MATCH_MAX_DETOUR_SECONDS &&
  measurement.dropoffDetourMeters <=
    RETURN_ROUTE_MATCH_MAX_DETOUR_METERS &&
  measurement.dropoffDetourSeconds <=
    RETURN_ROUTE_MATCH_MAX_DETOUR_SECONDS;

export const rideMatchOfferDocumentId = (
  driverId: string,
  rideId: string,
): string => {
  if (
    !isNonEmptyIdentifier(driverId) ||
    !isNonEmptyIdentifier(rideId)
  ) {
    throw new TypeError("Invalid ride match offer identity.");
  }

  return createHash("sha256")
    .update(
      `ride-match-offer:${driverId}:${rideId}`,
    )
    .digest("hex");
};

export const buildRideMatchOffer = (
  input: BuildRideMatchOfferInput,
): RideMatchOfferRecord => {
  if (
    !isNonEmptyIdentifier(input.driverId) ||
    !isNonEmptyIdentifier(input.rideId) ||
    !isNonEmptyIdentifier(input.returnRouteId) ||
    !isPositiveInteger(input.rideVersion)
  ) {
    throw new TypeError("Invalid ride match offer input.");
  }

  const ttlSeconds =
    input.ttlSeconds ??
    RIDE_MATCH_OFFER_TTL_SECONDS;

  if (
    !isPositiveInteger(ttlSeconds) ||
    ttlSeconds > 300
  ) {
    throw new TypeError(
      "Invalid ride match offer TTL.",
    );
  }

  if (
    input.routeExpiresAt.toMillis() <=
    input.now.toMillis()
  ) {
    throw new TypeError(
      "Return route must still be active.",
    );
  }

  if (
    !isRideMatchMeasurementEligible(
      input.measurement,
    )
  ) {
    throw new TypeError(
      "Ride match measurement is not eligible.",
    );
  }

  const ttlExpiresAtMillis =
    input.now.toMillis() +
    ttlSeconds * 1000;

  const expiresAtMillis =
    Math.min(
      ttlExpiresAtMillis,
      input.routeExpiresAt.toMillis(),
    );

  return {
    driverId: input.driverId,
    rideId: input.rideId,
    rideVersion: input.rideVersion,
    returnRouteId: input.returnRouteId,
    policyVersion:
      RIDE_MATCH_OFFER_POLICY_VERSION,
    status: "active",
    createdAt: input.now,
    expiresAt:
      Timestamp.fromMillis(expiresAtMillis),
    consumedAt: null,
    measurement: input.measurement,
  };
};

export const parseRideMatchOffer = (
  value: unknown,
): RideMatchOfferRecord => {
  if (!isPlainRecord(value)) {
    throw offerFailure(
      "ride_match_offer_invalid",
    );
  }

  const {
    driverId,
    rideId,
    rideVersion,
    returnRouteId,
    policyVersion,
    status,
    createdAt,
    expiresAt,
    consumedAt,
  } = value;

  if (
    !isNonEmptyIdentifier(driverId) ||
    !isNonEmptyIdentifier(rideId) ||
    !isPositiveInteger(rideVersion) ||
    !isNonEmptyIdentifier(returnRouteId) ||
    policyVersion !==
      RIDE_MATCH_OFFER_POLICY_VERSION ||
    !RIDE_MATCH_OFFER_STATUSES.includes(
      status as RideMatchOfferStatus,
    ) ||
    !(createdAt instanceof Timestamp) ||
    !(expiresAt instanceof Timestamp)
  ) {
    throw offerFailure(
      "ride_match_offer_invalid",
    );
  }

  if (
    expiresAt.toMillis() <=
    createdAt.toMillis()
  ) {
    throw offerFailure(
      "ride_match_offer_invalid",
    );
  }

  if (
    status === "active" &&
    consumedAt !== null
  ) {
    throw offerFailure(
      "ride_match_offer_invalid",
    );
  }

  if (
    status === "consumed" &&
    !(consumedAt instanceof Timestamp)
  ) {
    throw offerFailure(
      "ride_match_offer_invalid",
    );
  }

  const measurement =
    parseMeasurement(value.measurement);

  if (
    !isRideMatchMeasurementEligible(
      measurement,
    )
  ) {
    throw offerFailure(
      "ride_match_offer_invalid",
    );
  }

  return {
    driverId,
    rideId,
    rideVersion,
    returnRouteId,
    policyVersion,
    status: status as RideMatchOfferStatus,
    createdAt,
    expiresAt,
    consumedAt:
      consumedAt instanceof Timestamp ?
        consumedAt :
        null,
    measurement,
  };
};

export const requireRideMatchOfferForAcceptance = (
  value: unknown,
  expected: RequireRideMatchOfferInput,
): RideMatchOfferRecord => {
  const offer = parseRideMatchOffer(value);

  if (offer.status !== "active") {
    throw offerFailure(
      "ride_match_offer_not_active",
    );
  }

  if (
    offer.driverId !== expected.driverId ||
    offer.rideId !== expected.rideId
  ) {
    throw offerFailure(
      "ride_match_offer_mismatch",
    );
  }

  if (
    offer.rideVersion !==
    expected.rideVersion
  ) {
    throw offerFailure(
      "ride_match_offer_stale",
    );
  }

  if (
    offer.returnRouteId !==
    expected.activeReturnRouteId
  ) {
    throw offerFailure(
      "ride_match_offer_route_changed",
    );
  }

  if (
    expected.now.toMillis() >=
    offer.expiresAt.toMillis()
  ) {
    throw offerFailure(
      "ride_match_offer_expired",
    );
  }

  if (
    offer.createdAt.toMillis() >
    expected.now.toMillis()
  ) {
    throw offerFailure(
      "ride_match_offer_invalid",
    );
  }

  return offer;
};
