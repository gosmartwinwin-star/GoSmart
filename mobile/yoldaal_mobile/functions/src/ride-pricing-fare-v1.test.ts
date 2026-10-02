import assert from "node:assert/strict";
import test from "node:test";
import {
  calculatePricingFareV1,
  PRICING_FARE_V1,
  YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS,
} from "./ride-pricing-fare-v1.js";

test("fare-v1 calculates the frozen 18.2 km example", () => {
  const result = calculatePricingFareV1({
    distanceMeters: 18200,
    openingFeeMinor: 5000,
    distanceRateMinorPerKm: 3500,
    minimumFareMinor: 15000,
  });

  assert.deepEqual(result, {
    pricingVersion: PRICING_FARE_V1,
    referenceEstimatedFareMinor: 68700,
    yoldaalFareMinor: 27480,
    savingMinor: 41220,
    multiplierBasisPoints: YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS,
  });
});

test("fare-v1 applies official minimum fare as a floor", () => {
  const result = calculatePricingFareV1({
    distanceMeters: 2000,
    openingFeeMinor: 5000,
    distanceRateMinorPerKm: 3500,
    minimumFareMinor: 15000,
  });

  assert.equal(result.referenceEstimatedFareMinor, 15000);
  assert.equal(result.yoldaalFareMinor, 6000);
  assert.equal(result.savingMinor, 9000);
});

test("fare-v1 prorates distance to meters with half-up minor rounding", () => {
  const result = calculatePricingFareV1({
    distanceMeters: 1,
    openingFeeMinor: 0,
    distanceRateMinorPerKm: 3500,
    minimumFareMinor: 0,
  });

  assert.equal(result.referenceEstimatedFareMinor, 4);
  assert.equal(result.yoldaalFareMinor, 2);
  assert.equal(result.savingMinor, 2);
});

test("fare-v1 has no waiting, duration or toll monetary input", () => {
  const keys = Object.keys(calculatePricingFareV1({
    distanceMeters: 10000,
    openingFeeMinor: 5000,
    distanceRateMinorPerKm: 3500,
    minimumFareMinor: 15000,
  })).sort();

  assert.deepEqual(keys, [
    "multiplierBasisPoints",
    "pricingVersion",
    "referenceEstimatedFareMinor",
    "savingMinor",
    "yoldaalFareMinor",
  ]);
});

test("fare-v1 rejects invalid monetary and distance inputs", () => {
  assert.throws(
    () => calculatePricingFareV1({
      distanceMeters: 0,
      openingFeeMinor: 5000,
      distanceRateMinorPerKm: 3500,
      minimumFareMinor: 15000,
    }),
    /distance_meters_invalid/u,
  );

  assert.throws(
    () => calculatePricingFareV1({
      distanceMeters: 1000,
      openingFeeMinor: -1,
      distanceRateMinorPerKm: 3500,
      minimumFareMinor: 15000,
    }),
    /opening_fee_minor_invalid/u,
  );

  assert.throws(
    () => calculatePricingFareV1({
      distanceMeters: 1000,
      openingFeeMinor: 5000,
      distanceRateMinorPerKm: Number.MAX_SAFE_INTEGER,
      minimumFareMinor: 15000,
    }),
    /fare_amount_overflow/u,
  );
});
