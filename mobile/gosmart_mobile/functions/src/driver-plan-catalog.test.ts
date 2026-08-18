import assert from "node:assert/strict";
import test from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {
  calculateDriverPlanExpiresAt,
  driverPlanCatalogFromData,
  DriverPlanId,
} from "./driver-plan-catalog.js";

const validCatalog = () => ({
  catalogVersion: "test-v1",
  plans: {
    daily: {
      enabled: true,
      amountMinor: 1,
      currency: "TRY",
    },
    weekly: {
      enabled: true,
      amountMinor: 2,
      currency: "TRY",
    },
    monthly: {
      enabled: true,
      amountMinor: 3,
      currency: "TRY",
    },
    quarterly: {
      enabled: false,
      amountMinor: 4,
      currency: "TRY",
    },
  },
});

const timestamp = (
  value: string,
): Timestamp =>
  Timestamp.fromDate(new Date(value));

const iso = (
  value: Timestamp,
): string =>
  value.toDate().toISOString();

test("all canonical plans are accepted", () => {
  const input = validCatalog();

  assert.deepEqual(
    driverPlanCatalogFromData(input),
    input,
  );
});

test("missing catalog fails closed", () => {
  assert.throws(
    () => driverPlanCatalogFromData(undefined),
    TypeError,
  );
});

test("malformed catalog fails closed", () => {
  for (const value of [
    null,
    [],
    {},
    "catalog",
  ]) {
    assert.throws(
      () => driverPlanCatalogFromData(value),
      TypeError,
    );
  }
});

test("catalog version must be non-empty", () => {
  for (const value of ["", "   "]) {
    const input = validCatalog();
    input.catalogVersion = value;

    assert.throws(
      () => driverPlanCatalogFromData(input),
      TypeError,
    );
  }
});

test("missing canonical plan is rejected", () => {
  const input = validCatalog();

  delete (
    input.plans as Partial<
      Record<DriverPlanId, unknown>
    >
  ).daily;

  assert.throws(
    () => driverPlanCatalogFromData(input),
    TypeError,
  );
});

test("unknown plan id is rejected", () => {
  const input = validCatalog();

  (
    input.plans as Record<string, unknown>
  ).yearly = {
    enabled: true,
    amountMinor: 5,
    currency: "TRY",
  };

  assert.throws(
    () => driverPlanCatalogFromData(input),
    TypeError,
  );
});

test("unknown catalog field is rejected", () => {
  const input = validCatalog();

  (
    input as Record<string, unknown>
  ).campaign = {};

  assert.throws(
    () => driverPlanCatalogFromData(input),
    TypeError,
  );
});

test("unknown plan entry field is rejected", () => {
  const input = validCatalog();

  (
    input.plans.daily as Record<
      string,
      unknown
    >
  ).label = "Daily";

  assert.throws(
    () => driverPlanCatalogFromData(input),
    TypeError,
  );
});

test("amountMinor must be a non-negative safe integer", () => {
  for (const value of [
    -1,
    1.5,
    Number.MAX_SAFE_INTEGER + 1,
  ]) {
    const input = validCatalog();
    input.plans.daily.amountMinor = value;

    assert.throws(
      () => driverPlanCatalogFromData(input),
      TypeError,
    );
  }
});

test("zero amountMinor is valid catalog data", () => {
  const input = validCatalog();
  input.plans.daily.amountMinor = 0;

  assert.equal(
    driverPlanCatalogFromData(input)
      .plans.daily.amountMinor,
    0,
  );
});

test("currency must be uppercase three-letter ASCII", () => {
  for (const value of [
    "try",
    "TrY",
    "TR",
    "TRY1",
  ]) {
    const input = validCatalog();
    input.plans.daily.currency = value;

    assert.throws(
      () => driverPlanCatalogFromData(input),
      TypeError,
    );
  }
});

test("enabled must be boolean", () => {
  const input = validCatalog();

  (
    input.plans.daily as Record<
      string,
      unknown
    >
  ).enabled = "true";

  assert.throws(
    () => driverPlanCatalogFromData(input),
    TypeError,
  );
});

test("daily is exactly 24 hours from activation", () => {
  const activatedAt =
    timestamp("2026-01-31T10:15:30.123Z");

  assert.equal(
    iso(
      calculateDriverPlanExpiresAt(
        "daily",
        activatedAt,
      ),
    ),
    "2026-02-01T10:15:30.123Z",
  );
});

test("weekly is exactly seven days from activation", () => {
  const activatedAt =
    timestamp("2026-01-31T10:15:30.123Z");

  assert.equal(
    iso(
      calculateDriverPlanExpiresAt(
        "weekly",
        activatedAt,
      ),
    ),
    "2026-02-07T10:15:30.123Z",
  );
});

test("monthly keeps the calendar day when possible", () => {
  const activatedAt =
    timestamp("2026-01-15T10:15:30.123Z");

  assert.equal(
    iso(
      calculateDriverPlanExpiresAt(
        "monthly",
        activatedAt,
      ),
    ),
    "2026-02-15T10:15:30.123Z",
  );
});

test("monthly clamps January 31 to February end", () => {
  const activatedAt =
    timestamp("2025-01-31T10:15:30.123Z");

  assert.equal(
    iso(
      calculateDriverPlanExpiresAt(
        "monthly",
        activatedAt,
      ),
    ),
    "2025-02-28T10:15:30.123Z",
  );
});

test("monthly respects leap-year February", () => {
  const activatedAt =
    timestamp("2024-01-31T10:15:30.123Z");

  assert.equal(
    iso(
      calculateDriverPlanExpiresAt(
        "monthly",
        activatedAt,
      ),
    ),
    "2024-02-29T10:15:30.123Z",
  );
});

test("quarterly clamps across year boundary", () => {
  const activatedAt =
    timestamp("2025-11-30T10:15:30.123Z");

  assert.equal(
    iso(
      calculateDriverPlanExpiresAt(
        "quarterly",
        activatedAt,
      ),
    ),
    "2026-02-28T10:15:30.123Z",
  );
});

test("calendar plans preserve UTC time components", () => {
  const activatedAt =
    timestamp("2025-01-31T23:59:58.123Z");

  assert.equal(
    iso(
      calculateDriverPlanExpiresAt(
        "monthly",
        activatedAt,
      ),
    ),
    "2025-02-28T23:59:58.123Z",
  );
});
