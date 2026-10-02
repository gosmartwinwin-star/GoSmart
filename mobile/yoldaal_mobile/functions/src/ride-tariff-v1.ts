export const TARIFF_V1_CURRENCY = "TRY" as const;

export const TARIFF_APPROVAL_STATUSES = [
  "candidate",
  "approved",
  "rejected",
] as const;

export type TariffApprovalStatus =
  typeof TARIFF_APPROVAL_STATUSES[number];

export const TARIFF_AUTHORITY_TYPES = [
  "municipality",
  "ukome",
  "other_official",
] as const;

export type TariffAuthorityType =
  typeof TARIFF_AUTHORITY_TYPES[number];

export type TariffVersionV1 = {
  tariffVersionId: string;
  tariffZoneId: string;
  approvalStatus: TariffApprovalStatus;
  active: boolean;
  currency: typeof TARIFF_V1_CURRENCY;
  authorityType: TariffAuthorityType;
  authorityName: string;
  sourceUrl: string;
  decisionReference: string;
  publishedAtMillis: number;
  effectiveFromMillis: number;
  effectiveUntilMillis: number | null;
  verifiedAtMillis: number;
  approvedAtMillis: number | null;
  openingFeeMinor: number;
  distanceRateMinorPerKm: number;
  minimumFareMinor: number;
};

const fail = (reason: string): never => {
  throw new RangeError(reason);
};

const requireRecord = (
  value: unknown,
): Record<string, unknown> => {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value) ||
    Object.getPrototypeOf(value) !== Object.prototype
  ) {
    return fail("tariff_record_invalid");
  }
  return value as Record<string, unknown>;
};

const exactKeys = (
  value: Record<string, unknown>,
  expected: readonly string[],
): void => {
  const actual = Object.keys(value);
  if (
    actual.length !== expected.length ||
    expected.some((key) => !actual.includes(key))
  ) {
    fail("tariff_record_keys_invalid");
  }
};

const hasAsciiControlCharacter = (
  value: string,
): boolean =>
  value.split("").some((character) => {
    const codeUnit = character.charCodeAt(0);
    return codeUnit <= 31 || codeUnit === 127;
  });

const boundedText = (
  value: unknown,
  field: string,
  maxLength: number,
): string => {
  if (typeof value !== "string") {
    return fail(`${field}_invalid`);
  }
  const normalized = value.trim();
  if (
    normalized.length === 0 ||
    normalized.length > maxLength ||
    hasAsciiControlCharacter(normalized)
  ) {
    return fail(`${field}_invalid`);
  }
  return normalized;
};

const timestampMillis = (
  value: unknown,
  field: string,
): number => {
  if (!Number.isSafeInteger(value) || (value as number) < 0) {
    return fail(`${field}_invalid`);
  }
  return value as number;
};

const nullableTimestampMillis = (
  value: unknown,
  field: string,
): number | null => {
  if (value === null) {
    return null;
  }
  return timestampMillis(value, field);
};

const nonNegativeMoney = (
  value: unknown,
  field: string,
): number => {
  if (!Number.isSafeInteger(value) || (value as number) < 0) {
    return fail(`${field}_invalid`);
  }
  return value as number;
};

const requireEnum = <T extends string>(
  value: unknown,
  allowed: readonly T[],
  field: string,
): T => {
  if (typeof value !== "string" || !allowed.includes(value as T)) {
    return fail(`${field}_invalid`);
  }
  return value as T;
};

const requireBoolean = (
  value: unknown,
  field: string,
): boolean => {
  if (value === true) {
    return true;
  }
  if (value === false) {
    return false;
  }
  return fail(`${field}_invalid`);
};

const TARIFF_KEYS = [
  "tariffVersionId",
  "tariffZoneId",
  "approvalStatus",
  "active",
  "currency",
  "authorityType",
  "authorityName",
  "sourceUrl",
  "decisionReference",
  "publishedAtMillis",
  "effectiveFromMillis",
  "effectiveUntilMillis",
  "verifiedAtMillis",
  "approvedAtMillis",
  "openingFeeMinor",
  "distanceRateMinorPerKm",
  "minimumFareMinor",
] as const;

export const parseTariffVersionV1 = (
  raw: unknown,
): TariffVersionV1 => {
  const record = requireRecord(raw);
  exactKeys(record, TARIFF_KEYS);

  const tariffVersionId = boundedText(
    record.tariffVersionId,
    "tariff_version_id",
    120,
  );
  const tariffZoneId = boundedText(
    record.tariffZoneId,
    "tariff_zone_id",
    120,
  );
  const approvalStatus = requireEnum(
    record.approvalStatus,
    TARIFF_APPROVAL_STATUSES,
    "tariff_approval_status",
  );
  const active = requireBoolean(
    record.active,
    "tariff_active",
  );
  if (record.currency !== TARIFF_V1_CURRENCY) {
    fail("tariff_currency_invalid");
  }
  const authorityType = requireEnum(
    record.authorityType,
    TARIFF_AUTHORITY_TYPES,
    "tariff_authority_type",
  );
  const authorityName = boundedText(
    record.authorityName,
    "tariff_authority_name",
    200,
  );
  const sourceUrl = boundedText(
    record.sourceUrl,
    "tariff_source_url",
    1000,
  );
  let parsedUrl: URL;
  try {
    parsedUrl = new URL(sourceUrl);
  } catch (_error: unknown) {
    return fail("tariff_source_url_invalid");
  }
  if (parsedUrl.protocol !== "https:") {
    fail("tariff_source_url_invalid");
  }

  const decisionReference = boundedText(
    record.decisionReference,
    "tariff_decision_reference",
    240,
  );
  const publishedAtMillis = timestampMillis(
    record.publishedAtMillis,
    "tariff_published_at",
  );
  const effectiveFromMillis = timestampMillis(
    record.effectiveFromMillis,
    "tariff_effective_from",
  );
  const effectiveUntilMillis = nullableTimestampMillis(
    record.effectiveUntilMillis,
    "tariff_effective_until",
  );
  const verifiedAtMillis = timestampMillis(
    record.verifiedAtMillis,
    "tariff_verified_at",
  );
  const approvedAtMillis = nullableTimestampMillis(
    record.approvedAtMillis,
    "tariff_approved_at",
  );

  if (
    effectiveUntilMillis !== null &&
    effectiveUntilMillis <= effectiveFromMillis
  ) {
    fail("tariff_effective_interval_invalid");
  }
  if (
    approvalStatus === "approved" &&
    approvedAtMillis === null
  ) {
    fail("tariff_approved_at_required");
  }
  if (
    approvalStatus !== "approved" &&
    approvedAtMillis !== null
  ) {
    fail("tariff_approved_at_forbidden");
  }

  return {
    tariffVersionId,
    tariffZoneId,
    approvalStatus,
    active,
    currency: TARIFF_V1_CURRENCY,
    authorityType,
    authorityName,
    sourceUrl,
    decisionReference,
    publishedAtMillis,
    effectiveFromMillis,
    effectiveUntilMillis,
    verifiedAtMillis,
    approvedAtMillis,
    openingFeeMinor: nonNegativeMoney(
      record.openingFeeMinor,
      "tariff_opening_fee_minor",
    ),
    distanceRateMinorPerKm: nonNegativeMoney(
      record.distanceRateMinorPerKm,
      "tariff_distance_rate_minor_per_km",
    ),
    minimumFareMinor: nonNegativeMoney(
      record.minimumFareMinor,
      "tariff_minimum_fare_minor",
    ),
  };
};

export const selectApprovedTariffVersionV1 = (
  rawTariffs: readonly unknown[],
  tariffZoneIdRaw: unknown,
  quoteAtMillisRaw: unknown,
): TariffVersionV1 => {
  const tariffZoneId = boundedText(
    tariffZoneIdRaw,
    "tariff_zone_id",
    120,
  );
  const quoteAtMillis = timestampMillis(
    quoteAtMillisRaw,
    "tariff_quote_at",
  );

  const eligible = rawTariffs
    .map(parseTariffVersionV1)
    .filter((tariff) =>
      tariff.tariffZoneId === tariffZoneId &&
      tariff.approvalStatus === "approved" &&
      tariff.active &&
      tariff.effectiveFromMillis <= quoteAtMillis &&
      (
        tariff.effectiveUntilMillis === null ||
        quoteAtMillis < tariff.effectiveUntilMillis
      ),
    );

  if (eligible.length === 0) {
    return fail("approved_tariff_not_found");
  }
  if (eligible.length !== 1) {
    return fail("approved_tariff_ambiguous");
  }
  return eligible[0];
};
