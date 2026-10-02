import {
  FarePolicyVersionV1,
  selectApprovedFarePolicyVersionV1,
} from "./ride-fare-policy-v1.js";
import {
  calculatePricingFareV1,
  PRICING_FARE_V1,
  YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS,
} from "./ride-pricing-fare-v1.js";
import {
  selectApprovedTariffVersionV1,
  TariffVersionV1,
} from "./ride-tariff-v1.js";

export type FareQuoteSnapshotV1 = {
  quoteId: string;
  pricingVersion: typeof PRICING_FARE_V1;
  tariffZoneId: string;
  tariffVersionId: string;
  farePolicyVersionId: string;
  currency: "TRY";
  authorityType: TariffVersionV1["authorityType"];
  authorityName: string;
  sourceUrl: string;
  decisionReference: string;
  tariffPublishedAtMillis: number;
  tariffEffectiveFromMillis: number;
  tariffEffectiveUntilMillis: number | null;
  tariffVerifiedAtMillis: number;
  openingFeeMinor: number;
  distanceRateMinorPerKm: number;
  minimumFareMinor: number;
  plannedDistanceMeters: number;
  plannedDurationSeconds: number;
  referenceEstimatedFareMinor: number;
  passengerFareBasisPoints:
    typeof YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS;
  yoldaalFareMinor: number;
  savingMinor: number;
  quotedAtMillis: number;
};

export type BuildFareQuoteSnapshotV1Input = {
  quoteId: unknown;
  tariff: TariffVersionV1;
  farePolicy: FarePolicyVersionV1;
  plannedDistanceMeters: unknown;
  plannedDurationSeconds: unknown;
  quotedAtMillis: unknown;
};

const fail = (reason: string): never => {
  throw new RangeError(reason);
};

const hasAsciiControlCharacter = (
  value: string,
): boolean =>
  value.split("").some((character) => {
    const codeUnit = character.charCodeAt(0);
    return codeUnit <= 31 || codeUnit === 127;
  });

const boundedText = (
  value: unknown,
  field: string,
  maxLength: number,
): string => {
  if (typeof value !== "string") {
    return fail(`${field}_invalid`);
  }
  const normalized = value.trim();
  if (
    normalized.length === 0 ||
    normalized.length > maxLength ||
    hasAsciiControlCharacter(normalized)
  ) {
    return fail(`${field}_invalid`);
  }
  return normalized;
};

const nonNegativeInteger = (
  value: unknown,
  field: string,
): number => {
  if (!Number.isSafeInteger(value) || (value as number) < 0) {
    return fail(`${field}_invalid`);
  }
  return value as number;
};

export const buildFareQuoteSnapshotV1 = (
  input: BuildFareQuoteSnapshotV1Input,
): FareQuoteSnapshotV1 => {
  const quoteId = boundedText(
    input.quoteId,
    "fare_quote_id",
    120,
  );
  const plannedDistanceMeters = nonNegativeInteger(
    input.plannedDistanceMeters,
    "fare_quote_planned_distance",
  );
  const plannedDurationSeconds = nonNegativeInteger(
    input.plannedDurationSeconds,
    "fare_quote_planned_duration",
  );
  const quotedAtMillis = nonNegativeInteger(
    input.quotedAtMillis,
    "fare_quote_quoted_at",
  );

  const tariff = selectApprovedTariffVersionV1(
    [input.tariff],
    input.tariff.tariffZoneId,
    quotedAtMillis,
  );
  const farePolicy = selectApprovedFarePolicyVersionV1(
    [input.farePolicy],
    quotedAtMillis,
  );

  if (tariff.currency !== farePolicy.currency) {
    fail("fare_quote_currency_mismatch");
  }
  if (farePolicy.pricingVersion !== PRICING_FARE_V1) {
    fail("fare_quote_pricing_version_mismatch");
  }

  const fare = calculatePricingFareV1({
    distanceMeters: plannedDistanceMeters,
    openingFeeMinor: tariff.openingFeeMinor,
    distanceRateMinorPerKm: tariff.distanceRateMinorPerKm,
    minimumFareMinor: tariff.minimumFareMinor,
  });

  if (
    fare.multiplierBasisPoints !==
    farePolicy.passengerFareBasisPoints
  ) {
    fail("fare_quote_policy_multiplier_mismatch");
  }

  return {
    quoteId,
    pricingVersion: PRICING_FARE_V1,
    tariffZoneId: tariff.tariffZoneId,
    tariffVersionId: tariff.tariffVersionId,
    farePolicyVersionId: farePolicy.farePolicyVersionId,
    currency: tariff.currency,
    authorityType: tariff.authorityType,
    authorityName: tariff.authorityName,
    sourceUrl: tariff.sourceUrl,
    decisionReference: tariff.decisionReference,
    tariffPublishedAtMillis: tariff.publishedAtMillis,
    tariffEffectiveFromMillis: tariff.effectiveFromMillis,
    tariffEffectiveUntilMillis: tariff.effectiveUntilMillis,
    tariffVerifiedAtMillis: tariff.verifiedAtMillis,
    openingFeeMinor: tariff.openingFeeMinor,
    distanceRateMinorPerKm: tariff.distanceRateMinorPerKm,
    minimumFareMinor: tariff.minimumFareMinor,
    plannedDistanceMeters,
    plannedDurationSeconds,
    referenceEstimatedFareMinor:
      fare.referenceEstimatedFareMinor,
    passengerFareBasisPoints:
      YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS,
    yoldaalFareMinor: fare.yoldaalFareMinor,
    savingMinor: fare.savingMinor,
    quotedAtMillis,
  };
};
