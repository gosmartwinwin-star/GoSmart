import assert from "node:assert/strict";
import test from "node:test";
import {Firestore} from "firebase-admin/firestore";
import {
  FARE_TARIFFS_COLLECTION,
  loadApprovedTariffVersionV1,
  MAX_TARIFF_VERSIONS_PER_ZONE,
} from "./ride-tariff-repository-v1.js";
import {TariffVersionV1} from "./ride-tariff-v1.js";

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

const baseTariff = (
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
  tariff: TariffVersionV1,
  id = tariff.tariffVersionId,
): FakeDocument => ({
  id,
  data: () => ({...tariff}),
});

test("repository queries exact zone and bounded read", async () => {
  const {firestore, call} = fakeFirestore([
    document(baseTariff()),
  ]);

  const selected = await loadApprovedTariffVersionV1(
    firestore,
    "TR-ANKARA-METRO",
    1757000000000,
  );

  assert.equal(selected.tariffVersionId, "ANK-2026-09");
  assert.equal(call.collection, FARE_TARIFFS_COLLECTION);
  assert.equal(call.whereField, "tariffZoneId");
  assert.equal(call.whereOperator, "==");
  assert.equal(call.whereValue, "TR-ANKARA-METRO");
  assert.equal(call.limit, MAX_TARIFF_VERSIONS_PER_ZONE + 1);
  assert.equal(call.getCount, 1);
});

test("repository preserves approved selection semantics", async () => {
  const {firestore} = fakeFirestore([
    document(baseTariff({
      tariffVersionId: "OLD",
      effectiveFromMillis: 1700000000000,
      effectiveUntilMillis: 1756684800000,
    })),
    document(baseTariff()),
    document(baseTariff({
      tariffVersionId: "CANDIDATE",
      approvalStatus: "candidate",
      approvedAtMillis: null,
    })),
  ]);

  const selected = await loadApprovedTariffVersionV1(
    firestore,
    "TR-ANKARA-METRO",
    1757000000000,
  );

  assert.equal(selected.tariffVersionId, "ANK-2026-09");
});

test("repository fails closed on overlapping approved versions", async () => {
  const {firestore} = fakeFirestore([
    document(baseTariff({tariffVersionId: "A"})),
    document(baseTariff({tariffVersionId: "B"})),
  ]);

  await assert.rejects(
    loadApprovedTariffVersionV1(
      firestore,
      "TR-ANKARA-METRO",
      1757000000000,
    ),
    /approved_tariff_ambiguous/u,
  );
});

test("repository binds Firestore document id to tariffVersionId", async () => {
  const {firestore} = fakeFirestore([
    document(baseTariff(), "WRONG-DOCUMENT-ID"),
  ]);

  await assert.rejects(
    loadApprovedTariffVersionV1(
      firestore,
      "TR-ANKARA-METRO",
      1757000000000,
    ),
    /tariff_document_id_mismatch/u,
  );
});

test("repository fails closed when zone history exceeds limit", async () => {
  const documents = Array.from(
    {length: MAX_TARIFF_VERSIONS_PER_ZONE + 1},
    (_, index) =>
      document(baseTariff({
        tariffVersionId: `VERSION-${index}`,
        approvalStatus: "candidate",
        approvedAtMillis: null,
      })),
  );
  const {firestore} = fakeFirestore(documents);

  await assert.rejects(
    loadApprovedTariffVersionV1(
      firestore,
      "TR-ANKARA-METRO",
      1757000000000,
    ),
    /tariff_zone_version_limit_exceeded/u,
  );
});

test("repository sanitizes Firestore read failures", async () => {
  const {firestore} = fakeFirestore([], true);

  await assert.rejects(
    loadApprovedTariffVersionV1(
      firestore,
      "TR-ANKARA-METRO",
      1757000000000,
    ),
    /tariff_repository_unavailable/u,
  );
});

test("repository rejects invalid lookup before Firestore read", async () => {
  const {firestore, call} = fakeFirestore([]);

  await assert.rejects(
    loadApprovedTariffVersionV1(
      firestore,
      "   ",
      1757000000000,
    ),
    /tariff_zone_id_invalid/u,
  );
  assert.equal(call.getCount, 0);

  await assert.rejects(
    loadApprovedTariffVersionV1(
      firestore,
      "TR-ANKARA-METRO",
      -1,
    ),
    /tariff_quote_at_invalid/u,
  );
  assert.equal(call.getCount, 0);
});

test("repository has no write authority", async () => {
  const {firestore} = fakeFirestore([
    document(baseTariff()),
  ]);

  const selected = await loadApprovedTariffVersionV1(
    firestore,
    "TR-ANKARA-METRO",
    1757000000000,
  );

  assert.equal(selected.openingFeeMinor, 5000);
  assert.equal(selected.distanceRateMinorPerKm, 3500);
  assert.equal(selected.minimumFareMinor, 15000);
});
