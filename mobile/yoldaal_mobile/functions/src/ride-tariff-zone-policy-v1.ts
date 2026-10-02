import {createHash} from "node:crypto";
import type {
  PickupJurisdictionEvidenceV1,
} from "./ride-tariff-zone-jurisdiction-evidence-v1.js";

export const TARIFF_ZONE_POLICY_APPROVAL_STATUSES = [
  "candidate",
  "approved",
  "rejected",
] as const;

export type TariffZonePolicyApprovalStatus =
  typeof TARIFF_ZONE_POLICY_APPROVAL_STATUSES[number];

export type TariffZoneJurisdictionMatchV1 = {
  jurisdictionKey: string;
  jurisdictionEvidenceSource:
    "google-address-components-v1";
  countryCode: "TR";
  administrativeAreaLevel1LongText: string;
  administrativeAreaLevel1ShortText: string;
  administrativeAreaLevel2LongText: string | null;
  administrativeAreaLevel2ShortText: string | null;
  localityLongText: string | null;
  localityShortText: string | null;
};

export type TariffZonePolicyVersionV1 =
  TariffZoneJurisdictionMatchV1 & {
    tariffZonePolicyVersionId: string;
    tariffZoneId: string;
    approvalStatus:
      TariffZonePolicyApprovalStatus;
    active: boolean;
    policyReference: string;
    effectiveFromMillis: number;
    effectiveUntilMillis: number | null;
    approvedAtMillis: number | null;
  };

const fail = (reason: string): never => {
  throw new RangeError(reason);
};

const hasAsciiControlCharacter = (
  value: string,
): boolean =>
  value.split("").some((character) => {
    const code = character.charCodeAt(0);
    return code <= 31 || code === 127;
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

const nullableBoundedText = (
  value: unknown,
  field: string,
  maxLength: number,
): string | null => {
  if (value === null) {
    return null;
  }
  return boundedText(
    value,
    field,
    maxLength,
  );
};

const timestampMillis = (
  value: unknown,
  field: string,
): number => {
  if (
    typeof value !== "number" ||
    !Number.isSafeInteger(value) ||
    value < 0
  ) {
    return fail(`${field}_invalid`);
  }
  return value;
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

const requireRecord = (
  value: unknown,
): Record<string, unknown> => {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value) ||
    Object.getPrototypeOf(value) !==
      Object.prototype
  ) {
    return fail(
      "tariff_zone_policy_record_invalid",
    );
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
    expected.some(
      (key) => !actual.includes(key),
    )
  ) {
    fail(
      "tariff_zone_policy_record_keys_invalid",
    );
  }
};

const requireApprovalStatus = (
  value: unknown,
): TariffZonePolicyApprovalStatus => {
  if (
    typeof value !== "string" ||
    !TARIFF_ZONE_POLICY_APPROVAL_STATUSES
      .includes(
        value as TariffZonePolicyApprovalStatus,
      )
  ) {
    return fail(
      "tariff_zone_policy_approval_status_invalid",
    );
  }
  return value as TariffZonePolicyApprovalStatus;
};

const sha256 = (
  value: string,
): string =>
  createHash("sha256")
    .update(value)
    .digest("hex");

const jurisdictionKeyFromFields = (
  fields: Omit<
    TariffZoneJurisdictionMatchV1,
    "jurisdictionKey"
  >,
): string =>
  sha256(
    "tariff-zone-jurisdiction-v1:" +
    JSON.stringify({
      jurisdictionEvidenceSource:
        fields.jurisdictionEvidenceSource,
      countryCode: fields.countryCode,
      administrativeAreaLevel1LongText:
        fields.administrativeAreaLevel1LongText,
      administrativeAreaLevel1ShortText:
        fields.administrativeAreaLevel1ShortText,
      administrativeAreaLevel2LongText:
        fields.administrativeAreaLevel2LongText,
      administrativeAreaLevel2ShortText:
        fields.administrativeAreaLevel2ShortText,
      localityLongText:
        fields.localityLongText,
      localityShortText:
        fields.localityShortText,
    }),
  );

const requireOptionalPair = (
  longText: string | null,
  shortText: string | null,
  field: string,
): void => {
  if (
    (longText === null) !==
      (shortText === null)
  ) {
    fail(`${field}_pair_invalid`);
  }
};

export const buildTariffZoneJurisdictionMatchV1 = (
  evidence: PickupJurisdictionEvidenceV1,
): TariffZoneJurisdictionMatchV1 => {
  if (
    evidence.source !==
      "google-address-components-v1" ||
    evidence.countryCode !== "TR"
  ) {
    return fail(
      "tariff_zone_policy_evidence_invalid",
    );
  }

  const administrativeAreaLevel1LongText =
    boundedText(
      evidence.administrativeAreaLevel1
        .longText,
      "tariff_zone_policy_admin1_long",
      200,
    );
  const administrativeAreaLevel1ShortText =
    boundedText(
      evidence.administrativeAreaLevel1
        .shortText,
      "tariff_zone_policy_admin1_short",
      80,
    );

  const administrativeAreaLevel2LongText =
    evidence.administrativeAreaLevel2 ===
      null ?
      null :
      boundedText(
        evidence.administrativeAreaLevel2
          .longText,
        "tariff_zone_policy_admin2_long",
        200,
      );
  const administrativeAreaLevel2ShortText =
    evidence.administrativeAreaLevel2 ===
      null ?
      null :
      boundedText(
        evidence.administrativeAreaLevel2
          .shortText,
        "tariff_zone_policy_admin2_short",
        80,
      );

  const localityLongText =
    evidence.locality === null ?
      null :
      boundedText(
        evidence.locality.longText,
        "tariff_zone_policy_locality_long",
        200,
      );
  const localityShortText =
    evidence.locality === null ?
      null :
      boundedText(
        evidence.locality.shortText,
        "tariff_zone_policy_locality_short",
        80,
      );

  const fields = {
    jurisdictionEvidenceSource:
      "google-address-components-v1" as const,
    countryCode: "TR" as const,
    administrativeAreaLevel1LongText,
    administrativeAreaLevel1ShortText,
    administrativeAreaLevel2LongText,
    administrativeAreaLevel2ShortText,
    localityLongText,
    localityShortText,
  };

  return {
    jurisdictionKey:
      jurisdictionKeyFromFields(fields),
    ...fields,
  };
};

const POLICY_KEYS = [
  "tariffZonePolicyVersionId",
  "jurisdictionKey",
  "jurisdictionEvidenceSource",
  "countryCode",
  "administrativeAreaLevel1LongText",
  "administrativeAreaLevel1ShortText",
  "administrativeAreaLevel2LongText",
  "administrativeAreaLevel2ShortText",
  "localityLongText",
  "localityShortText",
  "tariffZoneId",
  "approvalStatus",
  "active",
  "policyReference",
  "effectiveFromMillis",
  "effectiveUntilMillis",
  "approvedAtMillis",
] as const;

export const parseTariffZonePolicyVersionV1 = (
  raw: unknown,
): TariffZonePolicyVersionV1 => {
  const record = requireRecord(raw);
  exactKeys(record, POLICY_KEYS);

  const tariffZonePolicyVersionId =
    boundedText(
      record.tariffZonePolicyVersionId,
      "tariff_zone_policy_version_id",
      120,
    );
  const jurisdictionKey =
    boundedText(
      record.jurisdictionKey,
      "tariff_zone_policy_jurisdiction_key",
      64,
    );
  if (
    !/^[a-f0-9]{64}$/u.test(
      jurisdictionKey,
    )
  ) {
    fail(
      "tariff_zone_policy_jurisdiction_key_invalid",
    );
  }

  if (
    record.jurisdictionEvidenceSource !==
      "google-address-components-v1" ||
    record.countryCode !== "TR"
  ) {
    fail(
      "tariff_zone_policy_jurisdiction_invalid",
    );
  }

  const administrativeAreaLevel1LongText =
    boundedText(
      record.administrativeAreaLevel1LongText,
      "tariff_zone_policy_admin1_long",
      200,
    );
  const administrativeAreaLevel1ShortText =
    boundedText(
      record.administrativeAreaLevel1ShortText,
      "tariff_zone_policy_admin1_short",
      80,
    );
  const administrativeAreaLevel2LongText =
    nullableBoundedText(
      record.administrativeAreaLevel2LongText,
      "tariff_zone_policy_admin2_long",
      200,
    );
  const administrativeAreaLevel2ShortText =
    nullableBoundedText(
      record.administrativeAreaLevel2ShortText,
      "tariff_zone_policy_admin2_short",
      80,
    );
  const localityLongText =
    nullableBoundedText(
      record.localityLongText,
      "tariff_zone_policy_locality_long",
      200,
    );
  const localityShortText =
    nullableBoundedText(
      record.localityShortText,
      "tariff_zone_policy_locality_short",
      80,
    );

  requireOptionalPair(
    administrativeAreaLevel2LongText,
    administrativeAreaLevel2ShortText,
    "tariff_zone_policy_admin2",
  );
  requireOptionalPair(
    localityLongText,
    localityShortText,
    "tariff_zone_policy_locality",
  );

  const jurisdictionFields = {
    jurisdictionEvidenceSource:
      "google-address-components-v1" as const,
    countryCode: "TR" as const,
    administrativeAreaLevel1LongText,
    administrativeAreaLevel1ShortText,
    administrativeAreaLevel2LongText,
    administrativeAreaLevel2ShortText,
    localityLongText,
    localityShortText,
  };

  if (
    jurisdictionKeyFromFields(
      jurisdictionFields,
    ) !== jurisdictionKey
  ) {
    fail(
      "tariff_zone_policy_jurisdiction_key_mismatch",
    );
  }

  const tariffZoneId = boundedText(
    record.tariffZoneId,
    "tariff_zone_policy_zone_id",
    120,
  );
  const approvalStatus =
    requireApprovalStatus(
      record.approvalStatus,
    );
  const active = requireBoolean(
    record.active,
    "tariff_zone_policy_active",
  );
  const policyReference = boundedText(
    record.policyReference,
    "tariff_zone_policy_reference",
    240,
  );
  const effectiveFromMillis =
    timestampMillis(
      record.effectiveFromMillis,
      "tariff_zone_policy_effective_from",
    );
  const effectiveUntilMillis =
    nullableTimestampMillis(
      record.effectiveUntilMillis,
      "tariff_zone_policy_effective_until",
    );
  const approvedAtMillis =
    nullableTimestampMillis(
      record.approvedAtMillis,
      "tariff_zone_policy_approved_at",
    );

  if (
    effectiveUntilMillis !== null &&
    effectiveUntilMillis <=
      effectiveFromMillis
  ) {
    fail(
      "tariff_zone_policy_effective_interval_invalid",
    );
  }

  if (
    approvalStatus === "approved" &&
    approvedAtMillis === null
  ) {
    fail(
      "tariff_zone_policy_approved_at_required",
    );
  }
  if (
    approvalStatus !== "approved" &&
    approvedAtMillis !== null
  ) {
    fail(
      "tariff_zone_policy_approved_at_forbidden",
    );
  }

  return {
    tariffZonePolicyVersionId,
    jurisdictionKey,
    ...jurisdictionFields,
    tariffZoneId,
    approvalStatus,
    active,
    policyReference,
    effectiveFromMillis,
    effectiveUntilMillis,
    approvedAtMillis,
  };
};

export const selectApprovedTariffZonePolicyVersionV1 = (
  rawPolicies: readonly unknown[],
  evidence: PickupJurisdictionEvidenceV1,
  quoteAtMillisRaw: unknown,
): TariffZonePolicyVersionV1 => {
  const quoteAtMillis =
    timestampMillis(
      quoteAtMillisRaw,
      "tariff_zone_policy_quote_at",
    );
  const jurisdiction =
    buildTariffZoneJurisdictionMatchV1(
      evidence,
    );

  const eligible = rawPolicies
    .map(parseTariffZonePolicyVersionV1)
    .filter((policy) =>
      policy.jurisdictionKey ===
        jurisdiction.jurisdictionKey &&
      policy.approvalStatus ===
        "approved" &&
      policy.active &&
      policy.effectiveFromMillis <=
        quoteAtMillis &&
      (
        policy.effectiveUntilMillis ===
          null ||
        quoteAtMillis <
          policy.effectiveUntilMillis
      ),
    );

  if (eligible.length === 0) {
    return fail(
      "approved_tariff_zone_policy_not_found",
    );
  }
  if (eligible.length !== 1) {
    return fail(
      "approved_tariff_zone_policy_ambiguous",
    );
  }

  return eligible[0];
};
