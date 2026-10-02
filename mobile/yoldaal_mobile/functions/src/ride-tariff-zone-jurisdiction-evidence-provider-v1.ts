import {
  FareQuoteRequestV1,
  validateFareQuoteRequestV1,
} from "./ride-fare-quote-persistence-v1.js";
import {
  PickupJurisdictionEvidenceV1,
  parsePickupJurisdictionEvidenceV1,
} from "./ride-tariff-zone-jurisdiction-evidence-v1.js";

export type PickupJurisdictionLookupInputV1 = {
  latitude: number;
  longitude: number;
};

export type PickupJurisdictionAddressComponentsLookupV1 = (
  pickup: PickupJurisdictionLookupInputV1,
  quoteAtMillis: number,
) => Promise<unknown>;

export type PickupJurisdictionEvidenceProviderDependenciesV1 = {
  lookupAddressComponents:
    PickupJurisdictionAddressComponentsLookupV1;
};

export type PickupJurisdictionEvidenceProviderV1 = (
  input: FareQuoteRequestV1,
  quoteAtMillis: number,
) => Promise<PickupJurisdictionEvidenceV1>;

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
      "tariff_zone_jurisdiction_quote_time_invalid",
    );
  }
  return value;
};

export const createPickupJurisdictionEvidenceProviderV1 = (
  dependencies:
    PickupJurisdictionEvidenceProviderDependenciesV1,
): PickupJurisdictionEvidenceProviderV1 =>
  async (
    rawInput: FareQuoteRequestV1,
    quoteAtMillisRaw: number,
  ): Promise<PickupJurisdictionEvidenceV1> => {
    const input =
      validateFareQuoteRequestV1(
        rawInput,
      );
    const quoteAtMillis =
      requireQuoteAtMillis(
        quoteAtMillisRaw,
      );

    let rawAddressComponents: unknown;
    try {
      rawAddressComponents =
        await dependencies
          .lookupAddressComponents(
            {
              latitude:
                input.pickup.latitude,
              longitude:
                input.pickup.longitude,
            },
            quoteAtMillis,
          );
    } catch (_error: unknown) {
      return fail(
        "tariff_zone_jurisdiction_evidence_unavailable",
      );
    }

    return parsePickupJurisdictionEvidenceV1(
      rawAddressComponents,
    );
  };
