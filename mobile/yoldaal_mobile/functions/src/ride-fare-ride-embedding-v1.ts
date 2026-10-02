import {
  RideFareBindingV1,
} from "./ride-fare-quote-ride-binding-v1.js";
import {
  DriverRideMatchOfferFareV1,
  RideParticipantFareV1,
  buildRideParticipantFareV1,
  parseRideParticipantFareV1,
  projectDriverRideMatchOfferFareV1,
} from "./ride-fare-ride-offer-projection-v1.js";

export const RIDE_FARE_FIELD_V1 =
  "fare" as const;

export type RideRecordWithFareV1 =
  Record<string, unknown> & {
    fare: RideParticipantFareV1;
  };

const FORBIDDEN_TOP_LEVEL_KEYS =
  new Set<string>([
    "quoteId",
    "currency",
    "yoldaalFareMinor",
    "referenceEstimatedFareMinor",
    "savingMinor",
    "passengerFareBasisPoints",
    "tariffZoneId",
    "tariffVersionId",
    "farePolicyVersionId",
    "authorityType",
    "authorityName",
    "sourceUrl",
    "decisionReference",
    "requestDigest",
    "expiresAtMillis",
    "waitingFeeMinor",
    "tollFeeMinor",
    "parkingFeeMinor",
  ]);

const fail = (reason: string): never => {
  throw new RangeError(reason);
};

const isRecord = (
  value: unknown,
): value is Record<string, unknown> =>
  typeof value === "object" &&
  value !== null &&
  !Array.isArray(value);

const requireBaseRideRecord = (
  value: unknown,
): Record<string, unknown> => {
  if (!isRecord(value)) {
    return fail(
      "ride_fare_embedding_invalid",
    );
  }

  if (
    Object.prototype.hasOwnProperty.call(
      value,
      RIDE_FARE_FIELD_V1,
    )
  ) {
    return fail(
      "ride_fare_embedding_conflict",
    );
  }

  for (const key of Object.keys(value)) {
    if (FORBIDDEN_TOP_LEVEL_KEYS.has(key)) {
      return fail(
        "ride_fare_embedding_leak",
      );
    }
  }

  return value;
};

export const embedRideFareV1 = (
  rawBaseRide: unknown,
  binding: RideFareBindingV1,
): RideRecordWithFareV1 => {
  const baseRide =
    requireBaseRideRecord(
      rawBaseRide,
    );
  const fare =
    buildRideParticipantFareV1(
      binding,
    );

  return {
    ...baseRide,
    [RIDE_FARE_FIELD_V1]: fare,
  };
};

export const parseRideFareFromRecordV1 = (
  rawRide: unknown,
): RideParticipantFareV1 => {
  if (!isRecord(rawRide)) {
    return fail(
      "ride_fare_record_invalid",
    );
  }

  if (
    !Object.prototype.hasOwnProperty.call(
      rawRide,
      RIDE_FARE_FIELD_V1,
    )
  ) {
    return fail(
      "ride_fare_required",
    );
  }

  return parseRideParticipantFareV1(
    rawRide[RIDE_FARE_FIELD_V1],
  );
};

export const projectDriverOfferFareFromRideV1 = (
  rawRide: unknown,
): DriverRideMatchOfferFareV1 =>
  projectDriverRideMatchOfferFareV1(
    parseRideFareFromRecordV1(
      rawRide,
    ),
  );
