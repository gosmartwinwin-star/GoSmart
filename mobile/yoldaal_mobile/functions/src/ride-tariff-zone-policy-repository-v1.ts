import type {
  Firestore,
} from "firebase-admin/firestore";
import type {
  PickupJurisdictionEvidenceV1,
} from "./ride-tariff-zone-jurisdiction-evidence-v1.js";
import {
  buildTariffZoneJurisdictionMatchV1,
  parseTariffZonePolicyVersionV1,
  selectApprovedTariffZonePolicyVersionV1,
} from "./ride-tariff-zone-policy-v1.js";
import type {
  TariffZonePolicyVersionV1,
} from "./ride-tariff-zone-policy-v1.js";
import type {
  TariffZonePolicyResolverV1,
} from "./ride-tariff-zone-resolver-v1.js";

export const TARIFF_ZONE_POLICIES_COLLECTION =
  "tariffZonePolicies" as const;

export const MAX_TARIFF_ZONE_POLICY_VERSIONS_PER_JURISDICTION =
  100;

const TARIFF_ZONE_POLICY_QUERY_LIMIT =
  MAX_TARIFF_ZONE_POLICY_VERSIONS_PER_JURISDICTION +
  1;

const fail = (reason: string): never => {
  throw new RangeError(reason);
};

const requireQuoteAtMillis = (
  value: number,
): number => {
  if (
    !Number.isSafeInteger(value) ||
    value < 0
  ) {
    return fail(
      "tariff_zone_policy_quote_at_invalid",
    );
  }
  return value;
};

export const loadApprovedTariffZonePolicyVersionV1 =
  async (
    firestore: Firestore,
    evidence:
      PickupJurisdictionEvidenceV1,
    quoteAtMillisRaw: number,
  ): Promise<TariffZonePolicyVersionV1> => {
    const quoteAtMillis =
      requireQuoteAtMillis(
        quoteAtMillisRaw,
      );
    const jurisdiction =
      buildTariffZoneJurisdictionMatchV1(
        evidence,
      );

    let snapshot;
    try {
      snapshot = await firestore
        .collection(
          TARIFF_ZONE_POLICIES_COLLECTION,
        )
        .where(
          "jurisdictionKey",
          "==",
          jurisdiction.jurisdictionKey,
        )
        .limit(
          TARIFF_ZONE_POLICY_QUERY_LIMIT,
        )
        .get();
    } catch (_error: unknown) {
      return fail(
        "tariff_zone_policy_repository_unavailable",
      );
    }

    if (
      snapshot.docs.length >
      MAX_TARIFF_ZONE_POLICY_VERSIONS_PER_JURISDICTION
    ) {
      return fail(
        "tariff_zone_policy_version_limit_exceeded",
      );
    }

    const policies =
      snapshot.docs.map((document) => {
        const parsed =
          parseTariffZonePolicyVersionV1(
            document.data(),
          );
        if (
          parsed.tariffZonePolicyVersionId !==
          document.id
        ) {
          return fail(
            "tariff_zone_policy_document_id_mismatch",
          );
        }
        return parsed;
      });

    return selectApprovedTariffZonePolicyVersionV1(
      policies,
      evidence,
      quoteAtMillis,
    );
  };

export const createFirestoreTariffZonePolicyResolverV1 =
  (
    firestore: Firestore,
  ): TariffZonePolicyResolverV1 =>
    async (
      evidence,
      quoteAtMillis,
    ): Promise<string> => {
      const policy =
        await loadApprovedTariffZonePolicyVersionV1(
          firestore,
          evidence,
          quoteAtMillis,
        );
      return policy.tariffZoneId;
    };
