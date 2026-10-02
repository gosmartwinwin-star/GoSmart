import assert from "node:assert/strict";
import test from "node:test";
import {
  bindFareQuoteToCreateRideV1,
} from "./ride-fare-quote-ride-binding-v1.js";
import {
  buildPersistedFareQuoteV1,
  fareQuoteOperationIdV1,
  validateFareQuoteRequestV1,
} from "./ride-fare-quote-persistence-v1.js";
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
const requestId = "quote_ride_shared_request_1234";
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

const input = (
  overrides: Record<string, unknown> = {},
) =>
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
    ...overrides,
  });

const persisted = (
  rideInput = input(),
) => {
  const quoteId =
    fareQuoteOperationIdV1(
      passengerId,
      rideInput.requestId,
    );
  return buildPersistedFareQuoteV1(
    passengerId,
    rideInput,
    buildFareQuoteSnapshotV1({
      quoteId,
      tariff,
      farePolicy: policy,
      plannedDistanceMeters: 18200,
      plannedDurationSeconds: 2400,
      quotedAtMillis,
    }),
  );
};

test(
  "canonical shared request binds quote to ride",
  () => {
    const rideInput = input();
    const binding =
      bindFareQuoteToCreateRideV1(
        passengerId,
        rideInput,
        persisted(rideInput),
      );

    assert.deepEqual(binding, {
      quoteId: fareQuoteOperationIdV1(
        passengerId,
        requestId,
      ),
      currency: "TRY",
      yoldaalFareMinor: 27480,
    });
  },
);

test(
  "createRide input remains exact current contract",
  () => {
    const rideInput = input();
    assert.deepEqual(
      Object.keys(rideInput).sort(),
      [
        "dropoff",
        "pickup",
        "requestId",
      ],
    );
    assert.equal(
      "quoteId" in rideInput,
      false,
    );
  },
);

test(
  "different createRide request id cannot reuse quote",
  () => {
    const quotedInput = input();
    const rideInput =
      input({
        requestId:
          "different_create_request_1234",
      });

    assert.throws(
      () =>
        bindFareQuoteToCreateRideV1(
          passengerId,
          rideInput,
          persisted(quotedInput),
        ),
      /fare_quote_view_ownership_invalid/u,
    );
  },
);

test(
  "changed pickup cannot reuse quote",
  () => {
    const quotedInput = input();
    const changed = {
      ...quotedInput,
      pickup: {
        ...quotedInput.pickup,
        latitude: 39.921,
      },
    };

    assert.throws(
      () =>
        bindFareQuoteToCreateRideV1(
          passengerId,
          changed,
          persisted(quotedInput),
        ),
      /fare_quote_request_binding_mismatch/u,
    );
  },
);

test(
  "changed dropoff cannot reuse quote",
  () => {
    const quotedInput = input();
    const changed = {
      ...quotedInput,
      dropoff: {
        ...quotedInput.dropoff,
        longitude: 32.881,
      },
    };

    assert.throws(
      () =>
        bindFareQuoteToCreateRideV1(
          passengerId,
          changed,
          persisted(quotedInput),
        ),
      /fare_quote_request_binding_mismatch/u,
    );
  },
);

test(
  "changed address label cannot reuse quote",
  () => {
    const quotedInput = input();
    const changed = {
      ...quotedInput,
      pickup: {
        ...quotedInput.pickup,
        addressLabel: "Other Pickup",
      },
    };

    assert.throws(
      () =>
        bindFareQuoteToCreateRideV1(
          passengerId,
          changed,
          persisted(quotedInput),
        ),
      /fare_quote_request_binding_mismatch/u,
    );
  },
);

test(
  "foreign passenger cannot bind quote",
  () => {
    const rideInput = input();

    assert.throws(
      () =>
        bindFareQuoteToCreateRideV1(
          "passenger-2",
          rideInput,
          persisted(rideInput),
        ),
      /fare_quote_view_ownership_invalid/u,
    );
  },
);

test(
  "tampered digest fails binding",
  () => {
    const rideInput = input();
    const quote = persisted(rideInput);

    assert.throws(
      () =>
        bindFareQuoteToCreateRideV1(
          passengerId,
          rideInput,
          {
            ...quote,
            requestDigest:
              "a".repeat(64),
          },
        ),
      /fare_quote_request_binding_mismatch/u,
    );
  },
);

test(
  "tampered monetary values fail before binding",
  () => {
    const rideInput = input();
    const quote = persisted(rideInput);

    assert.throws(
      () =>
        bindFareQuoteToCreateRideV1(
          passengerId,
          rideInput,
          {
            ...quote,
            yoldaalFareMinor:
              quote.yoldaalFareMinor + 1,
          },
        ),
      /fare_quote_view_fare_mismatch/u,
    );
  },
);

test(
  "ride-safe binding excludes passenger-only fare data",
  () => {
    const rideInput = input();
    const binding =
      bindFareQuoteToCreateRideV1(
        passengerId,
        rideInput,
        persisted(rideInput),
      );
    const keys = Object.keys(binding);

    assert.deepEqual(
      keys.sort(),
      [
        "currency",
        "quoteId",
        "yoldaalFareMinor",
      ],
    );

    for (const key of [
      "referenceEstimatedFareMinor",
      "savingMinor",
      "tariffZoneId",
      "tariffVersionId",
      "farePolicyVersionId",
      "authorityType",
      "authorityName",
      "sourceUrl",
      "decisionReference",
      "requestDigest",
      "passengerId",
      "passengerFareBasisPoints",
      "expiresAtMillis",
    ]) {
      assert.equal(
        keys.includes(key),
        false,
      );
    }
  },
);
