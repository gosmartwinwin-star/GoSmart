/* eslint-disable max-len, require-jsdoc, valid-jsdoc */

import {
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  formatDriverPlanAmountDecimal,
} from "./driver-plan-checkout-authority.js";
import {
  DriverPlanPaymentProviderException,
  DriverPlanPaymentRetrieveResult,
  DriverPlanPaymentRetriever,
} from "./driver-plan-payment-provider.js";
import {
  settleDriverPlanPurchase,
} from "./driver-plan-purchase-authority.js";

type Data = Record<string, unknown>;

type CallbackErrorCode =
  | "invalid-argument"
  | "not-found"
  | "failed-precondition"
  | "unavailable"
  | "internal";

export interface DriverPlanCheckoutCallbackDependencies {
  firestore: Firestore;
  retriever: DriverPlanPaymentRetriever;
  now?: () => Timestamp;
}

export interface DriverPlanCheckoutCallbackInput {
  token: string;
}

export type DriverPlanCheckoutCallbackResult =
  | {
    status: "settled";
    purchaseOperationId: string;
    paymentId: string;
    paymentSettlementId: string;
    passId: string;
  }
  | {
    status: "payment_failed" | "payment_review";
    purchaseOperationId: string;
    paymentId: string;
  };

interface CallbackOperation {
  purchaseOperationId: string;
  amountMinor: number;
  currency: string;
  status: "pending" | "settled";
  conversationId: string;
  token: string;
}

const failure = (
  code: CallbackErrorCode,
  reason: string,
): HttpsError =>
  new HttpsError(
    code,
    "Driver plan checkout callback failed.",
    {reason},
  );

const isRecord = (
  value: unknown,
): value is Data =>
  typeof value === "object" &&
  value !== null &&
  !Array.isArray(value);

const hasControlCharacter = (
  value: string,
): boolean =>
  [...value].some((character) => {
    const code =
      character.codePointAt(0) ?? 0;

    return code <= 31 || code === 127;
  });

const requireText = (
  value: unknown,
  reason: string,
  maxLength: number,
): string => {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > maxLength ||
    value.trim() !== value ||
    hasControlCharacter(value)
  ) {
    throw failure(
      "failed-precondition",
      reason,
    );
  }

  return value;
};

export const validateDriverPlanCheckoutCallbackPayload = (
  value: unknown,
): DriverPlanCheckoutCallbackInput => {
  if (!isRecord(value)) {
    throw failure(
      "invalid-argument",
      "invalid_driver_plan_checkout_callback_payload",
    );
  }

  const keys =
    Object.keys(value).sort();

  if (
    keys.length !== 1 ||
    keys[0] !== "token"
  ) {
    throw failure(
      "invalid-argument",
      "invalid_driver_plan_checkout_callback_payload",
    );
  }

  const token =
    value.token;

  if (
    typeof token !== "string" ||
    token.length === 0 ||
    token.length > 2048 ||
    token.trim() !== token ||
    hasControlCharacter(token)
  ) {
    throw failure(
      "invalid-argument",
      "invalid_driver_plan_checkout_callback_token",
    );
  }

  return {token};
};

const parseCallbackOperation = (
  purchaseOperationId: string,
  data: Data,
  callbackToken: string,
): CallbackOperation => {
  if (
    !/^[a-f0-9]{64}$/u.test(
      purchaseOperationId,
    )
  ) {
    throw failure(
      "internal",
      "driver_plan_checkout_callback_operation_invalid",
    );
  }

  const amountMinor =
    data.amountMinor;

  const currency =
    data.currency;

  const status =
    data.status;

  if (
    typeof amountMinor !== "number" ||
    !Number.isSafeInteger(amountMinor) ||
    amountMinor < 0 ||
    typeof currency !== "string" ||
    !/^[A-Z]{3}$/u.test(currency) ||
    (
      status !== "pending" &&
      status !== "settled"
    )
  ) {
    throw failure(
      "internal",
      "driver_plan_checkout_callback_operation_invalid",
    );
  }

  const checkout =
    data.paymentCheckout;

  if (
    !isRecord(checkout) ||
    checkout.status !== "initialized" ||
    checkout.provider !==
      "iyzico_checkout_form"
  ) {
    throw failure(
      "failed-precondition",
      "driver_plan_checkout_not_initialized",
    );
  }

  const conversationId =
    requireText(
      checkout.conversationId,
      "driver_plan_checkout_conversation_invalid",
      256,
    );

  const basketId =
    requireText(
      checkout.basketId,
      "driver_plan_checkout_basket_invalid",
      256,
    );

  const token =
    requireText(
      checkout.token,
      "driver_plan_checkout_token_invalid",
      2048,
    );

  if (basketId !== purchaseOperationId) {
    throw failure(
      "internal",
      "driver_plan_checkout_basket_mismatch",
    );
  }

  if (token !== callbackToken) {
    throw failure(
      "failed-precondition",
      "driver_plan_checkout_callback_token_mismatch",
    );
  }

  return {
    purchaseOperationId,
    amountMinor,
    currency,
    status,
    conversationId,
    token,
  };
};

const loadOperationByToken = async (
  firestore: Firestore,
  token: string,
): Promise<CallbackOperation> => {
  let snapshot;

  try {
    snapshot =
      await firestore
        .collection(
          "driverPlanPurchaseOperations",
        )
        .where(
          "paymentCheckout.token",
          "==",
          token,
        )
        .limit(2)
        .get();
  } catch {
    throw failure(
      "unavailable",
      "driver_plan_checkout_callback_lookup_failed",
    );
  }

  if (snapshot.docs.length === 0) {
    throw failure(
      "not-found",
      "driver_plan_checkout_callback_operation_not_found",
    );
  }

  if (snapshot.docs.length !== 1) {
    throw failure(
      "internal",
      "driver_plan_checkout_callback_token_not_unique",
    );
  }

  const document =
    snapshot.docs[0];

  return parseCallbackOperation(
    document.id,
    document.data(),
    token,
  );
};

const canonicalDecimal = (
  value: unknown,
): string => {
  if (
    typeof value !== "string" ||
    value.trim() !== value ||
    !/^(0|[1-9]\d*)(?:\.\d+)?$/u.test(
      value,
    )
  ) {
    throw failure(
      "failed-precondition",
      "driver_plan_checkout_retrieve_amount_invalid",
    );
  }

  const parts =
    value.split(".");

  const whole =
    parts[0];

  const fraction =
    (parts[1] ?? "").replace(
      /0+$/u,
      "",
    );

  return fraction.length === 0 ?
    whole :
    `${whole}.${fraction}`;
};

const validateRetrievedPayment = (
  operation: CallbackOperation,
  retrieved: DriverPlanPaymentRetrieveResult,
): DriverPlanPaymentRetrieveResult => {
  if (
    retrieved.provider !==
      "iyzico_checkout_form"
  ) {
    throw failure(
      "failed-precondition",
      "driver_plan_checkout_provider_mismatch",
    );
  }

  if (
    retrieved.token !==
    operation.token
  ) {
    throw failure(
      "failed-precondition",
      "driver_plan_checkout_retrieve_token_mismatch",
    );
  }

  if (
    retrieved.conversationId !==
    operation.conversationId
  ) {
    throw failure(
      "failed-precondition",
      "driver_plan_checkout_retrieve_conversation_mismatch",
    );
  }

  if (
    retrieved.basketId !==
    operation.purchaseOperationId
  ) {
    throw failure(
      "failed-precondition",
      "driver_plan_checkout_retrieve_basket_mismatch",
    );
  }

  if (
    retrieved.currency !==
    operation.currency
  ) {
    throw failure(
      "failed-precondition",
      "driver_plan_checkout_retrieve_currency_mismatch",
    );
  }

  if (
    retrieved.paymentStatus !== "SUCCESS" &&
    retrieved.paymentStatus !== "FAILURE"
  ) {
    throw failure(
      "failed-precondition",
      "driver_plan_checkout_retrieve_payment_status_invalid",
    );
  }

  if (
    retrieved.fraudStatus !== -1 &&
    retrieved.fraudStatus !== 0 &&
    retrieved.fraudStatus !== 1
  ) {
    throw failure(
      "failed-precondition",
      "driver_plan_checkout_retrieve_fraud_status_invalid",
    );
  }

  const paymentId =
    requireText(
      retrieved.paymentId,
      "driver_plan_checkout_retrieve_payment_id_invalid",
      256,
    );

  if (paymentId !== retrieved.paymentId) {
    throw failure(
      "failed-precondition",
      "driver_plan_checkout_retrieve_payment_id_invalid",
    );
  }

  const expected =
    canonicalDecimal(
      formatDriverPlanAmountDecimal(
        operation.amountMinor,
        operation.currency,
      ),
    );

  const price =
    canonicalDecimal(
      retrieved.priceDecimal,
    );

  const paidPrice =
    canonicalDecimal(
      retrieved.paidPriceDecimal,
    );

  if (
    price !== expected ||
    paidPrice !== expected
  ) {
    throw failure(
      "failed-precondition",
      "driver_plan_checkout_retrieve_amount_mismatch",
    );
  }

  return retrieved;
};

const retrievePayment = async (
  dependencies: DriverPlanCheckoutCallbackDependencies,
  operation: CallbackOperation,
): Promise<DriverPlanPaymentRetrieveResult> => {
  try {
    return await dependencies.retriever.retrieve({
      conversationId:
        operation.conversationId,
      token:
        operation.token,
    });
  } catch (error: unknown) {
    if (
      error instanceof
      DriverPlanPaymentProviderException
    ) {
      if (error.code === "unavailable") {
        throw failure(
          "unavailable",
          "driver_plan_checkout_retrieve_unavailable",
        );
      }

      if (
        error.code ===
          "provider-rejected"
      ) {
        throw failure(
          "failed-precondition",
          "driver_plan_checkout_retrieve_rejected",
        );
      }

      throw failure(
        "failed-precondition",
        "driver_plan_checkout_retrieve_invalid",
      );
    }

    if (error instanceof HttpsError) {
      throw error;
    }

    throw failure(
      "unavailable",
      "driver_plan_checkout_retrieve_unavailable",
    );
  }
};

export const handleDriverPlanCheckoutCallback = async (
  dependencies: DriverPlanCheckoutCallbackDependencies,
  rawInput: unknown,
): Promise<DriverPlanCheckoutCallbackResult> => {
  const input =
    validateDriverPlanCheckoutCallbackPayload(
      rawInput,
    );

  const operation =
    await loadOperationByToken(
      dependencies.firestore,
      input.token,
    );

  const retrieved =
    validateRetrievedPayment(
      operation,
      await retrievePayment(
        dependencies,
        operation,
      ),
    );

  if (
    retrieved.paymentStatus ===
    "FAILURE" ||
    retrieved.fraudStatus === -1
  ) {
    return {
      status: "payment_failed",
      purchaseOperationId:
        operation.purchaseOperationId,
      paymentId:
        retrieved.paymentId,
    };
  }

  if (retrieved.fraudStatus === 0) {
    return {
      status: "payment_review",
      purchaseOperationId:
        operation.purchaseOperationId,
      paymentId:
        retrieved.paymentId,
    };
  }

  const settlement =
    await settleDriverPlanPurchase(
      {
        firestore:
          dependencies.firestore,
        now:
          dependencies.now,
      },
      {
        purchaseOperationId:
          operation.purchaseOperationId,
        settlementId:
          `iyzico_checkout_form:${retrieved.paymentId}`,
        amountMinor:
          operation.amountMinor,
        currency:
          operation.currency,
      },
    );

  const paymentSettlementId =
    settlement.paymentSettlementId;

  const passId =
    settlement.passId;

  if (
    typeof paymentSettlementId !== "string" ||
    paymentSettlementId.length === 0 ||
    typeof passId !== "string" ||
    passId.length === 0
  ) {
    throw failure(
      "internal",
      "driver_plan_checkout_settlement_result_invalid",
    );
  }

  return {
    status: "settled",
    purchaseOperationId:
      operation.purchaseOperationId,
    paymentId:
      retrieved.paymentId,
    paymentSettlementId,
    passId,
  };
};
