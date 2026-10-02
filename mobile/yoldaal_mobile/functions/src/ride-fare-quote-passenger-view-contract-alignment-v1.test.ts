import assert from "node:assert/strict";
import test from "node:test";
import {
  projectPassengerFareQuoteViewV1,
} from "./ride-fare-quote-passenger-view-v1.js";

const quoteId = "a".repeat(64);
const passengerId = "passenger-1";

const persisted = (
  overrides: Record<string, unknown> = {},
): Record<string, unknown> => ({
  quoteId,
  pricingVersion: "fare-v1",
  tariffZoneId: "TR-TEST-ZONE",
  tariffVersionId: "TEST-TARIFF-1",
  farePolicyVersionId: "TEST-POLICY-1",
  currency: "TRY",
  authorityType: "ukome",
  authorityName: "Example Authority",
  sourceUrl: "https://example.gov.tr/tariff.pdf",
  decisionReference: "TEST-DECISION",
  tariffPublishedAtMillis: 500,
  tariffEffectiveFromMillis: 1000,
  tariffEffectiveUntilMillis: null,
  tariffVerifiedAtMillis: 1500,
  openingFeeMinor: 1000,
  distanceRateMinorPerKm: 1000,
  minimumFareMinor: 500,
  plannedDistanceMeters: 1000,
  plannedDurationSeconds: 60,
  referenceEstimatedFareMinor: 2000,
  passengerFareBasisPoints: 4000,
  yoldaalFareMinor: 800,
  savingMinor: 1200,
  quotedAtMillis: 2000,
  passengerId,
  requestDigest: "b".repeat(64),
  ...overrides,
});

test(
  "passenger view accepts zero tariff components when recalculation is exact",
  () => {
    const view =
      projectPassengerFareQuoteViewV1(
        persisted({
          openingFeeMinor: 0,
          distanceRateMinorPerKm: 0,
          minimumFareMinor: 0,
          referenceEstimatedFareMinor: 0,
          yoldaalFareMinor: 0,
          savingMinor: 0,
        }),
        passengerId,
        quoteId,
      );

    assert.equal(view.referenceEstimatedFareMinor, 0);
    assert.equal(view.yoldaalFareMinor, 0);
    assert.equal(view.savingMinor, 0);
  },
);

test(
  "passenger view does not invent published-before-effective chronology",
  () => {
    const view =
      projectPassengerFareQuoteViewV1(
        persisted({
          tariffPublishedAtMillis: 1500,
        }),
        passengerId,
        quoteId,
      );

    assert.equal(view.quotedAtMillis, 2000);
  },
);

test(
  "passenger view still enforces tariff effective interval",
  () => {
    assert.throws(
      () =>
        projectPassengerFareQuoteViewV1(
          persisted({
            quotedAtMillis: 999,
          }),
          passengerId,
          quoteId,
        ),
      /fare_quote_view_data_invalid/u,
    );

    assert.throws(
      () =>
        projectPassengerFareQuoteViewV1(
          persisted({
            tariffEffectiveUntilMillis: 2000,
          }),
          passengerId,
          quoteId,
        ),
      /fare_quote_view_data_invalid/u,
    );
  },
);

test(
  "passenger view still rejects negative tariff money",
  () => {
    assert.throws(
      () =>
        projectPassengerFareQuoteViewV1(
          persisted({
            openingFeeMinor: -1,
          }),
          passengerId,
          quoteId,
        ),
      /fare_quote_view_data_invalid/u,
    );
  },
);
