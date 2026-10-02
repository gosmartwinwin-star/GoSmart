import assert from "node:assert/strict";
import test from "node:test";
import {
  buildPersistedFareQuoteV1,
  fareQuoteOperationIdV1,
  validateFareQuoteRequestV1,
} from "./ride-fare-quote-persistence-v1.js";
import {
  projectPassengerFareQuoteViewV1,
} from "./ride-fare-quote-passenger-view-v1.js";
import {
  buildFareQuoteSnapshotV1,
} from "./ride-fare-quote-v1.js";
import {
  PRICING_FARE_V1,
  YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS,
} from "./ride-pricing-fare-v1.js";
import {
  FarePolicyVersionV1,
} from "./ride-fare-policy-v1.js";
import {
  TariffVersionV1,
} from "./ride-tariff-v1.js";

const passengerId = "passenger-1";
const requestId = "quote_request_1234567890";
const quotedAtMillis = 1757000000000;

const tariff: TariffVersionV1 = {
  tariffVersionId: "ANK-2026-09",
  tariffZoneId: "TR-ANKARA-METRO",
  approvalStatus: "approved",
  active: true,
  currency: "TRY",
  authorityType: "ukome",
  authorityName:
    "Example Official Authority",
  sourceUrl:
    "https://example.gov.tr/tariff.pdf",
  decisionReference: "EXAMPLE-2026-09",
  publishedAtMillis: 1756684800000,
  effectiveFromMillis: 1756684800000,
  effectiveUntilMillis: null,
  verifiedAtMillis: 1756688400000,
  approvedAtMillis: 1756689000000,
  openingFeeMinor: 5000,
  distanceRateMinorPerKm: 3500,
  minimumFareMinor: 15000,
};

const policy: FarePolicyVersionV1 = {
  farePolicyVersionId:
    "FARE-V1-40PCT-2026-09",
  approvalStatus: "approved",
  active: true,
  pricingVersion: PRICING_FARE_V1,
  currency: "TRY",
  passengerFareBasisPoints:
    YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS,
  policyReference:
    "YOLDAAL-FARE-V1-40PCT",
  effectiveFromMillis: 1756684800000,
  effectiveUntilMillis: null,
  approvedAtMillis: 1756689000000,
};

const input =
  validateFareQuoteRequestV1({
    requestId,
    pickup: {
      latitude: 39.92077,
      longitude: 32.85411,
      addressLabel: "Pickup",
    },
    dropoff: {
      latitude: 39.95,
      longitude: 32.88,
      addressLabel: "Dropoff",
    },
  });

const quoteId =
  fareQuoteOperationIdV1(
    passengerId,
    requestId,
  );

const persisted = () =>
  buildPersistedFareQuoteV1(
    passengerId,
    input,
    buildFareQuoteSnapshotV1({
      quoteId,
      tariff,
      farePolicy: policy,
      plannedDistanceMeters: 18200,
      plannedDurationSeconds: 2400,
      quotedAtMillis,
    }),
  );

test(
  "canonical persisted quote projects exact passenger view",
  () => {
    const view =
      projectPassengerFareQuoteViewV1(
        persisted(),
        passengerId,
        quoteId,
      );

    assert.deepEqual(
      view,
      {
        quoteId,
        pricingVersion: PRICING_FARE_V1,
        currency: "TRY",
        plannedDistanceMeters: 18200,
        plannedDurationSeconds: 2400,
        referenceEstimatedFareMinor: 68700,
        yoldaalFareMinor: 27480,
        savingMinor: 41220,
        quotedAtMillis,
      },
    );
  },
);

test(
  "persisted quote schema rejects extra fields",
  () => {
    assert.throws(
      () =>
        projectPassengerFareQuoteViewV1(
          {
            ...persisted(),
            expiresAtMillis:
              quotedAtMillis + 60000,
          },
          passengerId,
          quoteId,
        ),
      /fare_quote_view_data_invalid/u,
    );
  },
);

test(
  "foreign passenger fails closed",
  () => {
    assert.throws(
      () =>
        projectPassengerFareQuoteViewV1(
          persisted(),
          "passenger-2",
          quoteId,
        ),
      /fare_quote_view_ownership_invalid/u,
    );
  },
);

test(
  "quote identity mismatch fails closed",
  () => {
    const otherQuoteId =
      fareQuoteOperationIdV1(
        passengerId,
        "quote_request_other_1234",
      );

    assert.throws(
      () =>
        projectPassengerFareQuoteViewV1(
          persisted(),
          passengerId,
          otherQuoteId,
        ),
      /fare_quote_view_ownership_invalid/u,
    );
  },
);

test(
  "request digest must be canonical lowercase sha256",
  () => {
    assert.throws(
      () =>
        projectPassengerFareQuoteViewV1(
          {
            ...persisted(),
            requestDigest: "A".repeat(64),
          },
          passengerId,
          quoteId,
        ),
      /fare_quote_view_ownership_invalid/u,
    );
  },
);

test(
  "pricing currency and basis points are fixed",
  () => {
    for (const override of [
      {pricingVersion: "fare-v2"},
      {currency: "USD"},
      {passengerFareBasisPoints: 3999},
    ]) {
      assert.throws(
        () =>
          projectPassengerFareQuoteViewV1(
            {
              ...persisted(),
              ...override,
            },
            passengerId,
            quoteId,
          ),
        /fare_quote_view_data_invalid/u,
      );
    }
  },
);

test(
  "altered reference amount fails recalculation",
  () => {
    assert.throws(
      () =>
        projectPassengerFareQuoteViewV1(
          {
            ...persisted(),
            referenceEstimatedFareMinor:
              68701,
          },
          passengerId,
          quoteId,
        ),
      /fare_quote_view_fare_mismatch/u,
    );
  },
);

test(
  "altered yoldaal or saving amount fails recalculation",
  () => {
    for (const override of [
      {yoldaalFareMinor: 27479},
      {savingMinor: 41219},
    ]) {
      assert.throws(
        () =>
          projectPassengerFareQuoteViewV1(
            {
              ...persisted(),
              ...override,
            },
            passengerId,
            quoteId,
          ),
        /fare_quote_view_fare_mismatch/u,
      );
    }
  },
);

test(
  "invalid route or tariff time semantics fail closed",
  () => {
    for (const override of [
      {plannedDistanceMeters: -1},
      {plannedDurationSeconds: -1},
      {
        tariffEffectiveUntilMillis:
          quotedAtMillis,
      },
    ]) {
      assert.throws(
        () =>
          projectPassengerFareQuoteViewV1(
            {
              ...persisted(),
              ...override,
            },
            passengerId,
            quoteId,
          ),
        /fare_quote_view_data_invalid/u,
      );
    }
  },
);

test(
  "passenger view excludes internal provenance and fee authority",
  () => {
    const view =
      projectPassengerFareQuoteViewV1(
        persisted(),
        passengerId,
        quoteId,
      );
    const keys = Object.keys(view);

    for (const key of [
      "passengerId",
      "requestDigest",
      "tariffZoneId",
      "tariffVersionId",
      "farePolicyVersionId",
      "authorityType",
      "authorityName",
      "sourceUrl",
      "decisionReference",
      "openingFeeMinor",
      "distanceRateMinorPerKm",
      "minimumFareMinor",
      "passengerFareBasisPoints",
      "waitingFeeMinor",
      "tollFeeMinor",
      "parkingFeeMinor",
      "expiresAtMillis",
    ]) {
      assert.equal(
        keys.includes(key),
        false,
      );
    }
  },
);
