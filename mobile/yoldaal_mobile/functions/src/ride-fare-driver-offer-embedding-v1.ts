import {
  DriverRideMatchOfferFareV1,
} from "./ride-fare-ride-offer-projection-v1.js";
import {
  projectDriverOfferFareFromRideV1,
} from "./ride-fare-ride-embedding-v1.js";

export const DRIVER_OFFER_FARE_FIELD_V1 =
  "fare" as const;

export type DriverPublicOfferWithFareV1 =
  Record<string, unknown> & {
    fare: DriverRideMatchOfferFareV1;
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

const parseAmount = (
  value: unknown,
): number => {
  if (
    !Number.isSafeInteger(value) ||
    (value as number) < 0
  ) {
    return fail(
      "driver_offer_fare_invalid",
    );
  }
  return value as number;
};

export const parseDriverPublicOfferFareV1 = (
  raw: unknown,
): DriverRideMatchOfferFareV1 => {
  if (!isRecord(raw)) {
    return fail(
      "driver_offer_fare_invalid",
    );
  }

  const keys = Object.keys(raw).sort();
  const expected = [
    "currency",
    "yoldaalFareMinor",
  ].sort();

  if (
    keys.length !== expected.length ||
    keys.some(
      (key, index) =>
        key !== expected[index],
    ) ||
    raw.currency !== "TRY"
  ) {
    return fail(
      "driver_offer_fare_invalid",
    );
  }

  return {
    currency: "TRY",
    yoldaalFareMinor:
      parseAmount(
        raw.yoldaalFareMinor,
      ),
  };
};

const requireBaseOffer = (
  raw: unknown,
): Record<string, unknown> => {
  if (!isRecord(raw)) {
    return fail(
      "driver_offer_embedding_invalid",
    );
  }

  if (
    Object.prototype.hasOwnProperty.call(
      raw,
      DRIVER_OFFER_FARE_FIELD_V1,
    )
  ) {
    return fail(
      "driver_offer_embedding_conflict",
    );
  }

  for (const key of Object.keys(raw)) {
    if (FORBIDDEN_TOP_LEVEL_KEYS.has(key)) {
      return fail(
        "driver_offer_embedding_leak",
      );
    }
  }

  return raw;
};

export const embedDriverOfferFareFromRideV1 = (
  rawBaseOffer: unknown,
  rawRide: unknown,
): DriverPublicOfferWithFareV1 => {
  const baseOffer =
    requireBaseOffer(
      rawBaseOffer,
    );
  const projected =
    parseDriverPublicOfferFareV1(
      projectDriverOfferFareFromRideV1(
        rawRide,
      ),
    );

  return {
    ...baseOffer,
    [DRIVER_OFFER_FARE_FIELD_V1]:
      projected,
  };
};

export const parseDriverOfferFareFromRecordV1 = (
  rawOffer: unknown,
): DriverRideMatchOfferFareV1 => {
  if (!isRecord(rawOffer)) {
    return fail(
      "driver_offer_record_invalid",
    );
  }

  if (
    !Object.prototype.hasOwnProperty.call(
      rawOffer,
      DRIVER_OFFER_FARE_FIELD_V1,
    )
  ) {
    return fail(
      "driver_offer_fare_required",
    );
  }

  return parseDriverPublicOfferFareV1(
    rawOffer[
      DRIVER_OFFER_FARE_FIELD_V1
    ],
  );
};
