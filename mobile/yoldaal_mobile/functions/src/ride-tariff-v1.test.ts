import assert from "node:assert/strict";
import test from "node:test";
import {
  parseTariffVersionV1,
  selectApprovedTariffVersionV1,
  TariffVersionV1,
} from "./ride-tariff-v1.js";
import {
  calculatePricingFareV1,
} from "./ride-pricing-fare-v1.js";

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

test("tariff-v1 parses the exact immutable version contract", () => {
  const parsed = parseTariffVersionV1(baseTariff());
  assert.equal(parsed.tariffVersionId, "ANK-2026-09");
  assert.equal(parsed.tariffZoneId, "TR-ANKARA-METRO");
  assert.equal(parsed.approvalStatus, "approved");
  assert.equal(parsed.currency, "TRY");
  assert.equal(parsed.openingFeeMinor, 5000);
});

test("tariff-v1 rejects unknown fields and non-TRY currency", () => {
  assert.throws(
    () => parseTariffVersionV1({
      ...baseTariff(),
      waitingFeeMinor: 100,
    }),
    /tariff_record_keys_invalid/u,
  );

  assert.throws(
    () => parseTariffVersionV1({
      ...baseTariff(),
      currency: "USD",
    }),
    /tariff_currency_invalid/u,
  );
});

test("tariff-v1 enforces approval timestamp semantics", () => {
  assert.throws(
    () => parseTariffVersionV1(baseTariff({
      approvedAtMillis: null,
    })),
    /tariff_approved_at_required/u,
  );

  assert.throws(
    () => parseTariffVersionV1(baseTariff({
      approvalStatus: "candidate",
      approvedAtMillis: 1756689000000,
    })),
    /tariff_approved_at_forbidden/u,
  );
});

test("tariff-v1 selects exactly one approved active effective version", () => {
  const selected = selectApprovedTariffVersionV1(
    [
      baseTariff({
        tariffVersionId: "OLD",
        effectiveFromMillis: 1700000000000,
        effectiveUntilMillis: 1756684800000,
      }),
      baseTariff(),
      baseTariff({
        tariffVersionId: "CANDIDATE",
        approvalStatus: "candidate",
        approvedAtMillis: null,
        effectiveFromMillis: 1756684800000,
      }),
    ],
    "TR-ANKARA-METRO",
    1757000000000,
  );

  assert.equal(selected.tariffVersionId, "ANK-2026-09");
});

test("tariff-v1 uses a half-open effective interval", () => {
  const oldTariff = baseTariff({
    tariffVersionId: "OLD",
    effectiveFromMillis: 1000,
    effectiveUntilMillis: 2000,
    publishedAtMillis: 1000,
    verifiedAtMillis: 1000,
    approvedAtMillis: 1000,
  });
  const newTariff = baseTariff({
    tariffVersionId: "NEW",
    effectiveFromMillis: 2000,
    publishedAtMillis: 2000,
    verifiedAtMillis: 2000,
    approvedAtMillis: 2000,
  });

  assert.equal(
    selectApprovedTariffVersionV1(
      [oldTariff, newTariff],
      "TR-ANKARA-METRO",
      1999,
    ).tariffVersionId,
    "OLD",
  );
  assert.equal(
    selectApprovedTariffVersionV1(
      [oldTariff, newTariff],
      "TR-ANKARA-METRO",
      2000,
    ).tariffVersionId,
    "NEW",
  );
});

test("tariff-v1 fails closed when no approved effective tariff exists", () => {
  assert.throws(
    () => selectApprovedTariffVersionV1(
      [baseTariff({
        approvalStatus: "candidate",
        approvedAtMillis: null,
      })],
      "TR-ANKARA-METRO",
      1757000000000,
    ),
    /approved_tariff_not_found/u,
  );
});

test("tariff-v1 fails closed on overlapping approved versions", () => {
  assert.throws(
    () => selectApprovedTariffVersionV1(
      [
        baseTariff({tariffVersionId: "A"}),
        baseTariff({tariffVersionId: "B"}),
      ],
      "TR-ANKARA-METRO",
      1757000000000,
    ),
    /approved_tariff_ambiguous/u,
  );
});

test("selected tariff feeds the frozen fare-v1 calculation", () => {
  const tariff = selectApprovedTariffVersionV1(
    [baseTariff()],
    "TR-ANKARA-METRO",
    1757000000000,
  );

  const fare = calculatePricingFareV1({
    distanceMeters: 18200,
    openingFeeMinor: tariff.openingFeeMinor,
    distanceRateMinorPerKm: tariff.distanceRateMinorPerKm,
    minimumFareMinor: tariff.minimumFareMinor,
  });

  assert.equal(fare.referenceEstimatedFareMinor, 68700);
  assert.equal(fare.yoldaalFareMinor, 27480);
  assert.equal(fare.savingMinor, 41220);
});

test("tariff-v1 contains no waiting, time or toll monetary component", () => {
  const keys = Object.keys(baseTariff()).sort();
  assert.equal(keys.includes("waitingFeeMinor"), false);
  assert.equal(keys.includes("timeRateMinor"), false);
  assert.equal(keys.includes("tollFeeMinor"), false);
  assert.equal(keys.includes("parkingFeeMinor"), false);
});
