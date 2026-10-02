export const PRICING_FARE_V1 = "fare-v1" as const;
export const YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS = 4000;
const BASIS_POINTS_DENOMINATOR = 10000;
const METERS_PER_KILOMETER = 1000;

export type PricingFareV1Input = {
  distanceMeters: number;
  openingFeeMinor: number;
  distanceRateMinorPerKm: number;
  minimumFareMinor: number;
};

export type PricingFareV1Result = {
  pricingVersion: typeof PRICING_FARE_V1;
  referenceEstimatedFareMinor: number;
  yoldaalFareMinor: number;
  savingMinor: number;
  multiplierBasisPoints: typeof YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS;
};

const requireNonNegativeSafeInteger = (
  value: number,
  field: string,
): number => {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new RangeError(`${field}_invalid`);
  }
  return value;
};

const requirePositiveSafeInteger = (
  value: number,
  field: string,
): number => {
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new RangeError(`${field}_invalid`);
  }
  return value;
};

const checkedAdd = (left: number, right: number): number => {
  const result = left + right;
  if (!Number.isSafeInteger(result)) {
    throw new RangeError("fare_amount_overflow");
  }
  return result;
};

const roundedPositiveRatio = (
  numeratorLeft: number,
  numeratorRight: number,
  denominator: number,
): number => {
  if (
    !Number.isSafeInteger(numeratorLeft) ||
    numeratorLeft < 0 ||
    !Number.isSafeInteger(numeratorRight) ||
    numeratorRight < 0 ||
    !Number.isSafeInteger(denominator) ||
    denominator <= 0
  ) {
    throw new RangeError("fare_ratio_invalid");
  }

  const wholeLeft = Math.floor(numeratorLeft / denominator);
  const remainderLeft = numeratorLeft % denominator;
  const wholeRight = Math.floor(numeratorRight / denominator);
  const remainderRight = numeratorRight % denominator;

  const wholeContribution = wholeLeft * numeratorRight;
  const remainderWholeContribution = remainderLeft * wholeRight;
  const remainderProduct = remainderLeft * remainderRight;

  if (
    !Number.isSafeInteger(wholeContribution) ||
    !Number.isSafeInteger(remainderWholeContribution) ||
    !Number.isSafeInteger(remainderProduct)
  ) {
    throw new RangeError("fare_amount_overflow");
  }

  const fractionalWhole = Math.floor(remainderProduct / denominator);
  const fractionalRemainder = remainderProduct % denominator;
  const roundedFractional = fractionalWhole +
    (fractionalRemainder * 2 >= denominator ? 1 : 0);

  const partial = checkedAdd(
    wholeContribution,
    remainderWholeContribution,
  );
  return checkedAdd(partial, roundedFractional);
};

export const calculatePricingFareV1 = (
  raw: PricingFareV1Input,
): PricingFareV1Result => {
  const distanceMeters = requirePositiveSafeInteger(
    raw.distanceMeters,
    "distance_meters",
  );
  const openingFeeMinor = requireNonNegativeSafeInteger(
    raw.openingFeeMinor,
    "opening_fee_minor",
  );
  const distanceRateMinorPerKm = requireNonNegativeSafeInteger(
    raw.distanceRateMinorPerKm,
    "distance_rate_minor_per_km",
  );
  const minimumFareMinor = requireNonNegativeSafeInteger(
    raw.minimumFareMinor,
    "minimum_fare_minor",
  );

  const distanceFareMinor = roundedPositiveRatio(
    distanceMeters,
    distanceRateMinorPerKm,
    METERS_PER_KILOMETER,
  );
  const meteredReferenceMinor = checkedAdd(
    openingFeeMinor,
    distanceFareMinor,
  );
  const referenceEstimatedFareMinor = Math.max(
    meteredReferenceMinor,
    minimumFareMinor,
  );
  const yoldaalFareMinor = roundedPositiveRatio(
    referenceEstimatedFareMinor,
    YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS,
    BASIS_POINTS_DENOMINATOR,
  );
  const savingMinor = referenceEstimatedFareMinor - yoldaalFareMinor;

  return {
    pricingVersion: PRICING_FARE_V1,
    referenceEstimatedFareMinor,
    yoldaalFareMinor,
    savingMinor,
    multiplierBasisPoints: YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS,
  };
};
