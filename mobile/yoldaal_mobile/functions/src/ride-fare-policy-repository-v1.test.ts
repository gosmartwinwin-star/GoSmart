import assert from "node:assert/strict";
import test from "node:test";
import {Firestore} from "firebase-admin/firestore";
import {
  FARE_POLICIES_COLLECTION,
  loadApprovedFarePolicyVersionV1,
  MAX_FARE_POLICY_VERSIONS,
} from "./ride-fare-policy-repository-v1.js";
import {FarePolicyVersionV1} from "./ride-fare-policy-v1.js";
import {
  PRICING_FARE_V1,
  YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS,
} from "./ride-pricing-fare-v1.js";

type FakeDocument = {
  id: string;
  data: () => Record<string, unknown>;
};

type QueryCall = {
  collection: string | null;
  whereField: string | null;
  whereOperator: string | null;
  whereValue: unknown;
  limit: number | null;
  getCount: number;
};

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

const fakeFirestore = (
  documents: readonly FakeDocument[],
  failGet = false,
): {firestore: Firestore; call: QueryCall} => {
  const call: QueryCall = {
    collection: null,
    whereField: null,
    whereOperator: null,
    whereValue: null,
    limit: null,
    getCount: 0,
  };

  const query = {
    where(
      field: string,
      operator: string,
      value: unknown,
    ) {
      call.whereField = field;
      call.whereOperator = operator;
      call.whereValue = value;
      return query;
    },
    limit(value: number) {
      call.limit = value;
      return query;
    },
    async get() {
      call.getCount += 1;
      if (failGet) {
        throw new Error("raw transport detail");
      }
      return {docs: [...documents]};
    },
  };

  const firestore = {
    collection(name: string) {
      call.collection = name;
      return query;
    },
  } as unknown as Firestore;

  return {firestore, call};
};

const document = (
  policy: FarePolicyVersionV1,
  id = policy.farePolicyVersionId,
): FakeDocument => ({
  id,
  data: () => ({...policy}),
});

test("policy repository queries fare-v1 with bounded read", async () => {
  const {firestore, call} = fakeFirestore([
    document(basePolicy()),
  ]);

  const selected = await loadApprovedFarePolicyVersionV1(
    firestore,
    1757000000000,
  );

  assert.equal(
    selected.farePolicyVersionId,
    "FARE-V1-40PCT-2026-09",
  );
  assert.equal(call.collection, FARE_POLICIES_COLLECTION);
  assert.equal(call.whereField, "pricingVersion");
  assert.equal(call.whereOperator, "==");
  assert.equal(call.whereValue, PRICING_FARE_V1);
  assert.equal(call.limit, MAX_FARE_POLICY_VERSIONS + 1);
  assert.equal(call.getCount, 1);
});

test("policy repository preserves approved selection", async () => {
  const {firestore} = fakeFirestore([
    document(basePolicy({
      farePolicyVersionId: "OLD",
      effectiveFromMillis: 1700000000000,
      effectiveUntilMillis: 1756684800000,
    })),
    document(basePolicy()),
    document(basePolicy({
      farePolicyVersionId: "CANDIDATE",
      approvalStatus: "candidate",
      approvedAtMillis: null,
    })),
  ]);

  const selected = await loadApprovedFarePolicyVersionV1(
    firestore,
    1757000000000,
  );

  assert.equal(
    selected.farePolicyVersionId,
    "FARE-V1-40PCT-2026-09",
  );
});

test("policy repository fails closed on overlapping versions", async () => {
  const {firestore} = fakeFirestore([
    document(basePolicy({farePolicyVersionId: "A"})),
    document(basePolicy({farePolicyVersionId: "B"})),
  ]);

  await assert.rejects(
    loadApprovedFarePolicyVersionV1(
      firestore,
      1757000000000,
    ),
    /approved_fare_policy_ambiguous/u,
  );
});

test("policy repository binds document id to policy id", async () => {
  const {firestore} = fakeFirestore([
    document(basePolicy(), "WRONG-DOCUMENT-ID"),
  ]);

  await assert.rejects(
    loadApprovedFarePolicyVersionV1(
      firestore,
      1757000000000,
    ),
    /fare_policy_document_id_mismatch/u,
  );
});

test("policy repository fails closed above version limit", async () => {
  const documents = Array.from(
    {length: MAX_FARE_POLICY_VERSIONS + 1},
    (_, index) =>
      document(basePolicy({
        farePolicyVersionId: `VERSION-${index}`,
        approvalStatus: "candidate",
        approvedAtMillis: null,
      })),
  );
  const {firestore} = fakeFirestore(documents);

  await assert.rejects(
    loadApprovedFarePolicyVersionV1(
      firestore,
      1757000000000,
    ),
    /fare_policy_version_limit_exceeded/u,
  );
});

test("policy repository sanitizes Firestore read failures", async () => {
  const {firestore} = fakeFirestore([], true);

  await assert.rejects(
    loadApprovedFarePolicyVersionV1(
      firestore,
      1757000000000,
    ),
    /fare_policy_repository_unavailable/u,
  );
});

test("policy repository rejects bad time before read", async () => {
  const {firestore, call} = fakeFirestore([]);

  await assert.rejects(
    loadApprovedFarePolicyVersionV1(
      firestore,
      -1,
    ),
    /fare_policy_quote_at_invalid/u,
  );

  assert.equal(call.getCount, 0);
});

test("policy repository has no write authority", async () => {
  const {firestore} = fakeFirestore([
    document(basePolicy()),
  ]);

  const selected = await loadApprovedFarePolicyVersionV1(
    firestore,
    1757000000000,
  );

  assert.equal(
    selected.passengerFareBasisPoints,
    YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS,
  );
  assert.equal(selected.currency, "TRY");
});
