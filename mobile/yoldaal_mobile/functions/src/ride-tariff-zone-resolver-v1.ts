import {
  FareQuoteTariffZoneResolverV1,
} from "./ride-fare-quote-provider-v1.js";
import {
  PickupJurisdictionEvidenceV1,
} from "./ride-tariff-zone-jurisdiction-evidence-v1.js";
import {
  PickupJurisdictionEvidenceProviderV1,
} from "./ride-tariff-zone-jurisdiction-evidence-provider-v1.js";

export type TariffZonePolicyResolverV1 = (
  evidence: PickupJurisdictionEvidenceV1,
  quoteAtMillis: number,
) => Promise<unknown>;

export type TariffZoneResolverDependenciesV1 = {
  getPickupJurisdictionEvidence:
    PickupJurisdictionEvidenceProviderV1;
  resolveZoneFromEvidence:
    TariffZonePolicyResolverV1;
};

const fail = (reason: string): never => {
  throw new RangeError(reason);
};

const hasAsciiControlCharacter = (
  value: string,
): boolean =>
  value.split("").some((character) => {
    const codeUnit =
      character.charCodeAt(0);
    return codeUnit <= 31 || codeUnit === 127;
  });

const requireTariffZoneId = (
  value: unknown,
): string => {
  if (typeof value !== "string") {
    return fail(
      "tariff_zone_id_invalid",
    );
  }

  const normalized = value.trim();
  if (
    normalized.length === 0 ||
    normalized.length > 120 ||
    hasAsciiControlCharacter(
      normalized,
    )
  ) {
    return fail(
      "tariff_zone_id_invalid",
    );
  }

  return normalized;
};

const requireQuoteAtMillis = (
  value: number,
): number => {
  if (
    !Number.isSafeInteger(value) ||
    value < 0
  ) {
    return fail(
      "tariff_quote_at_invalid",
    );
  }
  return value;
};

export const createTariffZoneResolverV1 = (
  dependencies:
    TariffZoneResolverDependenciesV1,
): FareQuoteTariffZoneResolverV1 =>
  async (
    input,
    quoteAtMillisRaw,
  ): Promise<string> => {
    const quoteAtMillis =
      requireQuoteAtMillis(
        quoteAtMillisRaw,
      );

    const evidence =
      await dependencies
        .getPickupJurisdictionEvidence(
          input,
          quoteAtMillis,
        );

    let rawZoneId: unknown;
    try {
      rawZoneId =
        await dependencies
          .resolveZoneFromEvidence(
            evidence,
            quoteAtMillis,
          );
    } catch (_error: unknown) {
      return fail(
        "tariff_zone_policy_unavailable",
      );
    }

    return requireTariffZoneId(
      rawZoneId,
    );
  };
