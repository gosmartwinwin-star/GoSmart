/* eslint-disable max-len */
import {Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {loadApprovedDriverId} from "./ride-driver-identity.js";

type Data = Record<string, unknown>;

export type DriverPlanPaymentOutcome =
  | "pending"
  | "payment_failed"
  | "payment_review"
  | "settled";

export type DriverPlanPaymentStatusReadInput = {
  purchaseOperationId: string;
};

export type DriverPlanPaymentStatusReadResult = {
  purchaseOperationId: string;
  paymentOutcome: DriverPlanPaymentOutcome;
};

export type DriverPlanPaymentStatusReadDependencies = {
  firestore: Firestore;
  loadApprovedDriverId?: (
    firestore: Firestore,
    actorUid: string,
  ) => Promise<string>;
};

const failure = (
  code:
    | "invalid-argument"
    | "not-found"
    | "unavailable"
    | "internal",
  reason: string,
): HttpsError => new HttpsError(
  code,
  "Driver plan payment status request failed.",
  {reason},
);

const isRecord = (
  value: unknown,
): value is Data =>
  typeof value === "object" &&
  value !== null &&
  !Array.isArray(value);

const validatePurchaseOperationId = (
  value: unknown,
): string => {
  if (
    typeof value !== "string" ||
    !/^[a-f0-9]{64}$/u.test(value)
  ) {
    throw failure(
      "invalid-argument",
      "invalid_purchase_operation_id",
    );
  }

  return value;
};

export const validateDriverPlanPaymentStatusReadPayload = (
  value: unknown,
): DriverPlanPaymentStatusReadInput => {
  if (!isRecord(value)) {
    throw failure(
      "invalid-argument",
      "invalid_driver_plan_payment_status_read_payload",
    );
  }

  const keys = Object.keys(value);

  if (
    keys.length !== 1 ||
    keys[0] !== "purchaseOperationId"
  ) {
    throw failure(
      "invalid-argument",
      "invalid_driver_plan_payment_status_read_payload",
    );
  }

  return {
    purchaseOperationId:
      validatePurchaseOperationId(
        value.purchaseOperationId,
      ),
  };
};

const loadOperationForRead = async (
  dependencies: DriverPlanPaymentStatusReadDependencies,
  purchaseOperationId: string,
): Promise<Data> => {
  try {
    const snapshot =
      await dependencies.firestore
        .collection("driverPlanPurchaseOperations")
        .doc(purchaseOperationId)
        .get();

    if (!snapshot.exists) {
      throw failure(
        "not-found",
        "purchase_operation_not_found",
      );
    }

    const data = snapshot.data();

    if (!isRecord(data)) {
      throw failure(
        "internal",
        "purchase_operation_invalid",
      );
    }

    return data;
  } catch (error: unknown) {
    if (error instanceof HttpsError) {
      throw error;
    }

    throw failure(
      "unavailable",
      "purchase_operation_lookup_failed",
    );
  }
};

const resolvePaymentOutcome = (
  operation: Data,
): DriverPlanPaymentOutcome => {
  if (operation.status === "settled") {
    return "settled";
  }

  if (operation.status !== "pending") {
    throw failure(
      "internal",
      "purchase_operation_invalid",
    );
  }

  const paymentOutcome =
    operation.paymentOutcome;

  if (
    paymentOutcome === undefined ||
    paymentOutcome === "pending"
  ) {
    return "pending";
  }

  if (
    paymentOutcome === "payment_failed" ||
    paymentOutcome === "payment_review"
  ) {
    return paymentOutcome;
  }

  throw failure(
    "internal",
    "purchase_operation_invalid",
  );
};

export const getDriverPlanPaymentStatusForActor = async (
  dependencies: DriverPlanPaymentStatusReadDependencies,
  actorUid: string,
  payload: unknown,
): Promise<DriverPlanPaymentStatusReadResult> => {
  const input =
    validateDriverPlanPaymentStatusReadPayload(
      payload,
    );

  const approvedDriverLoader =
    dependencies.loadApprovedDriverId ??
    loadApprovedDriverId;

  const approvedDriverId =
    await approvedDriverLoader(
      dependencies.firestore,
      actorUid,
    );

  const operation =
    await loadOperationForRead(
      dependencies,
      input.purchaseOperationId,
    );

  if (
    typeof operation.driverId !== "string" ||
    operation.driverId.trim().length === 0
  ) {
    throw failure(
      "internal",
      "purchase_operation_invalid",
    );
  }

  // Do not disclose another driver's purchase operation.
  if (operation.driverId !== approvedDriverId) {
    throw failure(
      "not-found",
      "purchase_operation_not_found",
    );
  }

  return {
    purchaseOperationId:
      input.purchaseOperationId,
    paymentOutcome:
      resolvePaymentOutcome(operation),
  };
};
/* eslint-enable max-len */
