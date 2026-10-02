import assert from "node:assert/strict";
import test from "node:test";
import {
  buildPersistedFareQuoteV1,
  CREATE_FARE_QUOTE_CALLABLE_NAME,
  fareQuoteOperationIdV1,
  fareQuoteRequestDigestV1,
  replayFareQuoteOperationV1,
  validateFareQuoteRequestV1,
} from "./ride-fare-quote-persistence-v1.js";
import {
  buildFareQuoteSnapshotV1,
} from "./ride-fare-quote-v1.js";
import {
  PRICING_FARE_V1,
  YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS,
} from "./ride-pricing-fare-v1.js";

const rawRequest = () => ({
  requestId: "quote_request_1234567890",
  pickup: {
    latitude: 39.92077,
    longitude: 32.85411,
    addressLabel: "Pickup",
  },
  dropoff: {
    latitude: 39.95000,
    longitude: 32.88000,
    addressLabel: "Dropoff",
  },
});

const tariff = {
  tariffVersionId: "ANK-2026-09",
  tariffZoneId: "TR-ANKARA-METRO",
  approvalStatus: "approved" as const,
  active: true,
  currency: "TRY" as const,
  authorityType: "ukome" as const,
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
};

const policy = {
  farePolicyVersionId: "FARE-V1-40PCT-2026-09",
  approvalStatus: "approved" as const,
  active: true,
  pricingVersion: PRICING_FARE_V1,
  currency: "TRY" as const,
  passengerFareBasisPoints:
    YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS,
  policyReference: "YOLDAAL-FARE-V1-40PCT",
  effectiveFromMillis: 1756684800000,
  effectiveUntilMillis: null,
  approvedAtMillis: 1756689000000,
} as const;

const quote = () => buildFareQuoteSnapshotV1({
  quoteId: "server_quote_001",
  tariff,
  farePolicy: policy,
  plannedDistanceMeters: 18200,
  plannedDurationSeconds: 2400,
  quotedAtMillis: 1757000000000,
});

test("quote request reuses exact ride location contract", () => {
  const parsed =
    validateFareQuoteRequestV1(rawRequest());

  assert.deepEqual(
    Object.keys(parsed).sort(),
    ["dropoff", "pickup", "requestId"],
  );

  assert.throws(
    () => validateFareQuoteRequestV1({
      ...rawRequest(),
      tariffZoneId: "CLIENT-ZONE",
    }),
    (error: unknown) =>
      typeof error === "object" &&
      error !== null &&
      "details" in error &&
      typeof error.details === "object" &&
      error.details !== null &&
      "reason" in error.details &&
      error.details.reason === "invalid_create_ride_payload",
  );
});

test("quote operation id follows existing deterministic pattern", () => {
  const id = fareQuoteOperationIdV1(
    "passenger-1",
    "quote_request_1234567890",
  );

  assert.match(id, /^[a-f0-9]{64}$/u);
  assert.equal(
    id,
    fareQuoteOperationIdV1(
      "passenger-1",
      "quote_request_1234567890",
    ),
  );
  assert.equal(
    CREATE_FARE_QUOTE_CALLABLE_NAME,
    "createFareQuote",
  );
});

test("quote digest is deterministic and payload sensitive", () => {
  const first =
    validateFareQuoteRequestV1(rawRequest());
  const second =
    validateFareQuoteRequestV1({
      dropoff: rawRequest().dropoff,
      requestId: rawRequest().requestId,
      pickup: rawRequest().pickup,
    });
  const changed =
    validateFareQuoteRequestV1({
      ...rawRequest(),
      pickup: {
        ...rawRequest().pickup,
        latitude: 39.921,
      },
    });

  assert.equal(
    fareQuoteRequestDigestV1(first),
    fareQuoteRequestDigestV1(second),
  );
  assert.notEqual(
    fareQuoteRequestDigestV1(first),
    fareQuoteRequestDigestV1(changed),
  );
});

test("persisted quote binds passenger and request digest", () => {
  const input =
    validateFareQuoteRequestV1(rawRequest());
  const persisted =
    buildPersistedFareQuoteV1(
      "passenger-1",
      input,
      quote(),
    );

  assert.equal(persisted.passengerId, "passenger-1");
  assert.equal(
    persisted.requestDigest,
    fareQuoteRequestDigestV1(input),
  );
  assert.equal(persisted.quoteId, "server_quote_001");
  assert.equal(persisted.yoldaalFareMinor, 27480);
});

test("persisted quote carries no invented expiry field", () => {
  const persisted =
    buildPersistedFareQuoteV1(
      "passenger-1",
      validateFareQuoteRequestV1(rawRequest()),
      quote(),
    );
  const keys = Object.keys(persisted);

  assert.equal(keys.includes("expiresAtMillis"), false);
  assert.equal(keys.includes("quoteExpirySeconds"), false);
  assert.equal(keys.includes("consumedAtMillis"), false);
});

test("operation replay returns completed same-digest result", () => {
  const digest =
    fareQuoteRequestDigestV1(
      validateFareQuoteRequestV1(rawRequest()),
    );
  const result = {
    quoteId: "server_quote_001",
    yoldaalFareMinor: 27480,
  };

  assert.deepEqual(
    replayFareQuoteOperationV1({
      requestDigest: digest,
      status: "completed",
      result,
    }, digest),
    result,
  );
});

test("operation replay rejects digest mismatch", () => {
  const digest =
    fareQuoteRequestDigestV1(
      validateFareQuoteRequestV1(rawRequest()),
    );

  assert.throws(
    () => replayFareQuoteOperationV1({
      requestDigest: "0".repeat(64),
      status: "completed",
      result: {quoteId: "server_quote_001"},
    }, digest),
    /idempotency_payload_mismatch/u,
  );
});

test("operation replay fails closed while incomplete", () => {
  const digest =
    fareQuoteRequestDigestV1(
      validateFareQuoteRequestV1(rawRequest()),
    );

  assert.throws(
    () => replayFareQuoteOperationV1({
      requestDigest: digest,
      status: "processing",
      result: null,
    }, digest),
    /fare_quote_operation_in_progress/u,
  );
});

test("quote request has no client monetary authority", () => {
  const requestKeys =
    Object.keys(
      validateFareQuoteRequestV1(rawRequest()),
    );

  for (const forbidden of [
    "openingFeeMinor",
    "distanceRateMinorPerKm",
    "minimumFareMinor",
    "passengerFareBasisPoints",
    "yoldaalFareMinor",
    "tariffVersionId",
    "farePolicyVersionId",
  ]) {
    assert.equal(
      requestKeys.includes(forbidden),
      false,
    );
  }
});
