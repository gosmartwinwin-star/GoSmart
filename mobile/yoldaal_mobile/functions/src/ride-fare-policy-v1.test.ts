import assert from "node:assert/strict";
import test from "node:test";
import {
  FarePolicyVersionV1,
  parseFarePolicyVersionV1,
  selectApprovedFarePolicyVersionV1,
} from "./ride-fare-policy-v1.js";
import {
  PRICING_FARE_V1,
  YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS,
} from "./ride-pricing-fare-v1.js";

const basePolicy = (
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

test("fare policy parses the exact immutable contract", () => {
  const parsed = parseFarePolicyVersionV1(basePolicy());

  assert.equal(
    parsed.farePolicyVersionId,
    "FARE-V1-40PCT-2026-09",
  );
  assert.equal(parsed.pricingVersion, PRICING_FARE_V1);
  assert.equal(parsed.currency, "TRY");
  assert.equal(
    parsed.passengerFareBasisPoints,
    YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS,
  );
});

test("fare policy rejects unknown fields and wrong currency", () => {
  assert.throws(
    () => parseFarePolicyVersionV1({
      ...basePolicy(),
      quoteExpirySeconds: 600,
    }),
    /fare_policy_record_keys_invalid/u,
  );

  assert.throws(
    () => parseFarePolicyVersionV1({
      ...basePolicy(),
      currency: "USD",
    }),
    /fare_policy_currency_invalid/u,
  );
});

test("fare policy freezes passenger basis points at 4000", () => {
  assert.throws(
    () => parseFarePolicyVersionV1({
      ...basePolicy(),
      passengerFareBasisPoints: 3999,
    }),
    /fare_policy_basis_points_invalid/u,
  );

  assert.throws(
    () => parseFarePolicyVersionV1({
      ...basePolicy(),
      passengerFareBasisPoints: 6000,
    }),
    /fare_policy_basis_points_invalid/u,
  );
});

test("fare policy enforces approval timestamp semantics", () => {
  assert.throws(
    () => parseFarePolicyVersionV1(basePolicy({
      approvedAtMillis: null,
    })),
    /fare_policy_approved_at_required/u,
  );

  assert.throws(
    () => parseFarePolicyVersionV1(basePolicy({
      approvalStatus: "candidate",
      approvedAtMillis: 1756689000000,
    })),
    /fare_policy_approved_at_forbidden/u,
  );
});

test("fare policy selects one approved active effective version", () => {
  const selected = selectApprovedFarePolicyVersionV1(
    [
      basePolicy({
        farePolicyVersionId: "OLD",
        effectiveFromMillis: 1700000000000,
        effectiveUntilMillis: 1756684800000,
      }),
      basePolicy(),
      basePolicy({
        farePolicyVersionId: "CANDIDATE",
        approvalStatus: "candidate",
        approvedAtMillis: null,
      }),
    ],
    1757000000000,
  );

  assert.equal(
    selected.farePolicyVersionId,
    "FARE-V1-40PCT-2026-09",
  );
});

test("fare policy uses a half-open effective interval", () => {
  const oldPolicy = basePolicy({
    farePolicyVersionId: "OLD",
    effectiveFromMillis: 1000,
    effectiveUntilMillis: 2000,
    approvedAtMillis: 1000,
  });
  const newPolicy = basePolicy({
    farePolicyVersionId: "NEW",
    effectiveFromMillis: 2000,
    approvedAtMillis: 2000,
  });

  assert.equal(
    selectApprovedFarePolicyVersionV1(
      [oldPolicy, newPolicy],
      1999,
    ).farePolicyVersionId,
    "OLD",
  );
  assert.equal(
    selectApprovedFarePolicyVersionV1(
      [oldPolicy, newPolicy],
      2000,
    ).farePolicyVersionId,
    "NEW",
  );
});

test("fare policy fails closed when no eligible policy exists", () => {
  assert.throws(
    () => selectApprovedFarePolicyVersionV1(
      [basePolicy({
        approvalStatus: "candidate",
        approvedAtMillis: null,
      })],
      1757000000000,
    ),
    /approved_fare_policy_not_found/u,
  );
});

test("fare policy fails closed on overlapping approved versions", () => {
  assert.throws(
    () => selectApprovedFarePolicyVersionV1(
      [
        basePolicy({farePolicyVersionId: "A"}),
        basePolicy({farePolicyVersionId: "B"}),
      ],
      1757000000000,
    ),
    /approved_fare_policy_ambiguous/u,
  );
});

test("fare policy carries no quote expiry semantics", () => {
  const keys = Object.keys(basePolicy()).sort();

  assert.equal(keys.includes("quoteExpirySeconds"), false);
  assert.equal(keys.includes("expiresAtMillis"), false);
  assert.equal(keys.includes("quoteTtlSeconds"), false);
});
