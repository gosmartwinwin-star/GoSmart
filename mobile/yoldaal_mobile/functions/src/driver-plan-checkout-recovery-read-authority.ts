/* eslint-disable max-len */

import {
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  getDriverPlanPaymentStatusForActor,
  DriverPlanPaymentStatusReadResult,
} from "./driver-plan-payment-status-read-authority.js";
import {
  loadApprovedDriverId,
} from "./ride-driver-identity.js";

type Data = Record<string, unknown>;

type LatestCheckoutPointer = {
  purchaseOperationId: string;
  updatedAt: Timestamp;
};

export type DriverPlanCheckoutRecoveryReadDependencies = {
  firestore: Firestore;
  loadApprovedDriverId?: (
    firestore: Firestore,
    actorUid: string,
  ) => Promise<string>;
};

export type DriverPlanCheckoutRecoveryReadResult = {
  paymentStatus:
    DriverPlanPaymentStatusReadResult | null;
};

const failure = (
  code:
    | "invalid-argument"
    | "not-found"
    | "unavailable"
    | "internal",
  reason: string,
): HttpsError =>
  new HttpsError(
    code,
    "Driver plan checkout recovery request failed.",
    {reason},
  );

const isRecord = (
  value: unknown,
): value is Data =>
  typeof value === "object" &&
  value !== null &&
  !Array.isArray(value);

export const validateDriverPlanCheckoutRecoveryPayload = (
  value: unknown,
): Record<string, never> => {
  if (
    !isRecord(value) ||
    Object.keys(value).length !== 0
  ) {
    throw failure(
      "invalid-argument",
      "invalid_driver_plan_checkout_recovery_payload",
    );
  }

  return {};
};

const validatePurchaseOperationId = (
  value: unknown,
): string => {
  if (
    typeof value !== "string" ||
    !/^[a-f0-9]{64}$/u.test(value)
  ) {
    throw failure(
      "internal",
      "driver_plan_checkout_recovery_pointer_invalid",
    );
  }

  return value;
};

const parseLatestCheckoutPointer = (
  value: unknown,
): LatestCheckoutPointer => {
  if (!isRecord(value)) {
    throw failure(
      "internal",
      "driver_plan_checkout_recovery_pointer_invalid",
    );
  }

  const keys =
    Object.keys(value).sort();

  if (
    keys.length !== 2 ||
    keys[0] !== "purchaseOperationId" ||
    keys[1] !== "updatedAt"
  ) {
    throw failure(
      "internal",
      "driver_plan_checkout_recovery_pointer_invalid",
    );
  }

  const purchaseOperationId =
    validatePurchaseOperationId(
      value.purchaseOperationId,
    );

  if (!(value.updatedAt instanceof Timestamp)) {
    throw failure(
      "internal",
      "driver_plan_checkout_recovery_pointer_invalid",
    );
  }

  return {
    purchaseOperationId,
    updatedAt: value.updatedAt,
  };
};

const loadLatestCheckoutPointer = async (
  firestore: Firestore,
  approvedDriverId: string,
): Promise<LatestCheckoutPointer | null> => {
  try {
    const snapshot =
      await firestore
        .collection(
          "driverLatestPlanCheckoutOperations",
        )
        .doc(approvedDriverId)
        .get();

    if (!snapshot.exists) {
      return null;
    }

    return parseLatestCheckoutPointer(
      snapshot.data(),
    );
  } catch (error: unknown) {
    if (error instanceof HttpsError) {
      throw error;
    }

    throw failure(
      "unavailable",
      "driver_plan_checkout_recovery_pointer_lookup_failed",
    );
  }
};

export const getMyLatestDriverPlanPaymentStatusForActor =
  async (
    dependencies:
      DriverPlanCheckoutRecoveryReadDependencies,
    actorUid: string,
    payload: unknown,
  ): Promise<DriverPlanCheckoutRecoveryReadResult> => {
    validateDriverPlanCheckoutRecoveryPayload(
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

    const pointer =
      await loadLatestCheckoutPointer(
        dependencies.firestore,
        approvedDriverId,
      );

    if (pointer === null) {
      return {
        paymentStatus: null,
      };
    }

    const paymentStatus =
      await getDriverPlanPaymentStatusForActor(
        {
          firestore:
            dependencies.firestore,
          loadApprovedDriverId:
            async () => approvedDriverId,
        },
        actorUid,
        {
          purchaseOperationId:
            pointer.purchaseOperationId,
        },
      );

    return {
      paymentStatus,
    };
  };

/* eslint-enable max-len */
