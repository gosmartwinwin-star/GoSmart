import assert from "node:assert/strict";
import test from "node:test";
import type {
  PickupJurisdictionEvidenceV1,
} from "./ride-tariff-zone-jurisdiction-evidence-v1.js";
import {
  buildTariffZoneJurisdictionMatchV1,
  parseTariffZonePolicyVersionV1,
  selectApprovedTariffZonePolicyVersionV1,
} from "./ride-tariff-zone-policy-v1.js";

const evidence = (
  overrides: Partial<
    PickupJurisdictionEvidenceV1
  > = {},
): PickupJurisdictionEvidenceV1 => ({
  source:
    "google-address-components-v1",
  countryCode: "TR",
  administrativeAreaLevel1: {
    longText: "Province A",
    shortText: "Province A",
  },
  administrativeAreaLevel2: {
    longText: "District A",
    shortText: "District A",
  },
  locality: {
    longText: "Locality A",
    shortText: "Locality A",
  },
  ...overrides,
});

const policy = (
  overrides: Record<string, unknown> = {},
): Record<string, unknown> => {
  const jurisdiction =
    buildTariffZoneJurisdictionMatchV1(
      evidence(),
    );

  return {
    tariffZonePolicyVersionId:
      "zone-policy-v1",
    ...jurisdiction,
    tariffZoneId: "TR-TEST-ZONE",
    approvalStatus: "approved",
    active: true,
    policyReference:
      "approved-backend-mapping",
    effectiveFromMillis: 1000,
    effectiveUntilMillis: null,
    approvedAtMillis: 900,
    ...overrides,
  };
};

test(
  "canonical version parses exact self-describing jurisdiction mapping",
  () => {
    const parsed =
      parseTariffZonePolicyVersionV1(
        policy(),
      );

    assert.equal(
      parsed.tariffZoneId,
      "TR-TEST-ZONE",
    );
    assert.equal(
      parsed.countryCode,
      "TR",
    );
    assert.match(
      parsed.jurisdictionKey,
      /^[a-f0-9]{64}$/u,
    );
  },
);

test(
  "jurisdiction key is deterministic for identical normalized evidence",
  () => {
    const first =
      buildTariffZoneJurisdictionMatchV1(
        evidence(),
      );
    const second =
      buildTariffZoneJurisdictionMatchV1(
        evidence(),
      );

    assert.deepEqual(first, second);
  },
);

test(
  "jurisdiction key changes when authoritative evidence changes",
  () => {
    const base =
      buildTariffZoneJurisdictionMatchV1(
        evidence(),
      );

    const changedLevel2 =
      buildTariffZoneJurisdictionMatchV1(
        evidence({
          administrativeAreaLevel2: {
            longText: "District B",
            shortText: "District B",
          },
        }),
      );

    const changedLocality =
      buildTariffZoneJurisdictionMatchV1(
        evidence({
          locality: null,
        }),
      );

    assert.notEqual(
      base.jurisdictionKey,
      changedLevel2.jurisdictionKey,
    );
    assert.notEqual(
      base.jurisdictionKey,
      changedLocality.jurisdictionKey,
    );
  },
);

test(
  "policy parser rejects extra fields and non-TR jurisdiction",
  () => {
    assert.throws(
      () =>
        parseTariffZonePolicyVersionV1({
          ...policy(),
          unexpected: true,
        }),
      /tariff_zone_policy_record_keys_invalid/u,
    );

    assert.throws(
      () =>
        parseTariffZonePolicyVersionV1({
          ...policy(),
          countryCode: "DE",
        }),
      /tariff_zone_policy_jurisdiction_invalid/u,
    );
  },
);

test(
  "stored jurisdiction key must match stored evidence fields",
  () => {
    assert.throws(
      () =>
        parseTariffZonePolicyVersionV1({
          ...policy(),
          administrativeAreaLevel1ShortText:
            "Tampered",
        }),
      /tariff_zone_policy_jurisdiction_key_mismatch/u,
    );
  },
);

test(
  "optional jurisdiction text pairs must be structurally exact",
  () => {
    assert.throws(
      () =>
        parseTariffZonePolicyVersionV1({
          ...policy(),
          administrativeAreaLevel2LongText:
            null,
        }),
      /tariff_zone_policy_admin2_pair_invalid/u,
    );

    assert.throws(
      () =>
        parseTariffZonePolicyVersionV1({
          ...policy(),
          localityShortText: null,
        }),
      /tariff_zone_policy_locality_pair_invalid/u,
    );
  },
);

test(
  "approval timestamp and effective interval semantics are strict",
  () => {
    assert.throws(
      () =>
        parseTariffZonePolicyVersionV1({
          ...policy(),
          approvedAtMillis: null,
        }),
      /tariff_zone_policy_approved_at_required/u,
    );

    assert.throws(
      () =>
        parseTariffZonePolicyVersionV1({
          ...policy(),
          approvalStatus: "candidate",
          approvedAtMillis: 900,
        }),
      /tariff_zone_policy_approved_at_forbidden/u,
    );

    assert.throws(
      () =>
        parseTariffZonePolicyVersionV1({
          ...policy(),
          effectiveUntilMillis: 1000,
        }),
      /tariff_zone_policy_effective_interval_invalid/u,
    );
  },
);

test(
  "selector uses exact jurisdiction and half-open effective interval",
  () => {
    const selected =
      selectApprovedTariffZonePolicyVersionV1(
        [{
          ...policy(),
          effectiveUntilMillis: 2000,
        }],
        evidence(),
        1999,
      );

    assert.equal(
      selected.tariffZonePolicyVersionId,
      "zone-policy-v1",
    );

    assert.throws(
      () =>
        selectApprovedTariffZonePolicyVersionV1(
          [{
            ...policy(),
            effectiveUntilMillis: 2000,
          }],
          evidence(),
          2000,
        ),
      /approved_tariff_zone_policy_not_found/u,
    );
  },
);

test(
  "selector fails closed for missing and overlapping approved mappings",
  () => {
    assert.throws(
      () =>
        selectApprovedTariffZonePolicyVersionV1(
          [],
          evidence(),
          1500,
        ),
      /approved_tariff_zone_policy_not_found/u,
    );

    assert.throws(
      () =>
        selectApprovedTariffZonePolicyVersionV1(
          [
            policy(),
            policy({
              tariffZonePolicyVersionId:
                "zone-policy-v2",
            }),
          ],
          evidence(),
          1500,
        ),
      /approved_tariff_zone_policy_ambiguous/u,
    );
  },
);

test(
  "policy contract defines no wildcard precedence or concrete legal mapping",
  () => {
    const source =
      selectApprovedTariffZonePolicyVersionV1
        .toString();

    for (const forbidden of [
      "wildcard",
      "precedence",
      "municipality",
      "UKOME",
      "Ankara",
      "Cankaya",
      "dropoff",
      "driverId",
      "passengerId",
    ]) {
      assert.equal(
        source.includes(forbidden),
        false,
      );
    }
  },
);
