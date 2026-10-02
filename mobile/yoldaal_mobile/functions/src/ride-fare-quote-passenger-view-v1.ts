import {
  calculatePricingFareV1,
  PRICING_FARE_V1,
  YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS,
} from "./ride-pricing-fare-v1.js";

export type PassengerFareQuoteViewV1 = {
  quoteId: string;
  pricingVersion: typeof PRICING_FARE_V1;
  currency: "TRY";
  plannedDistanceMeters: number;
  plannedDurationSeconds: number;
  referenceEstimatedFareMinor: number;
  yoldaalFareMinor: number;
  savingMinor: number;
  quotedAtMillis: number;
};

const EXPECTED_KEYS = [
  "quoteId",
  "pricingVersion",
  "tariffZoneId",
  "tariffVersionId",
  "farePolicyVersionId",
  "currency",
  "authorityType",
  "authorityName",
  "sourceUrl",
  "decisionReference",
  "tariffPublishedAtMillis",
  "tariffEffectiveFromMillis",
  "tariffEffectiveUntilMillis",
  "tariffVerifiedAtMillis",
  "openingFeeMinor",
  "distanceRateMinorPerKm",
  "minimumFareMinor",
  "plannedDistanceMeters",
  "plannedDurationSeconds",
  "referenceEstimatedFareMinor",
  "passengerFareBasisPoints",
  "yoldaalFareMinor",
  "savingMinor",
  "quotedAtMillis",
  "passengerId",
  "requestDigest",
] as const;

const fail = (reason: string): never => {
  throw new RangeError(reason);
};

const isRecord = (
  value: unknown,
): value is Record<string, unknown> =>
  typeof value === "object" &&
  value !== null &&
  !Array.isArray(value);

const exactRecord = (
  value: unknown,
): Record<string, unknown> => {
  if (!isRecord(value)) {
    return fail("fare_quote_view_data_invalid");
  }
  const keys = Object.keys(value).sort();
  const expected = [...EXPECTED_KEYS].sort();
  if (
    keys.length !== expected.length ||
    keys.some(
      (key, index) =>
        key !== expected[index],
    )
  ) {
    return fail("fare_quote_view_data_invalid");
  }
  return value;
};

const text = (
  value: unknown,
  maxLength: number,
): string => {
  if (typeof value !== "string") {
    return fail("fare_quote_view_data_invalid");
  }
  const normalized = value.trim();
  if (
    normalized.length === 0 ||
    normalized.length > maxLength ||
    normalized.split("").some(
      (character) => {
        const code = character.charCodeAt(0);
        return code <= 31 || code === 127;
      },
    )
  ) {
    return fail("fare_quote_view_data_invalid");
  }
  return normalized;
};

const nonNegativeInteger = (
  value: unknown,
): number => {
  if (
    !Number.isSafeInteger(value) ||
    (value as number) < 0
  ) {
    return fail("fare_quote_view_data_invalid");
  }
  return value as number;
};


const optionalEndMillis = (
  value: unknown,
): number | null => {
  if (value === null) {
    return null;
  }
  return nonNegativeInteger(value);
};

const SHA256_HEX =
  /^[0-9a-f]{64}$/u;

export const projectPassengerFareQuoteViewV1 = (
  raw: unknown,
  expectedPassengerIdRaw: string,
  expectedQuoteIdRaw: string,
): PassengerFareQuoteViewV1 => {
  const data = exactRecord(raw);
  const expectedPassengerId =
    text(expectedPassengerIdRaw, 128);
  const expectedQuoteId =
    text(expectedQuoteIdRaw, 64);

  const quoteId = text(data.quoteId, 64);
  const passengerId =
    text(data.passengerId, 128);
  const requestDigest =
    text(data.requestDigest, 64);

  if (
    !SHA256_HEX.test(quoteId) ||
    !SHA256_HEX.test(expectedQuoteId) ||
    !SHA256_HEX.test(requestDigest) ||
    quoteId !== expectedQuoteId ||
    passengerId !== expectedPassengerId
  ) {
    return fail("fare_quote_view_ownership_invalid");
  }

  if (
    data.pricingVersion !== PRICING_FARE_V1 ||
    data.currency !== "TRY" ||
    data.passengerFareBasisPoints !==
      YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS
  ) {
    return fail("fare_quote_view_data_invalid");
  }

  text(data.tariffZoneId, 120);
  text(data.tariffVersionId, 120);
  text(data.farePolicyVersionId, 120);
  text(data.authorityType, 80);
  text(data.authorityName, 300);
  text(data.sourceUrl, 2048);
  text(data.decisionReference, 300);

  nonNegativeInteger(
    data.tariffPublishedAtMillis,
  );
  const tariffEffectiveFromMillis =
    nonNegativeInteger(
      data.tariffEffectiveFromMillis,
    );
  const tariffEffectiveUntilMillis =
    optionalEndMillis(
      data.tariffEffectiveUntilMillis,
    );
  nonNegativeInteger(
    data.tariffVerifiedAtMillis,
  );
  const quotedAtMillis =
    nonNegativeInteger(
      data.quotedAtMillis,
    );

  if (
    (
      tariffEffectiveUntilMillis !== null &&
      tariffEffectiveUntilMillis <=
        tariffEffectiveFromMillis
    ) ||
    quotedAtMillis <
      tariffEffectiveFromMillis ||
    (
      tariffEffectiveUntilMillis !== null &&
      quotedAtMillis >=
        tariffEffectiveUntilMillis
    )
  ) {
    return fail("fare_quote_view_data_invalid");
  }

  const openingFeeMinor =
    nonNegativeInteger(
      data.openingFeeMinor,
    );
  const distanceRateMinorPerKm =
    nonNegativeInteger(
      data.distanceRateMinorPerKm,
    );
  const minimumFareMinor =
    nonNegativeInteger(
      data.minimumFareMinor,
    );
  const plannedDistanceMeters =
    nonNegativeInteger(
      data.plannedDistanceMeters,
    );
  const plannedDurationSeconds =
    nonNegativeInteger(
      data.plannedDurationSeconds,
    );
  const referenceEstimatedFareMinor =
    nonNegativeInteger(
      data.referenceEstimatedFareMinor,
    );
  const yoldaalFareMinor =
    nonNegativeInteger(
      data.yoldaalFareMinor,
    );
  const savingMinor =
    nonNegativeInteger(
      data.savingMinor,
    );


  const recalculated =
    calculatePricingFareV1({
      distanceMeters:
        plannedDistanceMeters,
      openingFeeMinor,
      distanceRateMinorPerKm,
      minimumFareMinor,
    });

  if (
    recalculated.referenceEstimatedFareMinor !==
      referenceEstimatedFareMinor ||
    recalculated.yoldaalFareMinor !==
      yoldaalFareMinor ||
    recalculated.savingMinor !==
      savingMinor ||
    recalculated.multiplierBasisPoints !==
      YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS
  ) {
    return fail("fare_quote_view_fare_mismatch");
  }

  return {
    quoteId,
    pricingVersion: PRICING_FARE_V1,
    currency: "TRY",
    plannedDistanceMeters,
    plannedDurationSeconds,
    referenceEstimatedFareMinor,
    yoldaalFareMinor,
    savingMinor,
    quotedAtMillis,
  };
};
