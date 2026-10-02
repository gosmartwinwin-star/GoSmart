import {
  PickupJurisdictionAddressComponentsLookupV1,
} from "./ride-tariff-zone-jurisdiction-evidence-provider-v1.js";
import {
  PickupJurisdictionEvidenceV1,
  parsePickupJurisdictionEvidenceV1,
} from "./ride-tariff-zone-jurisdiction-evidence-v1.js";

export const GOOGLE_GEOCODING_V4_LOCATION_ENDPOINT =
  "https://geocode.googleapis.com/v4/geocode/location" as const;

export const GOOGLE_GEOCODING_V4_FIELD_MASK =
  "results.addressComponents" as const;

type FetchResponseV1 = {
  ok: boolean;
  json: () => Promise<unknown>;
};

export type GoogleGeocodingFetchV1 = (
  input: string,
  init: {
    method: "GET";
    headers: Readonly<Record<string, string>>;
  },
) => Promise<FetchResponseV1>;

export type GoogleGeocodingV4LookupDependenciesV1 = {
  apiKey: string;
  fetch: GoogleGeocodingFetchV1;
};

type AreaV1 = {
  longText: string;
  shortText: string;
};

const fail = (reason: string): never => {
  throw new RangeError(reason);
};

const isRecord = (
  value: unknown,
): value is Record<string, unknown> =>
  typeof value === "object" &&
  value !== null &&
  !Array.isArray(value);

const hasAsciiControlCharacter = (
  value: string,
): boolean =>
  value.split("").some((character) => {
    const code = character.charCodeAt(0);
    return code <= 31 || code === 127;
  });

const requireApiKey = (
  value: string,
): string => {
  if (typeof value !== "string") {
    return fail(
      "google_geocoding_v4_api_key_invalid",
    );
  }

  const normalized = value.trim();
  if (
    normalized.length < 8 ||
    normalized.length > 512 ||
    hasAsciiControlCharacter(normalized)
  ) {
    return fail(
      "google_geocoding_v4_api_key_invalid",
    );
  }

  return normalized;
};

const requireCoordinate = (
  value: number,
  minimum: number,
  maximum: number,
): number => {
  if (
    typeof value !== "number" ||
    !Number.isFinite(value) ||
    value < minimum ||
    value > maximum
  ) {
    return fail(
      "google_geocoding_v4_coordinate_invalid",
    );
  }
  return value;
};

const sameArea = (
  left: AreaV1 | null,
  right: AreaV1 | null,
): boolean =>
  left === null ?
    right === null :
    right !== null &&
    left.longText === right.longText &&
    left.shortText === right.shortText;

const mergeOptionalArea = (
  current: AreaV1 | null,
  candidate: AreaV1 | null,
): AreaV1 | null => {
  if (current === null) {
    return candidate;
  }
  if (candidate === null) {
    return current;
  }
  if (!sameArea(current, candidate)) {
    return fail(
      "google_geocoding_v4_jurisdiction_ambiguous",
    );
  }
  return current;
};

const sameRequiredArea = (
  left: AreaV1,
  right: AreaV1,
): boolean =>
  left.longText === right.longText &&
  left.shortText === right.shortText;

const extractEvidenceCandidates = (
  raw: unknown,
): PickupJurisdictionEvidenceV1[] => {
  if (!isRecord(raw) || !Array.isArray(raw.results)) {
    return fail(
      "google_geocoding_v4_response_invalid",
    );
  }

  const candidates:
    PickupJurisdictionEvidenceV1[] = [];

  for (const result of raw.results) {
    if (
      !isRecord(result) ||
      !Object.prototype.hasOwnProperty.call(
        result,
        "addressComponents",
      )
    ) {
      continue;
    }

    try {
      candidates.push(
        parsePickupJurisdictionEvidenceV1(
          result.addressComponents,
        ),
      );
    } catch (_error: unknown) {
      continue;
    }
  }

  if (candidates.length === 0) {
    return fail(
      "google_geocoding_v4_jurisdiction_missing",
    );
  }

  return candidates;
};

const synthesizeComponents = (
  candidates:
    readonly PickupJurisdictionEvidenceV1[],
): readonly Record<string, unknown>[] => {
  const first = candidates[0];

  let level2 =
    first.administrativeAreaLevel2;
  let locality =
    first.locality;

  for (const candidate of candidates.slice(1)) {
    if (
      candidate.countryCode !== first.countryCode ||
      !sameRequiredArea(
        candidate.administrativeAreaLevel1,
        first.administrativeAreaLevel1,
      )
    ) {
      return fail(
        "google_geocoding_v4_jurisdiction_ambiguous",
      );
    }

    level2 = mergeOptionalArea(
      level2,
      candidate.administrativeAreaLevel2,
    );
    locality = mergeOptionalArea(
      locality,
      candidate.locality,
    );
  }

  const components:
    Record<string, unknown>[] = [
      {
        longText: "Turkiye",
        shortText: "TR",
        types: ["country", "political"],
      },
      {
        longText:
          first.administrativeAreaLevel1.longText,
        shortText:
          first.administrativeAreaLevel1.shortText,
        types: [
          "administrative_area_level_1",
          "political",
        ],
      },
    ];

  if (level2 !== null) {
    components.push({
      longText: level2.longText,
      shortText: level2.shortText,
      types: [
        "administrative_area_level_2",
        "political",
      ],
    });
  }

  if (locality !== null) {
    components.push({
      longText: locality.longText,
      shortText: locality.shortText,
      types: ["locality", "political"],
    });
  }

  return components;
};

export const createGoogleGeocodingV4AddressComponentsLookupV1 = (
  dependencies:
    GoogleGeocodingV4LookupDependenciesV1,
): PickupJurisdictionAddressComponentsLookupV1 => {
  const apiKey =
    requireApiKey(dependencies.apiKey);

  return async (
    pickup,
    _quoteAtMillis,
  ): Promise<unknown> => {
    const latitude = requireCoordinate(
      pickup.latitude,
      -90,
      90,
    );
    const longitude = requireCoordinate(
      pickup.longitude,
      -180,
      180,
    );

    const url = new URL(
      GOOGLE_GEOCODING_V4_LOCATION_ENDPOINT,
    );
    url.searchParams.set(
      "location.latitude",
      String(latitude),
    );
    url.searchParams.set(
      "location.longitude",
      String(longitude),
    );
    url.searchParams.set(
      "languageCode",
      "tr",
    );

    let response: FetchResponseV1;
    try {
      response = await dependencies.fetch(
        url.toString(),
        {
          method: "GET",
          headers: {
            "Content-Type":
              "application/json",
            "X-Goog-Api-Key": apiKey,
            "X-Goog-FieldMask":
              GOOGLE_GEOCODING_V4_FIELD_MASK,
          },
        },
      );
    } catch (_error: unknown) {
      return fail(
        "google_geocoding_v4_unavailable",
      );
    }

    if (!response.ok) {
      return fail(
        "google_geocoding_v4_unavailable",
      );
    }

    let raw: unknown;
    try {
      raw = await response.json();
    } catch (_error: unknown) {
      return fail(
        "google_geocoding_v4_response_invalid",
      );
    }

    return synthesizeComponents(
      extractEvidenceCandidates(raw),
    );
  };
};
