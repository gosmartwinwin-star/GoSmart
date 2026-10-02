import assert from "node:assert/strict";
import test from "node:test";
import type {
  Firestore,
} from "firebase-admin/firestore";
import type {
  PickupJurisdictionEvidenceV1,
} from "./ride-tariff-zone-jurisdiction-evidence-v1.js";
import {
  buildTariffZoneJurisdictionMatchV1,
} from "./ride-tariff-zone-policy-v1.js";
import {
  MAX_TARIFF_ZONE_POLICY_VERSIONS_PER_JURISDICTION,
  TARIFF_ZONE_POLICIES_COLLECTION,
  createFirestoreTariffZonePolicyResolverV1,
  loadApprovedTariffZonePolicyVersionV1,
} from "./ride-tariff-zone-policy-repository-v1.js";

type StoredDoc = {
  id: string;
  data: Record<string, unknown>;
};

const evidence =
  (): PickupJurisdictionEvidenceV1 => ({
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
  });

const storedPolicy = (
  overrides:
    Record<string, unknown> = {},
): StoredDoc => {
  const jurisdiction =
    buildTariffZoneJurisdictionMatchV1(
      evidence(),
    );

  const id =
    typeof overrides
      .tariffZonePolicyVersionId ===
      "string" ?
      overrides
        .tariffZonePolicyVersionId :
      "zone-policy-v1";

  return {
    id,
    data: {
      tariffZonePolicyVersionId: id,
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
    },
  };
};

const fakeFirestore = (
  docs: StoredDoc[],
  options: {
    rejectRead?: boolean;
  } = {},
) => {
  const calls: unknown[] = [];
  let writeCalls = 0;

  const firestore = {
    collection(
      collectionName: string,
    ) {
      calls.push({
        kind: "collection",
        collectionName,
      });

      return {
        where(
          field: string,
          op: string,
          value: unknown,
        ) {
          calls.push({
            kind: "where",
            field,
            op,
            value,
          });

          return {
            limit(limitValue: number) {
              calls.push({
                kind: "limit",
                limitValue,
              });

              return {
                async get() {
                  calls.push({
                    kind: "get",
                  });
                  if (options.rejectRead) {
                    throw new Error(
                      "private firestore detail",
                    );
                  }
                  return {
                    docs: docs.map(
                      (document) => ({
                        id: document.id,
                        data: () =>
                          document.data,
                      }),
                    ),
                  };
                },
                set() {
                  writeCalls += 1;
                },
              };
            },
          };
        },
      };
    },
  };

  return {
    firestore:
      firestore as unknown as Firestore,
    calls,
    writeCalls: () => writeCalls,
  };
};

test(
  "repository queries exact jurisdiction key with bounded read",
  async () => {
    const fake =
      fakeFirestore([
        storedPolicy(),
      ]);

    await loadApprovedTariffZonePolicyVersionV1(
      fake.firestore,
      evidence(),
      1500,
    );

    const jurisdiction =
      buildTariffZoneJurisdictionMatchV1(
        evidence(),
      );

    assert.deepEqual(
      fake.calls.slice(0, 4),
      [
        {
          kind: "collection",
          collectionName:
            TARIFF_ZONE_POLICIES_COLLECTION,
        },
        {
          kind: "where",
          field: "jurisdictionKey",
          op: "==",
          value:
            jurisdiction.jurisdictionKey,
        },
        {
          kind: "limit",
          limitValue:
            MAX_TARIFF_ZONE_POLICY_VERSIONS_PER_JURISDICTION +
            1,
        },
        {kind: "get"},
      ],
    );
  },
);

test(
  "repository preserves approved active effective selection",
  async () => {
    const fake =
      fakeFirestore([
        storedPolicy({
          tariffZonePolicyVersionId:
            "candidate",
          approvalStatus: "candidate",
          active: false,
          approvedAtMillis: null,
        }),
        storedPolicy({
          tariffZonePolicyVersionId:
            "approved",
          tariffZoneId:
            "TR-APPROVED-ZONE",
        }),
      ]);

    const result =
      await loadApprovedTariffZonePolicyVersionV1(
        fake.firestore,
        evidence(),
        1500,
      );

    assert.equal(
      result.tariffZonePolicyVersionId,
      "approved",
    );
    assert.equal(
      result.tariffZoneId,
      "TR-APPROVED-ZONE",
    );
  },
);

test(
  "resolver adapter returns only approved tariff zone id",
  async () => {
    const fake =
      fakeFirestore([
        storedPolicy({
          tariffZoneId:
            "TR-RESOLVED-ZONE",
        }),
      ]);

    const resolver =
      createFirestoreTariffZonePolicyResolverV1(
        fake.firestore,
      );

    assert.equal(
      await resolver(
        evidence(),
        1500,
      ),
      "TR-RESOLVED-ZONE",
    );
  },
);

test(
  "overlapping approved mappings fail closed",
  async () => {
    const fake =
      fakeFirestore([
        storedPolicy({
          tariffZonePolicyVersionId:
            "one",
        }),
        storedPolicy({
          tariffZonePolicyVersionId:
            "two",
        }),
      ]);

    await assert.rejects(
      () =>
        loadApprovedTariffZonePolicyVersionV1(
          fake.firestore,
          evidence(),
          1500,
        ),
      /approved_tariff_zone_policy_ambiguous/u,
    );
  },
);

test(
  "missing mapping fails closed",
  async () => {
    const fake =
      fakeFirestore([]);

    await assert.rejects(
      () =>
        loadApprovedTariffZonePolicyVersionV1(
          fake.firestore,
          evidence(),
          1500,
        ),
      /approved_tariff_zone_policy_not_found/u,
    );
  },
);

test(
  "repository binds Firestore document id to policy version id",
  async () => {
    const document = storedPolicy();
    document.id = "wrong-doc-id";

    const fake =
      fakeFirestore([document]);

    await assert.rejects(
      () =>
        loadApprovedTariffZonePolicyVersionV1(
          fake.firestore,
          evidence(),
          1500,
        ),
      /tariff_zone_policy_document_id_mismatch/u,
    );
  },
);

test(
  "repository fails closed above per-jurisdiction version limit",
  async () => {
    const docs =
      Array.from(
        {
          length:
            MAX_TARIFF_ZONE_POLICY_VERSIONS_PER_JURISDICTION +
            1,
        },
        (_unused, index) =>
          storedPolicy({
            tariffZonePolicyVersionId:
              `policy-${index}`,
          }),
      );

    const fake =
      fakeFirestore(docs);

    await assert.rejects(
      () =>
        loadApprovedTariffZonePolicyVersionV1(
          fake.firestore,
          evidence(),
          1500,
        ),
      /tariff_zone_policy_version_limit_exceeded/u,
    );
  },
);

test(
  "Firestore read failures are sanitized",
  async () => {
    const fake =
      fakeFirestore(
        [],
        {rejectRead: true},
      );

    await assert.rejects(
      () =>
        loadApprovedTariffZonePolicyVersionV1(
          fake.firestore,
          evidence(),
          1500,
        ),
      /tariff_zone_policy_repository_unavailable/u,
    );
  },
);

test(
  "invalid time and evidence fail before Firestore read",
  async () => {
    const invalidTime =
      fakeFirestore([]);

    await assert.rejects(
      () =>
        loadApprovedTariffZonePolicyVersionV1(
          invalidTime.firestore,
          evidence(),
          -1,
        ),
      /tariff_zone_policy_quote_at_invalid/u,
    );
    assert.equal(
      invalidTime.calls.length,
      0,
    );

    const invalidEvidence =
      fakeFirestore([]);

    await assert.rejects(
      () =>
        loadApprovedTariffZonePolicyVersionV1(
          invalidEvidence.firestore,
          {
            ...evidence(),
            countryCode:
              "DE" as "TR",
          },
          1500,
        ),
      /tariff_zone_policy_evidence_invalid/u,
    );
    assert.equal(
      invalidEvidence.calls.length,
      0,
    );
  },
);

test(
  "repository is read-only and defines no concrete mapping",
  async () => {
    const fake =
      fakeFirestore([
        storedPolicy(),
      ]);

    await loadApprovedTariffZonePolicyVersionV1(
      fake.firestore,
      evidence(),
      1500,
    );

    assert.equal(
      fake.writeCalls(),
      0,
    );

    const source =
      loadApprovedTariffZonePolicyVersionV1
        .toString();

    for (const forbidden of [
      ".set(",
      ".create(",
      ".update(",
      ".delete(",
      "Ankara",
      "Cankaya",
      "UKOME",
      "municipality",
    ]) {
      assert.equal(
        source.includes(forbidden),
        false,
      );
    }
  },
);
