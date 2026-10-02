export const PICKUP_JURISDICTION_EVIDENCE_SOURCE_V1 =
  "google-address-components-v1" as const;

export type JurisdictionAdministrativeAreaV1 = {
  longText: string;
  shortText: string;
};

export type PickupJurisdictionEvidenceV1 = {
  source:
    typeof PICKUP_JURISDICTION_EVIDENCE_SOURCE_V1;
  countryCode: "TR";
  administrativeAreaLevel1:
    JurisdictionAdministrativeAreaV1;
  administrativeAreaLevel2:
    JurisdictionAdministrativeAreaV1 | null;
  locality:
    JurisdictionAdministrativeAreaV1 | null;
};

type ParsedAddressComponentV1 = {
  longText: string;
  shortText: string;
  types: readonly string[];
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
  [...value].some((character) => {
    const code = character.charCodeAt(0);
    return code <= 31 || code === 127;
  });

const boundedText = (
  value: unknown,
  maxLength: number,
): string => {
  if (typeof value !== "string") {
    return fail(
      "tariff_zone_jurisdiction_evidence_invalid",
    );
  }

  const normalized = value.trim();
  if (
    normalized.length === 0 ||
    normalized.length > maxLength ||
    hasAsciiControlCharacter(normalized)
  ) {
    return fail(
      "tariff_zone_jurisdiction_evidence_invalid",
    );
  }

  return normalized;
};

const parseTypes = (
  value: unknown,
): readonly string[] => {
  if (
    !Array.isArray(value) ||
    value.length === 0 ||
    value.length > 16
  ) {
    return fail(
      "tariff_zone_jurisdiction_evidence_invalid",
    );
  }

  const parsed = value.map(
    (item) => boundedText(item, 80),
  );

  if (
    new Set(parsed).size !== parsed.length
  ) {
    return fail(
      "tariff_zone_jurisdiction_evidence_invalid",
    );
  }

  return parsed;
};

const parseComponent = (
  value: unknown,
): ParsedAddressComponentV1 => {
  if (!isRecord(value)) {
    return fail(
      "tariff_zone_jurisdiction_evidence_invalid",
    );
  }

  const keys = Object.keys(value).sort();
  const required = [
    "longText",
    "shortText",
    "types",
  ];

  const allowed = new Set([
    ...required,
    "languageCode",
  ]);

  if (
    keys.some((key) => !allowed.has(key)) ||
    required.some(
      (key) =>
        !Object.prototype.hasOwnProperty.call(
          value,
          key,
        ),
    )
  ) {
    return fail(
      "tariff_zone_jurisdiction_evidence_invalid",
    );
  }

  if (
    Object.prototype.hasOwnProperty.call(
      value,
      "languageCode",
    )
  ) {
    boundedText(
      value.languageCode,
      35,
    );
  }

  return {
    longText: boundedText(
      value.longText,
      200,
    ),
    shortText: boundedText(
      value.shortText,
      80,
    ),
    types: parseTypes(value.types),
  };
};

const area = (
  component: ParsedAddressComponentV1,
): JurisdictionAdministrativeAreaV1 => ({
  longText: component.longText,
  shortText: component.shortText,
});

const singleByType = (
  components: readonly ParsedAddressComponentV1[],
  type: string,
  required: boolean,
): ParsedAddressComponentV1 | null => {
  const matches = components.filter(
    (component) =>
      component.types.includes(type),
  );

  if (
    matches.length > 1 ||
    (required && matches.length !== 1)
  ) {
    return fail(
      "tariff_zone_jurisdiction_evidence_invalid",
    );
  }

  return matches[0] ?? null;
};

export const parsePickupJurisdictionEvidenceV1 = (
  rawAddressComponents: unknown,
): PickupJurisdictionEvidenceV1 => {
  if (
    !Array.isArray(rawAddressComponents) ||
    rawAddressComponents.length === 0 ||
    rawAddressComponents.length > 64
  ) {
    return fail(
      "tariff_zone_jurisdiction_evidence_invalid",
    );
  }

  const components =
    rawAddressComponents.map(
      parseComponent,
    );

  const country =
    singleByType(
      components,
      "country",
      true,
    );

  const administrativeAreaLevel1 =
    singleByType(
      components,
      "administrative_area_level_1",
      true,
    );

  const administrativeAreaLevel2 =
    singleByType(
      components,
      "administrative_area_level_2",
      false,
    );

  const locality =
    singleByType(
      components,
      "locality",
      false,
    );

  if (
    country === null ||
    administrativeAreaLevel1 === null ||
    country.shortText.toUpperCase() !==
      "TR"
  ) {
    return fail(
      "tariff_zone_jurisdiction_evidence_invalid",
    );
  }

  return {
    source:
      PICKUP_JURISDICTION_EVIDENCE_SOURCE_V1,
    countryCode: "TR",
    administrativeAreaLevel1:
      area(administrativeAreaLevel1),
    administrativeAreaLevel2:
      administrativeAreaLevel2 === null ?
        null :
        area(administrativeAreaLevel2),
    locality:
      locality === null ?
        null :
        area(locality),
  };
};
