/* eslint-disable max-len, @typescript-eslint/no-explicit-any, require-jsdoc, brace-style, block-spacing */
import assert from "node:assert/strict";
import test from "node:test";
import {Firestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  driverPlanAccessPassId,
  driverPlanPaymentSettlementId,
  driverPlanPurchaseOperationId,
  prepareDriverPlanPurchase,
  settleDriverPlanPurchase,
  validateDriverPlanPurchasePayload,
  validateDriverPlanSettlementPayload,
} from "./driver-plan-purchase-authority.js";

type Data = Record<string, unknown>;
const DAY = 24 * 60 * 60 * 1000;

const catalog = () => ({
  catalogVersion: "catalog-v1",
  plans: {
    daily: {enabled: true, amountMinor: 100, currency: "TRY"},
    weekly: {enabled: true, amountMinor: 200, currency: "TRY"},
    monthly: {enabled: true, amountMinor: 300, currency: "TRY"},
    quarterly: {enabled: true, amountMinor: 400, currency: "TRY"},
  },
});

class Snap {
  constructor(readonly id: string, private readonly value?: Data) {}
  get exists() { return this.value !== undefined; }
  data() { return this.value; }
  get(field: string) { return this.value?.[field]; }
}
class QuerySnap {
  constructor(readonly docs: Snap[]) {}
  get empty() { return this.docs.length === 0; }
  get size() { return this.docs.length; }
}
class Ref {
  constructor(readonly fs: FakeFirestore, readonly path: string) {}
  get id() { return this.path.substring(this.path.lastIndexOf("/") + 1); }
  get() { return Promise.resolve(this.fs.snap(this.path)); }
}
type Filter = {field: string; value: unknown};
class Query {
  constructor(readonly fs: FakeFirestore, readonly name: string,
    readonly filters: Filter[] = [], readonly order: string | null = null,
    readonly desc = false, readonly max: number | null = null) {}
  where(field: string, op: string, value: unknown) {
    assert.equal(op, "==");
    return new Query(this.fs, this.name, [...this.filters, {field, value}],
      this.order, this.desc, this.max);
  }
  orderBy(field: string, direction?: string) {
    return new Query(this.fs, this.name, this.filters, field,
      direction === "desc", this.max);
  }
  limit(max: number) {
    return new Query(this.fs, this.name, this.filters, this.order, this.desc, max);
  }
  get() { return Promise.resolve(this.fs.query(this)); }
}
class Collection {
  constructor(readonly fs: FakeFirestore, readonly name: string) {}
  doc(id: string) { return new Ref(this.fs, `${this.name}/${id}`); }
  where(field: string, op: string, value: unknown) {
    return new Query(this.fs, this.name).where(field, op, value);
  }
}
type Mutation = {kind: "create" | "update"; path: string; data: Data};
class Tx {
  private readonly mutations: Mutation[] = [];
  constructor(readonly fs: FakeFirestore) {}
  get(target: Ref | Query): Promise<any> {
    return Promise.resolve(target instanceof Ref ?
      this.fs.snap(target.path) : this.fs.query(target));
  }
  create(ref: Ref, data: Data) {
    this.mutations.push({kind: "create", path: ref.path, data});
    return this;
  }
  update(ref: Ref, data: Data) {
    this.mutations.push({kind: "update", path: ref.path, data});
    return this;
  }
  commit() {
    for (const mutation of this.mutations) {
      const current = this.fs.get(mutation.path);
      if (mutation.kind === "create") {
        if (current !== undefined) throw new Error(`exists:${mutation.path}`);
        this.fs.set(mutation.path, mutation.data);
      } else {
        if (current === undefined) throw new Error(`missing:${mutation.path}`);
        this.fs.set(mutation.path, {...current, ...mutation.data});
      }
    }
  }
}
class FakeFirestore {
  private readonly docs = new Map<string, Data>();
  collection(name: string) { return new Collection(this, name); }
  async runTransaction<T>(callback: (transaction: any) => Promise<T>): Promise<T> {
    const tx = new Tx(this);
    const result = await callback(tx);
    tx.commit();
    return result;
  }
  set(path: string, data: Data) { this.docs.set(path, data); }
  get(path: string) { return this.docs.get(path); }
  delete(path: string) { this.docs.delete(path); }
  count(name: string) {
    const prefix = `${name}/`;
    return [...this.docs.keys()].filter((path) =>
      path.startsWith(prefix) && !path.slice(prefix.length).includes("/")).length;
  }
  snap(path: string) { return new Snap(path.substring(path.lastIndexOf("/") + 1), this.docs.get(path)); }
  query(query: Query) {
    const prefix = `${query.name}/`;
    let values = [...this.docs.entries()]
      .filter(([path]) => path.startsWith(prefix) &&
        !path.slice(prefix.length).includes("/"))
      .map(([path, data]) => ({id: path.slice(prefix.length), data}));
    for (const filter of query.filters) {
      values = values.filter((item) => item.data[filter.field] === filter.value);
    }
    if (query.order !== null) {
      values.sort((a, b) => {
        const difference = comparable(a.data[query.order!]) -
          comparable(b.data[query.order!]);
        return query.desc ? -difference : difference;
      });
    }
    if (query.max !== null) values = values.slice(0, query.max);
    return new QuerySnap(values.map((item) => new Snap(item.id, item.data)));
  }
}
const comparable = (value: unknown) =>
  value instanceof Timestamp ? value.toMillis() :
    typeof value === "number" ? value : 0;

const setup = (iso = "2026-01-15T10:00:00.000Z") => {
  const fake = new FakeFirestore();
  let now = Timestamp.fromDate(new Date(iso));
  fake.set("driverProfiles/driver-1", {authUserId: "uid-1", status: "approved"});
  fake.set("platformConfig/driverPlanCatalog", catalog());
  return {
    fake,
    dependencies: {firestore: fake as unknown as Firestore, now: () => now},
    setNow: (value: string) => {
      now = Timestamp.fromDate(new Date(value));
    },
  };
};

type Plan = "daily" | "weekly" | "monthly" | "quarterly";
const prepare = (context: ReturnType<typeof setup>, planId: Plan = "daily",
  requestId = "request_1234567890") =>
  prepareDriverPlanPurchase(context.dependencies, "uid-1", {planId, requestId});
const settle = (context: ReturnType<typeof setup>, purchaseOperationId: string,
  overrides: Partial<{settlementId: string; amountMinor: number; currency: string}> = {}) =>
  settleDriverPlanPurchase(context.dependencies, {
    purchaseOperationId,
    settlementId: overrides.settlementId ?? "settlement-1",
    amountMinor: overrides.amountMinor ?? 100,
    currency: overrides.currency ?? "TRY",
  });
const reasonIs = (expected: string) => (error: unknown): boolean => {
  if (!(error instanceof HttpsError)) return false;
  return (error.details as Record<string, unknown> | undefined)?.reason === expected;
};

test("purchase payload requires exact keys", () => {
  assert.throws(() => validateDriverPlanPurchasePayload({
    planId: "daily", requestId: "request_1234567890", amountMinor: 1,
  }), reasonIs("invalid_driver_plan_purchase_payload"));
});

test("requestId uses canonical bounded format", () => {
  for (const requestId of ["short", "contains space 123456", "x".repeat(129)]) {
    assert.throws(() => validateDriverPlanPurchasePayload({planId: "daily", requestId}),
      reasonIs("invalid_request_id"));
  }
});

test("only canonical plan ids are accepted", () => {
  assert.throws(() => validateDriverPlanPurchasePayload({
    planId: "yearly", requestId: "request_1234567890",
  }), reasonIs("invalid_driver_plan_id"));
});

test("settlement payload requires exact server fields", () => {
  const purchaseOperationId = driverPlanPurchaseOperationId("uid-1", "request_1234567890");
  assert.throws(() => validateDriverPlanSettlementPayload({
    purchaseOperationId, settlementId: "settlement-1", amountMinor: 100,
    currency: "TRY", clientConfirmed: true,
  }), reasonIs("invalid_driver_plan_settlement_payload"));
});

test("missing and malformed catalog fail closed", async () => {
  const missing = setup();
  missing.fake.delete("platformConfig/driverPlanCatalog");
  await assert.rejects(() => prepare(missing),
    reasonIs("driver_plan_catalog_unavailable"));

  const malformed = setup();
  malformed.fake.set("platformConfig/driverPlanCatalog", {catalogVersion: "broken"});
  await assert.rejects(() => prepare(malformed),
    reasonIs("driver_plan_catalog_unavailable"));
});

test("disabled plan is rejected", async () => {
  const context = setup();
  const value = catalog();
  value.plans.daily.enabled = false;
  context.fake.set("platformConfig/driverPlanCatalog", value);
  await assert.rejects(() => prepare(context), reasonIs("driver_plan_disabled"));
});

test("prepare snapshots server commercial values and creates no pass", async () => {
  const context = setup();
  const value = catalog();
  value.catalogVersion = "catalog-v9";
  value.plans.daily.amountMinor = 987;
  value.plans.daily.currency = "EUR";
  context.fake.set("platformConfig/driverPlanCatalog", value);
  const result = await prepare(context);
  assert.equal(result.catalogVersion, "catalog-v9");
  assert.equal(result.amountMinor, 987);
  assert.equal(result.currency, "EUR");
  assert.equal(context.fake.count("driverAccessPasses"), 0);
});

test("purchase operation id is deterministic", () => {
  const first = driverPlanPurchaseOperationId("uid-1", "request_1234567890");
  assert.equal(first, driverPlanPurchaseOperationId("uid-1", "request_1234567890"));
  assert.notEqual(first, driverPlanPurchaseOperationId("uid-2", "request_1234567890"));
});

test("same request replays same result and payload mismatch is rejected", async () => {
  const context = setup();
  const first = await prepare(context, "daily", "same_request_123456");
  assert.deepEqual(await prepare(context, "daily", "same_request_123456"), first);
  assert.equal(context.fake.count("driverPlanPurchaseOperations"), 1);
  await assert.rejects(() => prepare(context, "weekly", "same_request_123456"),
    reasonIs("idempotency_payload_mismatch"));
});

test("settlement amount and currency must match prepare snapshot", async () => {
  const context = setup();
  const prepared = await prepare(context);
  const id = prepared.purchaseOperationId as string;
  await assert.rejects(() => settle(context, id, {amountMinor: 101}),
    reasonIs("settlement_amount_mismatch"));
  await assert.rejects(() => settle(context, id, {currency: "EUR"}),
    reasonIs("settlement_currency_mismatch"));
});

test("unknown and malformed operations are rejected", async () => {
  const context = setup();
  const unknown = driverPlanPurchaseOperationId("uid-1", "unknown_request_12345");
  await assert.rejects(() => settle(context, unknown),
    reasonIs("purchase_operation_not_found"));

  const malformed = driverPlanPurchaseOperationId("uid-1", "broken_request_12345");
  context.fake.set(`driverPlanPurchaseOperations/${malformed}`,
    {status: "pending", driverId: 42});
  await assert.rejects(() => settle(context, malformed),
    reasonIs("purchase_operation_invalid"));
});

test("settlement and pass ids are deterministic", () => {
  assert.equal(driverPlanPaymentSettlementId("provider-settlement-1"),
    driverPlanPaymentSettlementId("provider-settlement-1"));
  assert.equal(driverPlanAccessPassId("a".repeat(64)),
    driverPlanAccessPassId("a".repeat(64)));
});

test("settlement replay creates exactly one pass", async () => {
  const context = setup();
  const prepared = await prepare(context);
  const id = prepared.purchaseOperationId as string;
  const first = await settle(context, id);
  assert.deepEqual(await settle(context, id), first);
  assert.equal(context.fake.count("driverAccessPasses"), 1);
  assert.equal(context.fake.count("driverPlanPaymentSettlements"), 1);
});

test("settlement replay fails closed when operation state is inconsistent", async () => {
  const context = setup();
  const prepared = await prepare(context);
  const id = prepared.purchaseOperationId as string;

  await settle(context, id);

  const operationPath = `driverPlanPurchaseOperations/${id}`;
  const operation = context.fake.get(operationPath)!;
  context.fake.set(operationPath, {...operation, status: "pending"});

  await assert.rejects(() => settle(context, id),
    reasonIs("settlement_record_invalid"));
  assert.equal(context.fake.count("driverAccessPasses"), 1);
  assert.equal(context.fake.count("driverPlanPaymentSettlements"), 1);
});

test("settled purchase rejects a different settlement identity", async () => {
  const context = setup();
  const prepared = await prepare(context);
  const id = prepared.purchaseOperationId as string;

  await settle(context, id, {settlementId: "settlement-first"});

  await assert.rejects(() => settle(context, id,
    {settlementId: "settlement-second"}),
  reasonIs("purchase_already_settled"));

  assert.equal(context.fake.count("driverAccessPasses"), 1);
  assert.equal(context.fake.count("driverPlanPaymentSettlements"), 1);
});

test("same settlement identity cannot settle another purchase", async () => {
  const context = setup();
  const first = await prepare(context, "daily", "first_request_123456");
  const second = await prepare(context, "daily", "second_request_12345");
  await settle(context, first.purchaseOperationId as string,
    {settlementId: "shared-settlement"});
  await assert.rejects(() => settle(context, second.purchaseOperationId as string,
    {settlementId: "shared-settlement"}), reasonIs("settlement_already_used"));
});

test("expired pass does not extend duration base", async () => {
  const context = setup();
  const now = context.dependencies.now();
  context.fake.set("driverAccessPasses/old-pass", {
    driverId: "driver-1", status: "active", plan: "daily",
    purchasedAt: Timestamp.fromMillis(now.toMillis() - 2 * DAY),
    activatedAt: Timestamp.fromMillis(now.toMillis() - 2 * DAY),
    expiresAt: Timestamp.fromMillis(now.toMillis() - DAY),
  });
  const prepared = await prepare(context);
  const result = await settle(context, prepared.purchaseOperationId as string);
  assert.equal(result.expiresAtMillis, now.toMillis() + DAY);
});

test("active renewal is immediate and preserves remaining time", async () => {
  const context = setup();
  const now = context.dependencies.now();
  const currentExpiry = Timestamp.fromMillis(now.toMillis() + 12 * 60 * 60 * 1000);
  context.fake.set("driverAccessPasses/current-pass", {
    driverId: "driver-1", status: "active", plan: "daily",
    purchasedAt: Timestamp.fromMillis(now.toMillis() - DAY),
    activatedAt: Timestamp.fromMillis(now.toMillis() - DAY),
    expiresAt: currentExpiry,
  });
  const prepared = await prepare(context);
  const result = await settle(context, prepared.purchaseOperationId as string);
  const pass = context.fake.get(`driverAccessPasses/${result.passId as string}`)!;
  assert.equal((pass.activatedAt as Timestamp).toMillis(), now.toMillis());
  assert.equal(result.expiresAtMillis, currentExpiry.toMillis() + DAY);
});

test("exact expiry boundary is not active", async () => {
  const context = setup();
  const now = context.dependencies.now();
  context.fake.set("driverAccessPasses/current-pass", {
    driverId: "driver-1", status: "active", plan: "daily",
    purchasedAt: Timestamp.fromMillis(now.toMillis() - DAY),
    activatedAt: Timestamp.fromMillis(now.toMillis() - DAY), expiresAt: now,
  });
  const prepared = await prepare(context);
  const result = await settle(context, prepared.purchaseOperationId as string);
  assert.equal(result.expiresAtMillis, now.toMillis() + DAY);
});

test("monthly and quarterly settlements preserve calendar clamp", async () => {
  const monthly = setup("2025-01-31T10:15:30.123Z");
  const monthlyPrepared = await prepare(monthly, "monthly", "monthly_request_1234");
  const monthlyResult = await settle(monthly,
    monthlyPrepared.purchaseOperationId as string, {amountMinor: 300});
  assert.equal(new Date(monthlyResult.expiresAtMillis as number).toISOString(),
    "2025-02-28T10:15:30.123Z");

  const quarterly = setup("2025-11-30T10:15:30.123Z");
  const quarterlyPrepared = await prepare(quarterly, "quarterly", "quarter_request_1234");
  const quarterlyResult = await settle(quarterly,
    quarterlyPrepared.purchaseOperationId as string, {amountMinor: 400});
  assert.equal(new Date(quarterlyResult.expiresAtMillis as number).toISOString(),
    "2026-02-28T10:15:30.123Z");
});

test("consecutive renewals stack from latest active expiry", async () => {
  const context = setup();
  const first = await prepare(context, "monthly", "renewal_first_12345");
  const firstResult = await settle(context, first.purchaseOperationId as string,
    {settlementId: "renewal-settlement-1", amountMinor: 300});
  context.setNow("2026-01-16T10:00:00.000Z");
  const second = await prepare(context, "monthly", "renewal_second_1234");
  const secondResult = await settle(context, second.purchaseOperationId as string,
    {settlementId: "renewal-settlement-2", amountMinor: 300});
  assert.equal(new Date(firstResult.expiresAtMillis as number).toISOString(),
    "2026-02-15T10:00:00.000Z");
  assert.equal(new Date(secondResult.expiresAtMillis as number).toISOString(),
    "2026-03-15T10:00:00.000Z");
});

test("prepare cannot fabricate settlement or entitlement", async () => {
  const context = setup();
  const result = await prepare(context);
  assert.equal(result.status, "pending");
  assert.equal(context.fake.count("driverAccessPasses"), 0);
  assert.equal(context.fake.count("driverPlanPaymentSettlements"), 0);
});

test("controlled errors sanitize internal catalog failure", async () => {
  const context = setup();
  context.fake.set("platformConfig/driverPlanCatalog", {});
  await assert.rejects(async () => {
    try {
      await prepare(context);
    } catch (error: unknown) {
      if (!(error instanceof HttpsError)) throw error;
      assert.equal(error.message, "Driver plan operation could not be completed.");
      assert.deepEqual(error.details, {reason: "driver_plan_catalog_unavailable"});
      throw error;
    }
  }, reasonIs("driver_plan_catalog_unavailable"));
});
