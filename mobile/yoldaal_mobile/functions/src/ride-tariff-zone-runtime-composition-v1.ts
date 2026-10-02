import type {
  FareQuoteTariffZoneResolverV1,
} from "./ride-fare-quote-provider-v1.js";
import {
  createPickupJurisdictionEvidenceProviderV1,
} from "./ride-tariff-zone-jurisdiction-evidence-provider-v1.js";
import {
  createGoogleGeocodingV4AddressComponentsLookupV1,
} from "./ride-tariff-zone-google-geocoding-v4-v1.js";
import type {
  GoogleGeocodingFetchV1,
} from "./ride-tariff-zone-google-geocoding-v4-v1.js";
import {
  createTariffZoneResolverV1,
} from "./ride-tariff-zone-resolver-v1.js";
import type {
  TariffZonePolicyResolverV1,
} from "./ride-tariff-zone-resolver-v1.js";

export type TariffZoneRuntimeCompositionDependenciesV1 = {
  googleGeocodingApiKey: string;
  fetch: GoogleGeocodingFetchV1;
  resolveZoneFromEvidence:
    TariffZonePolicyResolverV1;
};

export const createTariffZoneRuntimeResolverV1 = (
  dependencies:
    TariffZoneRuntimeCompositionDependenciesV1,
): FareQuoteTariffZoneResolverV1 => {
  const lookupAddressComponents =
    createGoogleGeocodingV4AddressComponentsLookupV1({
      apiKey:
        dependencies.googleGeocodingApiKey,
      fetch: dependencies.fetch,
    });

  const getPickupJurisdictionEvidence =
    createPickupJurisdictionEvidenceProviderV1({
      lookupAddressComponents,
    });

  return createTariffZoneResolverV1({
    getPickupJurisdictionEvidence,
    resolveZoneFromEvidence:
      dependencies.resolveZoneFromEvidence,
  });
};
