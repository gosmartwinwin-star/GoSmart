/* eslint-disable max-len */
import {createHash} from "node:crypto";
import {Firestore, Timestamp, Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  calculateDriverPlanExpiresAt,
  DRIVER_PLAN_IDS,
  DriverPlanCatalog,
  DriverPlanId,
  loadDriverPlanCatalog,
} from "./driver-plan-catalog.js";
import {
  loadApprovedDriverId,
  loadApprovedDriverIdInTransaction,
} from "./ride-driver-identity.js";

export type DriverPlanPurchaseInput = {planId: DriverPlanId; requestId: string};
export type DriverPlanSettlementInput = {
  purchaseOperationId: string;
  settlementId: string;
  amountMinor: number;
  currency: string;
};
export type DriverPlanPurchaseDependencies = {
  firestore: Firestore;
  now?: () => Timestamp;
};

type PreparedOperation = {
  driverId: string;
  planId: DriverPlanId;
  amountMinor: number;
  currency: string;
  status: "pending" | "settled";
};

const PREPARE_NAME = "prepareDriverPlanPurchase";

const failure = (
  code: "failed-precondition" | "internal" | "invalid-argument" |
    "not-found" | "unauthenticated" | "unavailable",
  reason: string,
): HttpsError => new HttpsError(code,
  "Driver plan operation could not be completed.", {reason});

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value) &&
  Object.getPrototypeOf(value) === Object.prototype;

const exactObject = (value: unknown, keys: readonly string[], reason: string) => {
  if (!isRecord(value)) throw failure("invalid-argument", reason);
  const actual = Object.keys(value);
  if (actual.length !== keys.length || keys.some((key) => !actual.includes(key))) {
    throw failure("invalid-argument", reason);
  }
  return value;
};

const canonicalJson = (value: unknown): string => {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (typeof value === "object" && value !== null) {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record).sort().map((key) =>
      `${JSON.stringify(key)}:${canonicalJson(record[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
};

const sha256 = (value: string): string =>
  createHash("sha256").update(value).digest("hex");

const validateRequestId = (value: unknown): string => {
  if (typeof value !== "string" || value.length < 16 || value.length > 128 ||
      !/^[A-Za-z0-9_-]+$/u.test(value)) {
    throw failure("invalid-argument", "invalid_request_id");
  }
  return value;
};

const validatePlanId = (value: unknown): DriverPlanId => {
  if (!DRIVER_PLAN_IDS.includes(value as DriverPlanId)) {
    throw failure("invalid-argument", "invalid_driver_plan_id");
  }
  return value as DriverPlanId;
};

const validatePurchaseOperationId = (value: unknown): string => {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/u.test(value)) {
    throw failure("invalid-argument", "invalid_purchase_operation_id");
  }
  return value;
};

const validateSettlementId = (value: unknown): string => {
  const hasControl = typeof value === "string" && [...value].some((character) => {
    const code = character.codePointAt(0) ?? 0;
    return code <= 31 || code === 127;
  });
  if (typeof value !== "string" || value.length < 1 || value.length > 256 ||
      value.trim() !== value || hasControl) {
    throw failure("invalid-argument", "invalid_settlement_id");
  }
  return value;
};

const validateAmountMinor = (value: unknown): number => {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw failure("invalid-argument", "invalid_settlement_amount");
  }
  return value;
};

const validateCurrency = (value: unknown): string => {
  if (typeof value !== "string" || !/^[A-Z]{3}$/u.test(value)) {
    throw failure("invalid-argument", "invalid_settlement_currency");
  }
  return value;
};

export const validateDriverPlanPurchasePayload =
  (value: unknown): DriverPlanPurchaseInput => {
    const input = exactObject(value, ["planId", "requestId"],
      "invalid_driver_plan_purchase_payload");
    return {
      planId: validatePlanId(input.planId),
      requestId: validateRequestId(input.requestId),
    };
  };

export const validateDriverPlanSettlementPayload =
  (value: unknown): DriverPlanSettlementInput => {
    const input = exactObject(value,
      ["purchaseOperationId", "settlementId", "amountMinor", "currency"],
      "invalid_driver_plan_settlement_payload");
    return {
      purchaseOperationId: validatePurchaseOperationId(input.purchaseOperationId),
      settlementId: validateSettlementId(input.settlementId),
      amountMinor: validateAmountMinor(input.amountMinor),
      currency: validateCurrency(input.currency),
    };
  };

export const driverPlanPurchaseOperationId = (actorUid: string,
  requestId: string): string => sha256(
  `driver-plan-purchase-operation:${actorUid}:${PREPARE_NAME}:${requestId}`);

export const driverPlanPurchaseRequestDigest = (input: DriverPlanPurchaseInput):
string => sha256(`${PREPARE_NAME}:${canonicalJson(input)}`);

export const driverPlanPaymentSettlementId = (settlementId: string): string =>
  sha256(`driver-plan-payment-settlement:${settlementId}`);

export const driverPlanAccessPassId = (purchaseOperationId: string): string =>
  sha256(`driver-plan-access-pass:${purchaseOperationId}`);

const settlementRequestDigest = (input: DriverPlanSettlementInput): string =>
  sha256(`settleDriverPlanPurchase:${canonicalJson(input)}`);

const replayPreparedOperation = (data: Record<string, unknown>,
  digest: string): Record<string, unknown> => {
  if (data.requestDigest !== digest) {
    throw failure("failed-precondition", "idempotency_payload_mismatch");
  }
  if ((data.status !== "pending" && data.status !== "settled") ||
      !isRecord(data.result)) {
    throw failure("internal", "purchase_operation_invalid");
  }
  return data.result;
};

const loadCatalogForPrepare = async (firestore: Firestore):
Promise<DriverPlanCatalog> => {
  try {
    return await loadDriverPlanCatalog(firestore);
  } catch (_error: unknown) {
    throw failure("failed-precondition", "driver_plan_catalog_unavailable");
  }
};

const parsePreparedOperation = (data: Record<string, unknown>):
PreparedOperation => {
  const {driverId, planId, amountMinor, currency, status, catalogVersion,
    requestDigest, createdAt, updatedAt, result} = data;
  if (typeof driverId !== "string" || driverId.trim().length === 0 ||
      !DRIVER_PLAN_IDS.includes(planId as DriverPlanId) ||
      typeof amountMinor !== "number" || !Number.isSafeInteger(amountMinor) ||
      amountMinor < 0 || typeof currency !== "string" ||
      !/^[A-Z]{3}$/u.test(currency) || typeof catalogVersion !== "string" ||
      catalogVersion.trim().length === 0 || typeof requestDigest !== "string" ||
      !/^[a-f0-9]{64}$/u.test(requestDigest) ||
      !(createdAt instanceof Timestamp) || !(updatedAt instanceof Timestamp) ||
      !isRecord(result) || (status !== "pending" && status !== "settled")) {
    throw failure("internal", "purchase_operation_invalid");
  }
  return {
    driverId,
    planId: planId as DriverPlanId,
    amountMinor,
    currency,
    status,
  };
};

const latestPassQuery = (firestore: Firestore, driverId: string) => firestore
  .collection("driverAccessPasses")
  .where("driverId", "==", driverId)
  .orderBy("purchasedAt", "desc")
  .limit(1);

const activePassExpiry = (data: Record<string, unknown>,
  now: Timestamp): Timestamp | null => {
  if (data.status !== "active") return null;
  const activatedAt = data.activatedAt;
  const expiresAt = data.expiresAt;
  if (!(activatedAt instanceof Timestamp) || !(expiresAt instanceof Timestamp)) {
    throw failure("internal", "driver_access_pass_invalid");
  }
  return activatedAt.toMillis() <= now.toMillis() &&
    now.toMillis() < expiresAt.toMillis() ? expiresAt : null;
};

const replaySettlement = (data: Record<string, unknown>,
  input: DriverPlanSettlementInput, digest: string,
  passExists: boolean): Record<string, unknown> => {
  if (data.purchaseOperationId !== input.purchaseOperationId) {
    throw failure("failed-precondition", "settlement_already_used");
  }
  if (data.requestDigest !== digest) {
    throw failure("failed-precondition", "settlement_payload_mismatch");
  }
  if (data.status !== "settled" || !passExists || !isRecord(data.result)) {
    throw failure("internal", "settlement_record_invalid");
  }
  return data.result;
};

export const prepareDriverPlanPurchase = async (
  dependencies: DriverPlanPurchaseDependencies,
  actorUid: string,
  rawInput: unknown,
): Promise<Record<string, unknown>> => {
  if (typeof actorUid !== "string" || actorUid.trim().length === 0) {
    throw failure("unauthenticated", "authentication_required");
  }

  const input = validateDriverPlanPurchasePayload(rawInput);
  const {firestore} = dependencies;
  const operationId = driverPlanPurchaseOperationId(actorUid, input.requestId);
  const operationRef = firestore.collection("driverPlanPurchaseOperations")
    .doc(operationId);
  const digest = driverPlanPurchaseRequestDigest(input);

  try {
    const driverId = await loadApprovedDriverId(firestore, actorUid);
    const existing = await operationRef.get();
    if (existing.exists) {
      return replayPreparedOperation(existing.data() ?? {}, digest);
    }

    const catalog = await loadCatalogForPrepare(firestore);
    const plan = catalog.plans[input.planId];
    if (!plan.enabled) {
      throw failure("failed-precondition", "driver_plan_disabled");
    }

    const now = dependencies.now?.() ?? Timestamp.now();
    const result = {
      purchaseOperationId: operationId,
      status: "pending" as const,
      catalogVersion: catalog.catalogVersion,
      planId: input.planId,
      amountMinor: plan.amountMinor,
      currency: plan.currency,
    };

    return await firestore.runTransaction(async (transaction) => {
      const [operation, verifiedDriverId] = await Promise.all([
        transaction.get(operationRef),
        loadApprovedDriverIdInTransaction(firestore, actorUid, transaction),
      ]);
      if (verifiedDriverId !== driverId) {
        throw failure("failed-precondition", "driver_identity_changed");
      }
      if (operation.exists) {
        return replayPreparedOperation(operation.data() ?? {}, digest);
      }

      transaction.create(operationRef, {
        actorUid,
        driverId,
        requestDigest: digest,
        catalogVersion: catalog.catalogVersion,
        planId: input.planId,
        amountMinor: plan.amountMinor,
        currency: plan.currency,
        status: "pending",
        result,
        createdAt: now,
        updatedAt: now,
      });
      return result;
    });
  } catch (error: unknown) {
    if (error instanceof HttpsError) throw error;
    throw failure("unavailable", "purchase_prepare_persistence_failed");
  }
};

// Server-only authority. Do not expose this function through an onCall export.
export const settleDriverPlanPurchase = async (
  dependencies: DriverPlanPurchaseDependencies,
  rawInput: unknown,
): Promise<Record<string, unknown>> => {
  const input = validateDriverPlanSettlementPayload(rawInput);
  const {firestore} = dependencies;
  const operationRef = firestore.collection("driverPlanPurchaseOperations")
    .doc(input.purchaseOperationId);
  const settlementDocumentId = driverPlanPaymentSettlementId(input.settlementId);
  const settlementRef = firestore.collection("driverPlanPaymentSettlements")
    .doc(settlementDocumentId);
  const passId = driverPlanAccessPassId(input.purchaseOperationId);
  const passRef = firestore.collection("driverAccessPasses").doc(passId);
  const digest = settlementRequestDigest(input);
  const now = dependencies.now?.() ?? Timestamp.now();

  try {
    return await firestore.runTransaction(async (transaction: Transaction) => {
      const [operation, settlement, deterministicPass] = await Promise.all([
        transaction.get(operationRef),
        transaction.get(settlementRef),
        transaction.get(passRef),
      ]);

      if (!operation.exists) {
        throw failure("not-found", "purchase_operation_not_found");
      }

      const prepared = parsePreparedOperation(operation.data() ?? {});
      if (settlement.exists) {
        const settlementData = settlement.data() ?? {};
        if (typeof settlementData.purchaseOperationId !== "string") {
          throw failure("internal", "settlement_record_invalid");
        }
        if (settlementData.purchaseOperationId !== input.purchaseOperationId) {
          throw failure("failed-precondition", "settlement_already_used");
        }
        if (prepared.status !== "settled") {
          throw failure("internal", "settlement_record_invalid");
        }
        return replaySettlement(settlementData, input, digest,
          deterministicPass.exists);
      }
      if (prepared.status === "settled") {
        if (!deterministicPass.exists) {
          throw failure("internal", "purchase_settlement_inconsistent");
        }
        throw failure("failed-precondition", "purchase_already_settled");
      }
      if (deterministicPass.exists) {
        throw failure("internal", "purchase_settlement_inconsistent");
      }
      if (input.amountMinor !== prepared.amountMinor) {
        throw failure("failed-precondition", "settlement_amount_mismatch");
      }
      if (input.currency !== prepared.currency) {
        throw failure("failed-precondition", "settlement_currency_mismatch");
      }

      const passes = await transaction.get(latestPassQuery(
        firestore, prepared.driverId));
      let durationBase = now;
      if (!passes.empty) {
        const currentExpiry = activePassExpiry(passes.docs[0].data(), now);
        if (currentExpiry !== null) durationBase = currentExpiry;
      }

      const expiresAt = calculateDriverPlanExpiresAt(
        prepared.planId, durationBase);
      const result = {
        purchaseOperationId: input.purchaseOperationId,
        paymentSettlementId: settlementDocumentId,
        passId,
        status: "settled" as const,
        planId: prepared.planId,
        activatedAtMillis: now.toMillis(),
        expiresAtMillis: expiresAt.toMillis(),
      };

      transaction.create(passRef, {
        driverId: prepared.driverId,
        status: "active",
        plan: prepared.planId,
        purchasedAt: now,
        activatedAt: now,
        expiresAt,
      });
      transaction.create(settlementRef, {
        purchaseOperationId: input.purchaseOperationId,
        externalSettlementId: input.settlementId,
        requestDigest: digest,
        amountMinor: input.amountMinor,
        currency: input.currency,
        status: "settled",
        settledAt: now,
        passId,
        result,
      });
      transaction.update(operationRef, {
        status: "settled",
        paymentSettlementId: settlementDocumentId,
        passId,
        settledAt: now,
        updatedAt: now,
      });
      return result;
    });
  } catch (error: unknown) {
    if (error instanceof HttpsError) throw error;
    throw failure("unavailable", "purchase_settlement_persistence_failed");
  }
};
