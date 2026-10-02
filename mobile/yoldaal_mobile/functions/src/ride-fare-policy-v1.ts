import {
  PRICING_FARE_V1,
  YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS,
} from "./ride-pricing-fare-v1.js";

export const FARE_POLICY_V1_CURRENCY = "TRY" as const;

export const FARE_POLICY_APPROVAL_STATUSES = [
  "candidate",
  "approved",
  "rejected",
] as const;

export type FarePolicyApprovalStatus =
  typeof FARE_POLICY_APPROVAL_STATUSES[number];

export type FarePolicyVersionV1 = {
  farePolicyVersionId: string;
  approvalStatus: FarePolicyApprovalStatus;
  active: boolean;
  pricingVersion: typeof PRICING_FARE_V1;
  currency: typeof FARE_POLICY_V1_CURRENCY;
  passengerFareBasisPoints:
    typeof YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS;
  policyReference: string;
  effectiveFromMillis: number;
  effectiveUntilMillis: number | null;
  approvedAtMillis: number | null;
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
    return fail("fare_policy_record_invalid");
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
    fail("fare_policy_record_keys_invalid");
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

const requireApprovalStatus = (
  value: unknown,
): FarePolicyApprovalStatus => {
  if (
    typeof value !== "string" ||
    !FARE_POLICY_APPROVAL_STATUSES.includes(
      value as FarePolicyApprovalStatus,
    )
  ) {
    return fail("fare_policy_approval_status_invalid");
  }
  return value as FarePolicyApprovalStatus;
};

const POLICY_KEYS = [
  "farePolicyVersionId",
  "approvalStatus",
  "active",
  "pricingVersion",
  "currency",
  "passengerFareBasisPoints",
  "policyReference",
  "effectiveFromMillis",
  "effectiveUntilMillis",
  "approvedAtMillis",
] as const;

export const parseFarePolicyVersionV1 = (
  raw: unknown,
): FarePolicyVersionV1 => {
  const record = requireRecord(raw);
  exactKeys(record, POLICY_KEYS);

  const farePolicyVersionId = boundedText(
    record.farePolicyVersionId,
    "fare_policy_version_id",
    120,
  );
  const approvalStatus = requireApprovalStatus(
    record.approvalStatus,
  );
  const active = requireBoolean(
    record.active,
    "fare_policy_active",
  );

  if (record.pricingVersion !== PRICING_FARE_V1) {
    fail("fare_policy_pricing_version_invalid");
  }
  if (record.currency !== FARE_POLICY_V1_CURRENCY) {
    fail("fare_policy_currency_invalid");
  }
  if (
    record.passengerFareBasisPoints !==
    YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS
  ) {
    fail("fare_policy_basis_points_invalid");
  }

  const policyReference = boundedText(
    record.policyReference,
    "fare_policy_reference",
    240,
  );
  const effectiveFromMillis = timestampMillis(
    record.effectiveFromMillis,
    "fare_policy_effective_from",
  );
  const effectiveUntilMillis = nullableTimestampMillis(
    record.effectiveUntilMillis,
    "fare_policy_effective_until",
  );
  const approvedAtMillis = nullableTimestampMillis(
    record.approvedAtMillis,
    "fare_policy_approved_at",
  );

  if (
    effectiveUntilMillis !== null &&
    effectiveUntilMillis <= effectiveFromMillis
  ) {
    fail("fare_policy_effective_interval_invalid");
  }
  if (
    approvalStatus === "approved" &&
    approvedAtMillis === null
  ) {
    fail("fare_policy_approved_at_required");
  }
  if (
    approvalStatus !== "approved" &&
    approvedAtMillis !== null
  ) {
    fail("fare_policy_approved_at_forbidden");
  }

  return {
    farePolicyVersionId,
    approvalStatus,
    active,
    pricingVersion: PRICING_FARE_V1,
    currency: FARE_POLICY_V1_CURRENCY,
    passengerFareBasisPoints:
      YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS,
    policyReference,
    effectiveFromMillis,
    effectiveUntilMillis,
    approvedAtMillis,
  };
};

export const selectApprovedFarePolicyVersionV1 = (
  rawPolicies: readonly unknown[],
  quoteAtMillisRaw: unknown,
): FarePolicyVersionV1 => {
  const quoteAtMillis = timestampMillis(
    quoteAtMillisRaw,
    "fare_policy_quote_at",
  );

  const eligible = rawPolicies
    .map(parseFarePolicyVersionV1)
    .filter((policy) =>
      policy.approvalStatus === "approved" &&
      policy.active &&
      policy.effectiveFromMillis <= quoteAtMillis &&
      (
        policy.effectiveUntilMillis === null ||
        quoteAtMillis < policy.effectiveUntilMillis
      ),
    );

  if (eligible.length === 0) {
    return fail("approved_fare_policy_not_found");
  }
  if (eligible.length !== 1) {
    return fail("approved_fare_policy_ambiguous");
  }
  return eligible[0];
};
