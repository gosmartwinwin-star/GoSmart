import assert from "node:assert/strict";
import test from "node:test";
import {
  FarePolicyVersionV1,
} from "./ride-fare-policy-v1.js";
import {
  buildFareQuoteSnapshotV1,
} from "./ride-fare-quote-v1.js";
import {
  PRICING_FARE_V1,
  YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS,
} from "./ride-pricing-fare-v1.js";
import {
  TariffVersionV1,
} from "./ride-tariff-v1.js";

const quotedAtMillis = 1757000000000;

const tariff = (
  overrides: Partial<TariffVersionV1> = {},
): TariffVersionV1 => ({
  tariffVersionId: "ANK-2026-09",
  tariffZoneId: "TR-ANKARA-METRO",
  approvalStatus: "approved",
  active: true,
  currency: "TRY",
  authorityType: "ukome",
  authorityName: "Example Official Authority",
  sourceUrl: "https://example.gov.tr/tariff.pdf",
  decisionReference: "EXAMPLE-2026-09",
  publishedAtMillis: 1756684800000,
  effectiveFromMillis: 1756684800000,
  effectiveUntilMillis: null,
  verifiedAtMillis: 1756688400000,
  approvedAtMillis: 1756689000000,
  openingFeeMinor: 5000,
  distanceRateMinorPerKm: 3500,
  minimumFareMinor: 15000,
  ...overrides,
});

const policy = (
  overrides: Partial<FarePolicyVersionV1> = {},
): FarePolicyVersionV1 => ({
  farePolicyVersionId: "FARE-V1-40PCT-2026-09",
  approvalStatus: "approved",
  active: true,
  pricingVersion: PRICING_FARE_V1,
  currency: "TRY",
  passengerFareBasisPoints:
    YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS,
  policyReference: "YOLDAAL-FARE-V1-40PCT",
  effectiveFromMillis: 1756684800000,
  effectiveUntilMillis: null,
  approvedAtMillis: 1756689000000,
  ...overrides,
});

const build = (
  overrides: Record<string, unknown> = {},
) => buildFareQuoteSnapshotV1({
  quoteId: "quote-example-001",
  tariff: tariff(),
  farePolicy: policy(),
  plannedDistanceMeters: 18200,
  plannedDurationSeconds: 2400,
  quotedAtMillis,
  ...overrides,
});

test("quote snapshot freezes the illustrative fare values", () => {
  const quote = build();

  assert.equal(quote.referenceEstimatedFareMinor, 68700);
  assert.equal(quote.yoldaalFareMinor, 27480);
  assert.equal(quote.savingMinor, 41220);
  assert.equal(
    quote.passengerFareBasisPoints,
    YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS,
  );
});

test("quote snapshot freezes tariff and policy provenance", () => {
  const quote = build();

  assert.equal(quote.tariffZoneId, "TR-ANKARA-METRO");
  assert.equal(quote.tariffVersionId, "ANK-2026-09");
  assert.equal(
    quote.farePolicyVersionId,
    "FARE-V1-40PCT-2026-09",
  );
  assert.equal(quote.authorityType, "ukome");
  assert.equal(quote.decisionReference, "EXAMPLE-2026-09");
  assert.equal(quote.quotedAtMillis, quotedAtMillis);
});

test("planned duration cannot change any monetary amount", () => {
  const shortDuration = build({
    plannedDurationSeconds: 60,
  });
  const longDuration = build({
    plannedDurationSeconds: 7200,
  });

  assert.equal(
    shortDuration.referenceEstimatedFareMinor,
    longDuration.referenceEstimatedFareMinor,
  );
  assert.equal(
    shortDuration.yoldaalFareMinor,
    longDuration.yoldaalFareMinor,
  );
  assert.equal(
    shortDuration.savingMinor,
    longDuration.savingMinor,
  );
});

test("quote snapshot contains no waiting toll or expiry fields", () => {
  const keys = Object.keys(build());

  assert.equal(keys.includes("waitingFeeMinor"), false);
  assert.equal(keys.includes("timeRateMinor"), false);
  assert.equal(keys.includes("tollFeeMinor"), false);
  assert.equal(keys.includes("bridgeFeeMinor"), false);
  assert.equal(keys.includes("parkingFeeMinor"), false);
  assert.equal(keys.includes("expiresAtMillis"), false);
  assert.equal(keys.includes("quoteExpirySeconds"), false);
});

test("quote snapshot revalidates tariff at quote time", () => {
  assert.throws(
    () => build({
      tariff: tariff({
        effectiveUntilMillis: quotedAtMillis,
      }),
    }),
    /approved_tariff_not_found/u,
  );
});

test("quote snapshot revalidates fare policy at quote time", () => {
  assert.throws(
    () => build({
      farePolicy: policy({
        active: false,
      }),
    }),
    /approved_fare_policy_not_found/u,
  );
});

test("quote snapshot rejects invalid route measurements", () => {
  assert.throws(
    () => build({
      plannedDistanceMeters: -1,
    }),
    /fare_quote_planned_distance_invalid/u,
  );

  assert.throws(
    () => build({
      plannedDurationSeconds: -1,
    }),
    /fare_quote_planned_duration_invalid/u,
  );
});

test("quote snapshot carries the backend-owned quote id", () => {
  const quote = build({
    quoteId: " quote-example-002 ",
  });

  assert.equal(quote.quoteId, "quote-example-002");
});

test("quote snapshot does not expose mutable fare inputs", () => {
  const quote = build();
  const keys = Object.keys(quote);

  assert.equal(keys.includes("driverEnteredFareMinor"), false);
  assert.equal(keys.includes("passengerEnteredFareMinor"), false);
  assert.equal(keys.includes("liveMeterFareMinor"), false);
});
