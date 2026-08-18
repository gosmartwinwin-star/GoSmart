import {
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";

export const DRIVER_PLAN_IDS = [
  "daily",
  "weekly",
  "monthly",
  "quarterly",
] as const;

export type DriverPlanId =
  (typeof DRIVER_PLAN_IDS)[number];

export type DriverPlanCatalogEntry = {
  enabled: boolean;
  amountMinor: number;
  currency: string;
};

export type DriverPlanCatalog = {
  catalogVersion: string;
  plans: Record<DriverPlanId, DriverPlanCatalogEntry>;
};

const DAY_MILLIS =
  24 * 60 * 60 * 1000;

const WEEK_MILLIS =
  7 * DAY_MILLIS;

const invalidCatalog = (): TypeError =>
  new TypeError("Invalid driver plan catalog.");

const isRecord = (
  value: unknown,
): value is Record<string, unknown> =>
  typeof value === "object" &&
  value !== null &&
  !Array.isArray(value);

const hasExactKeys = (
  value: Record<string, unknown>,
  expected: readonly string[],
): boolean => {
  const actual = Object.keys(value);

  return actual.length === expected.length &&
    actual.every((key) => expected.includes(key));
};

const parseEntry = (
  value: unknown,
): DriverPlanCatalogEntry => {
  if (!isRecord(value)) {
    throw invalidCatalog();
  }

  if (
    !hasExactKeys(
      value,
      ["enabled", "amountMinor", "currency"],
    )
  ) {
    throw invalidCatalog();
  }

  const enabled = value.enabled;
  const amountMinor = value.amountMinor;
  const currency = value.currency;

  if (typeof enabled !== "boolean") {
    throw invalidCatalog();
  }

  if (
    typeof amountMinor !== "number" ||
    !Number.isSafeInteger(amountMinor) ||
    amountMinor < 0
  ) {
    throw invalidCatalog();
  }

  if (
    typeof currency !== "string" ||
    !/^[A-Z]{3}$/.test(currency)
  ) {
    throw invalidCatalog();
  }

  return {
    enabled,
    amountMinor,
    currency,
  };
};

export const driverPlanCatalogFromData = (
  value: unknown,
): DriverPlanCatalog => {
  if (!isRecord(value)) {
    throw invalidCatalog();
  }

  if (
    !hasExactKeys(
      value,
      ["catalogVersion", "plans"],
    )
  ) {
    throw invalidCatalog();
  }

  const catalogVersion = value.catalogVersion;
  const plans = value.plans;

  if (
    typeof catalogVersion !== "string" ||
    catalogVersion.trim().length === 0
  ) {
    throw invalidCatalog();
  }

  if (!isRecord(plans)) {
    throw invalidCatalog();
  }

  if (!hasExactKeys(plans, DRIVER_PLAN_IDS)) {
    throw invalidCatalog();
  }

  return {
    catalogVersion,
    plans: {
      daily: parseEntry(plans.daily),
      weekly: parseEntry(plans.weekly),
      monthly: parseEntry(plans.monthly),
      quarterly: parseEntry(plans.quarterly),
    },
  };
};

export const loadDriverPlanCatalog = async (
  firestore: Firestore,
): Promise<DriverPlanCatalog> => {
  const snapshot = await firestore
    .collection("platformConfig")
    .doc("driverPlanCatalog")
    .get();

  return driverPlanCatalogFromData(
    snapshot.exists ?
      snapshot.data() :
      undefined,
  );
};

const daysInUtcMonth = (
  year: number,
  month: number,
): number => {
  const value = new Date(0);

  value.setUTCFullYear(
    year,
    month + 1,
    0,
  );

  value.setUTCHours(0, 0, 0, 0);

  return value.getUTCDate();
};

const addUtcMonthsClamped = (
  activatedAt: Timestamp,
  months: number,
): Timestamp => {
  const source = activatedAt.toDate();

  const totalMonths =
    source.getUTCFullYear() * 12 +
    source.getUTCMonth() +
    months;

  const targetYear =
    Math.floor(totalMonths / 12);

  const targetMonth =
    totalMonths - targetYear * 12;

  const targetDay = Math.min(
    source.getUTCDate(),
    daysInUtcMonth(
      targetYear,
      targetMonth,
    ),
  );

  const result = new Date(0);

  result.setUTCFullYear(
    targetYear,
    targetMonth,
    targetDay,
  );

  result.setUTCHours(
    source.getUTCHours(),
    source.getUTCMinutes(),
    source.getUTCSeconds(),
    source.getUTCMilliseconds(),
  );

  return Timestamp.fromDate(result);
};

export const calculateDriverPlanExpiresAt = (
  plan: DriverPlanId,
  activatedAt: Timestamp,
): Timestamp => {
  switch (plan) {
  case "daily":
    return Timestamp.fromMillis(
      activatedAt.toMillis() + DAY_MILLIS,
    );

  case "weekly":
    return Timestamp.fromMillis(
      activatedAt.toMillis() + WEEK_MILLIS,
    );

  case "monthly":
    return addUtcMonthsClamped(
      activatedAt,
      1,
    );

  case "quarterly":
    return addUtcMonthsClamped(
      activatedAt,
      3,
    );
  }
};
