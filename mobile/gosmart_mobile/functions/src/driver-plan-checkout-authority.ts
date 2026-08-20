import {randomUUID} from "node:crypto";
import {
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  DRIVER_PLAN_IDS,
  DriverPlanId,
} from "./driver-plan-catalog.js";
import {
  DriverPlanPaymentInitializeInput,
  DriverPlanPaymentProvider,
  DriverPlanPaymentProviderException,
  DriverPlanPaymentSession,
} from "./driver-plan-payment-provider.js";
import {
  loadApprovedDriverIdInTransaction,
} from "./ride-driver-identity.js";

const PROVIDER_NAME =
  "iyzico_checkout_form" as const;

const IYZICO_CURRENCIES = [
  "TRY",
  "USD",
  "EUR",
  "GBP",
  "NOK",
  "CHF",
] as const;

type IyzicoCurrency =
  (typeof IYZICO_CURRENCIES)[number];

const IYZICO_MINOR_UNIT_DIGITS:
Record<IyzicoCurrency, number> = {
  TRY: 2,
  USD: 2,
  EUR: 2,
  GBP: 2,
  NOK: 2,
  CHF: 2,
};

type CheckoutErrorCode =
  | "aborted"
  | "failed-precondition"
  | "internal"
  | "invalid-argument"
  | "permission-denied"
  | "unavailable";

export type DriverPlanCheckoutBuyerInput = {
  name: string;
  surname: string;
  identityNumber: string;
  email: string;
  registrationAddress: string;
  city: string;
  country: string;
  zipCode: string;
};

export type DriverPlanCheckoutBillingAddressInput = {
  address: string;
  contactName: string;
  city: string;
  country: string;
  zipCode: string;
};

export type DriverPlanCheckoutInput = {
  purchaseOperationId: string;
  buyer: DriverPlanCheckoutBuyerInput;
  billingAddress:
    DriverPlanCheckoutBillingAddressInput;
};

export type DriverPlanCheckoutRuntime = {
  gsmNumber: string;
  ipAddress: string;
  callbackUrl: string;
};

export type DriverPlanCheckoutDependencies = {
  firestore: Firestore;
  provider: DriverPlanPaymentProvider;
  now?: () => Timestamp;
  randomId?: () => string;
  identityLoader?: (
    firestore: Firestore,
    actorUid: string,
    transaction: Transaction,
  ) => Promise<string>;
};

export type DriverPlanCheckoutResult = {
  purchaseOperationId: string;
  status: "initialized";
  provider: typeof PROVIDER_NAME;
  paymentPageUrl: string;
};

type PreparedCheckout = {
  purchaseOperationId: string;
  driverId: string;
  planId: DriverPlanId;
  amountMinor: number;
  currency: string;
  amountDecimal: string;
};

type CheckoutStateBase = {
  provider: typeof PROVIDER_NAME;
  attemptId: string;
  conversationId: string;
  basketId: string;
  startedAt: Timestamp;
  updatedAt: Timestamp;
};

type CheckoutInitializingState =
  CheckoutStateBase & {
    status: "initializing";
  };

type CheckoutFailedState =
  CheckoutStateBase & {
    status: "rejected" | "uncertain";
    reason: string;
  };

type CheckoutInitializedState =
  CheckoutStateBase & {
    status: "initialized";
    token: string;
    paymentPageUrl: string;
    initializedAt: Timestamp;
  };

type CheckoutState =
  | CheckoutInitializingState
  | CheckoutFailedState
  | CheckoutInitializedState;

type BeginCheckoutResult =
  | {
    kind: "replay";
    result: DriverPlanCheckoutResult;
  }
  | {
    kind: "initialize";
    prepared: PreparedCheckout;
    attemptId: string;
    conversationId: string;
  };

const failure = (
  code: CheckoutErrorCode,
  reason: string,
): HttpsError =>
  new HttpsError(
    code,
    "Driver plan checkout could not be completed.",
    {reason},
  );

const isRecord = (
  value: unknown,
): value is Record<string, unknown> =>
  typeof value === "object" &&
  value !== null &&
  !Array.isArray(value) &&
  Object.getPrototypeOf(value) ===
    Object.prototype;

const exactObject = (
  value: unknown,
  keys: readonly string[],
  reason: string,
): Record<string, unknown> => {
  if (!isRecord(value)) {
    throw failure(
      "invalid-argument",
      reason,
    );
  }

  const actual = Object.keys(value);

  if (
    actual.length !== keys.length ||
    keys.some((key) => !actual.includes(key))
  ) {
    throw failure(
      "invalid-argument",
      reason,
    );
  }

  return value;
};

const hasControlCharacter = (
  value: string,
): boolean =>
  [...value].some((character) => {
    const code =
      character.codePointAt(0) ?? 0;

    return code <= 31 || code === 127;
  });

const requireInputText = (
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
      "invalid-argument",
      reason,
    );
  }

  return value;
};

const requireRuntimeText = (
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

const validateEmail = (
  value: unknown,
): string => {
  const email = requireInputText(
    value,
    "invalid_checkout_buyer_email",
    254,
  );

  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/u.test(email)) {
    throw failure(
      "invalid-argument",
      "invalid_checkout_buyer_email",
    );
  }

  return email;
};

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

/**
 * Validates the exact transient checkout payload.
 * @param {*} value Raw checkout payload.
 * @return {DriverPlanCheckoutInput} Validated checkout payload.
 */
export const validateDriverPlanCheckoutPayload = (
  value: unknown,
): DriverPlanCheckoutInput => {
  const input = exactObject(
    value,
    [
      "purchaseOperationId",
      "buyer",
      "billingAddress",
    ],
    "invalid_driver_plan_checkout_payload",
  );

  const buyer = exactObject(
    input.buyer,
    [
      "name",
      "surname",
      "identityNumber",
      "email",
      "registrationAddress",
      "city",
      "country",
      "zipCode",
    ],
    "invalid_driver_plan_checkout_buyer",
  );

  const billingAddress = exactObject(
    input.billingAddress,
    [
      "address",
      "contactName",
      "city",
      "country",
      "zipCode",
    ],
    "invalid_driver_plan_checkout_billing_address",
  );

  return {
    purchaseOperationId:
      validatePurchaseOperationId(
        input.purchaseOperationId,
      ),
    buyer: {
      name: requireInputText(
        buyer.name,
        "invalid_checkout_buyer_name",
        100,
      ),
      surname: requireInputText(
        buyer.surname,
        "invalid_checkout_buyer_surname",
        100,
      ),
      identityNumber: requireInputText(
        buyer.identityNumber,
        "invalid_checkout_buyer_identity_number",
        64,
      ),
      email:
        validateEmail(buyer.email),
      registrationAddress: requireInputText(
        buyer.registrationAddress,
        "invalid_checkout_buyer_registration_address",
        500,
      ),
      city: requireInputText(
        buyer.city,
        "invalid_checkout_buyer_city",
        100,
      ),
      country: requireInputText(
        buyer.country,
        "invalid_checkout_buyer_country",
        100,
      ),
      zipCode: requireInputText(
        buyer.zipCode,
        "invalid_checkout_buyer_zip_code",
        32,
      ),
    },
    billingAddress: {
      address: requireInputText(
        billingAddress.address,
        "invalid_checkout_billing_address",
        500,
      ),
      contactName: requireInputText(
        billingAddress.contactName,
        "invalid_checkout_billing_contact_name",
        200,
      ),
      city: requireInputText(
        billingAddress.city,
        "invalid_checkout_billing_city",
        100,
      ),
      country: requireInputText(
        billingAddress.country,
        "invalid_checkout_billing_country",
        100,
      ),
      zipCode: requireInputText(
        billingAddress.zipCode,
        "invalid_checkout_billing_zip_code",
        32,
      ),
    },
  };
};

/**
 * Converts server-authoritative minor units using an explicit
 * iyzico-supported currency scale.
 * @param {number} amountMinor Server-authoritative minor-unit amount.
 * @param {string} currency Canonical three-letter currency.
 * @return {string} Provider decimal amount.
 */
export const formatDriverPlanAmountDecimal = (
  amountMinor: number,
  currency: string,
): string => {
  if (
    !Number.isSafeInteger(amountMinor) ||
    amountMinor < 0
  ) {
    throw failure(
      "failed-precondition",
      "driver_plan_checkout_amount_invalid",
    );
  }

  if (
    !IYZICO_CURRENCIES.includes(
      currency as IyzicoCurrency,
    )
  ) {
    throw failure(
      "failed-precondition",
      "driver_plan_checkout_currency_not_supported",
    );
  }

  const scale =
    IYZICO_MINOR_UNIT_DIGITS[
      currency as IyzicoCurrency
    ];

  if (scale === 0) {
    return amountMinor.toString();
  }

  const digits =
    amountMinor
      .toString()
      .padStart(scale + 1, "0");

  const whole =
    digits.slice(0, -scale);

  const fraction =
    digits.slice(-scale);

  return `${whole}.${fraction}`;
};

const validateRuntime = (
  value: DriverPlanCheckoutRuntime,
): DriverPlanCheckoutRuntime => {
  const gsmNumber = requireRuntimeText(
    value.gsmNumber,
    "driver_verified_phone_required",
    32,
  );

  if (!/^\+[1-9]\d{7,14}$/u.test(gsmNumber)) {
    throw failure(
      "failed-precondition",
      "driver_verified_phone_required",
    );
  }

  const ipAddress = requireRuntimeText(
    value.ipAddress,
    "driver_checkout_ip_unavailable",
    128,
  );

  const callbackUrl = requireRuntimeText(
    value.callbackUrl,
    "driver_checkout_callback_unavailable",
    2048,
  );

  let parsed: URL;

  try {
    parsed = new URL(callbackUrl);
  } catch {
    throw failure(
      "failed-precondition",
      "driver_checkout_callback_unavailable",
    );
  }

  if (parsed.protocol !== "https:") {
    throw failure(
      "failed-precondition",
      "driver_checkout_callback_unavailable",
    );
  }

  return {
    gsmNumber,
    ipAddress,
    callbackUrl,
  };
};

const hasExactKeys = (
  value: Record<string, unknown>,
  expected: readonly string[],
): boolean => {
  const actual = Object.keys(value);

  return (
    actual.length === expected.length &&
    actual.every(
      (key) => expected.includes(key),
    )
  );
};

const stateText = (
  value: unknown,
  maxLength: number,
): string | null => {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > maxLength ||
    value.trim() !== value ||
    hasControlCharacter(value)
  ) {
    return null;
  }

  return value;
};

const paymentPageUrl = (
  value: unknown,
): string | null => {
  const raw = stateText(value, 4096);

  if (raw === null) {
    return null;
  }

  let parsed: URL;

  try {
    parsed = new URL(raw);
  } catch {
    return null;
  }

  const host =
    parsed.hostname.toLowerCase();

  if (
    parsed.protocol !== "https:" ||
    (
      host !== "iyzipay.com" &&
      !host.endsWith(".iyzipay.com")
    )
  ) {
    return null;
  }

  return raw;
};

const parseCheckoutState = (
  value: unknown,
): CheckoutState | null => {
  if (value === undefined) {
    return null;
  }

  if (!isRecord(value)) {
    throw failure(
      "internal",
      "driver_plan_checkout_state_invalid",
    );
  }

  const status = value.status;

  const baseKeys = [
    "status",
    "provider",
    "attemptId",
    "conversationId",
    "basketId",
    "startedAt",
    "updatedAt",
  ];

  const expectedKeys =
    status === "initialized" ?
      [
        ...baseKeys,
        "token",
        "paymentPageUrl",
        "initializedAt",
      ] :
      status === "rejected" ||
        status === "uncertain" ?
        [
          ...baseKeys,
          "reason",
        ] :
        status === "initializing" ?
          baseKeys :
          [];

  if (
    expectedKeys.length === 0 ||
    !hasExactKeys(
      value,
      expectedKeys,
    )
  ) {
    throw failure(
      "internal",
      "driver_plan_checkout_state_invalid",
    );
  }

  const attemptId =
    stateText(value.attemptId, 128);

  const conversationId =
    stateText(value.conversationId, 256);

  const basketId =
    stateText(value.basketId, 128);

  if (
    value.provider !== PROVIDER_NAME ||
    attemptId === null ||
    conversationId === null ||
    basketId === null ||
    !(value.startedAt instanceof Timestamp) ||
    !(value.updatedAt instanceof Timestamp)
  ) {
    throw failure(
      "internal",
      "driver_plan_checkout_state_invalid",
    );
  }

  const base: CheckoutStateBase = {
    provider: PROVIDER_NAME,
    attemptId,
    conversationId,
    basketId,
    startedAt: value.startedAt,
    updatedAt: value.updatedAt,
  };

  if (status === "initializing") {
    return {
      ...base,
      status,
    };
  }

  if (
    status === "rejected" ||
    status === "uncertain"
  ) {
    const reason =
      stateText(value.reason, 128);

    if (reason === null) {
      throw failure(
        "internal",
        "driver_plan_checkout_state_invalid",
      );
    }

    return {
      ...base,
      status,
      reason,
    };
  }

  const token =
    stateText(value.token, 2048);

  const url =
    paymentPageUrl(
      value.paymentPageUrl,
    );

  if (
    token === null ||
    url === null ||
    !(value.initializedAt instanceof Timestamp)
  ) {
    throw failure(
      "internal",
      "driver_plan_checkout_state_invalid",
    );
  }

  return {
    ...base,
    status: "initialized",
    token,
    paymentPageUrl: url,
    initializedAt:
      value.initializedAt,
  };
};

const initializedResult = (
  purchaseOperationId: string,
  state: CheckoutInitializedState,
): DriverPlanCheckoutResult => ({
  purchaseOperationId,
  status: "initialized",
  provider: PROVIDER_NAME,
  paymentPageUrl:
    state.paymentPageUrl,
});

const parsePreparedOperation = (
  data: Record<string, unknown>,
  purchaseOperationId: string,
  actorUid: string,
  approvedDriverId: string,
): Omit<PreparedCheckout, "amountDecimal"> => {
  if (data.actorUid !== actorUid) {
    throw failure(
      "permission-denied",
      "purchase_operation_actor_mismatch",
    );
  }

  if (
    typeof data.driverId !== "string" ||
    data.driverId.trim().length === 0
  ) {
    throw failure(
      "internal",
      "purchase_operation_invalid",
    );
  }

  if (data.driverId !== approvedDriverId) {
    throw failure(
      "failed-precondition",
      "driver_identity_changed",
    );
  }

  if (data.status === "settled") {
    throw failure(
      "failed-precondition",
      "driver_plan_purchase_already_settled",
    );
  }

  if (data.status !== "pending") {
    throw failure(
      "internal",
      "purchase_operation_invalid",
    );
  }

  if (
    !DRIVER_PLAN_IDS.includes(
      data.planId as DriverPlanId
    ) ||
    typeof data.amountMinor !== "number" ||
    !Number.isSafeInteger(data.amountMinor) ||
    data.amountMinor < 0 ||
    typeof data.currency !== "string" ||
    !/^[A-Z]{3}$/u.test(data.currency) ||
    typeof data.catalogVersion !== "string" ||
    data.catalogVersion.trim().length === 0 ||
    typeof data.requestDigest !== "string" ||
    !/^[a-f0-9]{64}$/u.test(
      data.requestDigest
    ) ||
    !(data.createdAt instanceof Timestamp) ||
    !(data.updatedAt instanceof Timestamp) ||
    data.passId !== undefined ||
    data.paymentSettlementId !== undefined
  ) {
    throw failure(
      "internal",
      "purchase_operation_invalid",
    );
  }

  const result = data.result;

  if (
    !isRecord(result) ||
    result.purchaseOperationId !==
      purchaseOperationId ||
    result.status !== "pending" ||
    result.catalogVersion !==
      data.catalogVersion ||
    result.planId !== data.planId ||
    result.amountMinor !==
      data.amountMinor ||
    result.currency !== data.currency
  ) {
    throw failure(
      "internal",
      "purchase_operation_invalid",
    );
  }

  return {
    purchaseOperationId,
    driverId: data.driverId,
    planId: data.planId as DriverPlanId,
    amountMinor: data.amountMinor,
    currency: data.currency,
  };
};

const buildAttemptIdentity = (
  purchaseOperationId: string,
  rawRandomId: string,
): {
  attemptId: string;
  conversationId: string;
} => {
  const attemptId = requireRuntimeText(
    rawRandomId,
    "driver_plan_checkout_attempt_invalid",
    128,
  );

  const compact =
    attemptId.replace(
      /[^A-Za-z0-9]/gu,
      "",
    );

  if (compact.length < 8) {
    throw failure(
      "internal",
      "driver_plan_checkout_attempt_invalid",
    );
  }

  const operationPart =
    purchaseOperationId.slice(0, 32);

  const attemptPart =
    compact.slice(0, 24);

  return {
    attemptId,
    conversationId:
      `dp_${operationPart}_${attemptPart}`,
  };
};

const beginCheckout = async (
  dependencies: DriverPlanCheckoutDependencies,
  actorUid: string,
  input: DriverPlanCheckoutInput,
  attempt: {
    attemptId: string;
    conversationId: string;
  },
): Promise<BeginCheckoutResult> => {
  const now =
    dependencies.now?.() ??
    Timestamp.now();

  const operationRef =
    dependencies.firestore
      .collection(
        "driverPlanPurchaseOperations",
      )
      .doc(input.purchaseOperationId);

  const identityLoader =
    dependencies.identityLoader ??
    loadApprovedDriverIdInTransaction;

  return dependencies.firestore.runTransaction(
    async (transaction) => {
      const operation =
        await transaction.get(operationRef);

      const approvedDriverId =
        await identityLoader(
          dependencies.firestore,
          actorUid,
          transaction,
        );

      if (!operation.exists) {
        throw failure(
          "failed-precondition",
          "purchase_operation_not_found",
        );
      }

      const data = operation.data();

      if (!isRecord(data)) {
        throw failure(
          "internal",
          "purchase_operation_invalid",
        );
      }

      const preparedBase =
        parsePreparedOperation(
          data,
          input.purchaseOperationId,
          actorUid,
          approvedDriverId,
        );

      const existing =
        parseCheckoutState(
          data.paymentCheckout,
        );

      if (
        existing?.status ===
        "initialized"
      ) {
        return {
          kind: "replay",
          result: initializedResult(
            input.purchaseOperationId,
            existing,
          ),
        };
      }

      if (
        existing?.status ===
        "initializing"
      ) {
        throw failure(
          "aborted",
          "driver_plan_checkout_in_progress",
        );
      }

      if (
        existing?.status ===
        "uncertain"
      ) {
        throw failure(
          "failed-precondition",
          "driver_plan_checkout_uncertain",
        );
      }

      const amountDecimal =
        formatDriverPlanAmountDecimal(
          preparedBase.amountMinor,
          preparedBase.currency,
        );

      const state:
      CheckoutInitializingState = {
        status: "initializing",
        provider: PROVIDER_NAME,
        attemptId: attempt.attemptId,
        conversationId:
          attempt.conversationId,
        basketId:
          input.purchaseOperationId,
        startedAt: now,
        updatedAt: now,
      };

      transaction.update(
        operationRef,
        {
          paymentCheckout: state,
        },
      );

      return {
        kind: "initialize",
        prepared: {
          ...preparedBase,
          amountDecimal,
        },
        attemptId:
          attempt.attemptId,
        conversationId:
          attempt.conversationId,
      };
    },
  );
};

const DETERMINISTIC_REJECTION_REASONS =
  new Set<string>([
    "iyzico_api_key_unavailable",
    "iyzico_secret_key_unavailable",
    "iyzico_random_key_invalid",
    "invalid_iyzico_api_host",
    "invalid_callback_url",
    "unsupported_iyzico_currency",
    "invalid_amount_decimal",
    "iyzico_checkout_initialize_rejected",
  ]);

const classifyProviderFailure = (
  error: unknown,
): {
  status: "rejected" | "uncertain";
  reason: string;
} => {
  if (
    error instanceof
      DriverPlanPaymentProviderException &&
    DETERMINISTIC_REJECTION_REASONS.has(
      error.reason,
    )
  ) {
    return {
      status: "rejected",
      reason: error.reason,
    };
  }

  return {
    status: "uncertain",
    reason:
      "provider_outcome_uncertain",
  };
};

const markCheckoutFailure = async (
  dependencies:
    DriverPlanCheckoutDependencies,
  purchaseOperationId: string,
  attemptId: string,
  status: "rejected" | "uncertain",
  reason: string,
): Promise<void> => {
  const operationRef =
    dependencies.firestore
      .collection(
        "driverPlanPurchaseOperations",
      )
      .doc(purchaseOperationId);

  const now =
    dependencies.now?.() ??
    Timestamp.now();

  await dependencies.firestore.runTransaction(
    async (transaction) => {
      const operation =
        await transaction.get(
          operationRef,
        );

      if (!operation.exists) {
        throw failure(
          "internal",
          "driver_plan_checkout_state_persistence_failed",
        );
      }

      const data = operation.data();

      if (!isRecord(data)) {
        throw failure(
          "internal",
          "driver_plan_checkout_state_persistence_failed",
        );
      }

      const state =
        parseCheckoutState(
          data.paymentCheckout,
        );

      if (
        state === null ||
        state.status !== "initializing" ||
        state.attemptId !== attemptId
      ) {
        throw failure(
          "internal",
          "driver_plan_checkout_state_persistence_failed",
        );
      }

      const next:
      CheckoutFailedState = {
        ...state,
        status,
        reason,
        updatedAt: now,
      };

      transaction.update(
        operationRef,
        {
          paymentCheckout: next,
        },
      );
    },
  );
};

const requireProviderSession = (
  session: DriverPlanPaymentSession,
  purchaseOperationId: string,
  conversationId: string,
): DriverPlanPaymentSession => {
  if (
    session.provider !== PROVIDER_NAME ||
    session.purchaseOperationId !==
      purchaseOperationId ||
    session.conversationId !==
      conversationId
  ) {
    throw failure(
      "internal",
      "driver_plan_checkout_provider_response_invalid",
    );
  }

  const token =
    stateText(session.token, 2048);

  const url =
    paymentPageUrl(
      session.paymentPageUrl,
    );

  if (
    token === null ||
    url === null
  ) {
    throw failure(
      "internal",
      "driver_plan_checkout_provider_response_invalid",
    );
  }

  return {
    provider: PROVIDER_NAME,
    purchaseOperationId,
    conversationId,
    token,
    paymentPageUrl: url,
  };
};

const persistInitializedCheckout = async (
  dependencies:
    DriverPlanCheckoutDependencies,
  purchaseOperationId: string,
  attemptId: string,
  session: DriverPlanPaymentSession,
): Promise<DriverPlanCheckoutResult> => {
  const operationRef =
    dependencies.firestore
      .collection(
        "driverPlanPurchaseOperations",
      )
      .doc(purchaseOperationId);

  const now =
    dependencies.now?.() ??
    Timestamp.now();

  return dependencies.firestore.runTransaction(
    async (transaction) => {
      const operation =
        await transaction.get(
          operationRef,
        );

      if (!operation.exists) {
        throw failure(
          "internal",
          "driver_plan_checkout_state_persistence_failed",
        );
      }

      const data = operation.data();

      if (!isRecord(data)) {
        throw failure(
          "internal",
          "driver_plan_checkout_state_persistence_failed",
        );
      }

      const state =
        parseCheckoutState(
          data.paymentCheckout,
        );

      if (
        state === null ||
        state.status !== "initializing" ||
        state.attemptId !== attemptId
      ) {
        throw failure(
          "internal",
          "driver_plan_checkout_state_persistence_failed",
        );
      }

      const initialized:
      CheckoutInitializedState = {
        ...state,
        status: "initialized",
        token: session.token,
        paymentPageUrl:
          session.paymentPageUrl,
        initializedAt: now,
        updatedAt: now,
      };

      transaction.update(
        operationRef,
        {
          paymentCheckout:
            initialized,
        },
      );

      return initializedResult(
        purchaseOperationId,
        initialized,
      );
    },
  );
};

/**
 * Initializes or safely replays an iyzico Checkout Form session.
 * @param {DriverPlanCheckoutDependencies} dependencies Server dependencies.
 * @param {string} actorUid Authenticated Firebase actor UID.
 * @param {*} rawInput Transient untrusted checkout payload.
 * @param {DriverPlanCheckoutRuntime} rawRuntime Server-owned runtime values.
 * @return {Promise<DriverPlanCheckoutResult>} Initialized checkout result.
 */
export const initializeDriverPlanCheckout = async (
  dependencies:
    DriverPlanCheckoutDependencies,
  actorUid: string,
  rawInput: unknown,
  rawRuntime:
    DriverPlanCheckoutRuntime,
): Promise<DriverPlanCheckoutResult> => {
  const input =
    validateDriverPlanCheckoutPayload(
      rawInput,
    );

  const runtime =
    validateRuntime(rawRuntime);

  const attempt =
    buildAttemptIdentity(
      input.purchaseOperationId,
      dependencies.randomId?.() ??
        randomUUID(),
    );

  const begin =
    await beginCheckout(
      dependencies,
      actorUid,
      input,
      attempt,
    );

  if (begin.kind === "replay") {
    return begin.result;
  }

  const providerInput:
  DriverPlanPaymentInitializeInput = {
    purchaseOperationId:
      begin.prepared.purchaseOperationId,
    conversationId:
      begin.conversationId,
    amountDecimal:
      begin.prepared.amountDecimal,
    currency:
      begin.prepared.currency,
    callbackUrl:
      runtime.callbackUrl,
    buyer: {
      id:
        begin.prepared.driverId,
      name:
        input.buyer.name,
      surname:
        input.buyer.surname,
      identityNumber:
        input.buyer.identityNumber,
      email:
        input.buyer.email,
      gsmNumber:
        runtime.gsmNumber,
      registrationAddress:
        input.buyer.registrationAddress,
      city:
        input.buyer.city,
      country:
        input.buyer.country,
      ip:
        runtime.ipAddress,
      zipCode:
        input.buyer.zipCode,
    },
    billingAddress: {
      address:
        input.billingAddress.address,
      contactName:
        input.billingAddress.contactName,
      city:
        input.billingAddress.city,
      country:
        input.billingAddress.country,
      zipCode:
        input.billingAddress.zipCode,
    },
    basketItem: {
      id:
        begin.prepared.purchaseOperationId,
      name:
        `GoSmart driver plan ${begin.prepared.planId}`,
      category1:
        "Driver Plan",
    },
  };

  let session:
    DriverPlanPaymentSession;

  try {
    session =
      await dependencies.provider
        .initialize(providerInput);
  } catch (error: unknown) {
    const classified =
      classifyProviderFailure(error);

    try {
      await markCheckoutFailure(
        dependencies,
        input.purchaseOperationId,
        begin.attemptId,
        classified.status,
        classified.reason,
      );
    } catch {
      throw failure(
        "unavailable",
        "driver_plan_checkout_state_persistence_failed",
      );
    }

    if (
      classified.status ===
      "rejected"
    ) {
      throw failure(
        "failed-precondition",
        "driver_plan_checkout_rejected",
      );
    }

    throw failure(
      "unavailable",
      "driver_plan_checkout_uncertain",
    );
  }

  let verifiedSession:
    DriverPlanPaymentSession;

  try {
    verifiedSession =
      requireProviderSession(
        session,
        input.purchaseOperationId,
        begin.conversationId,
      );
  } catch {
    try {
      await markCheckoutFailure(
        dependencies,
        input.purchaseOperationId,
        begin.attemptId,
        "uncertain",
        "provider_response_invalid",
      );
    } catch {
      throw failure(
        "unavailable",
        "driver_plan_checkout_state_persistence_failed",
      );
    }

    throw failure(
      "unavailable",
      "driver_plan_checkout_uncertain",
    );
  }

  try {
    return await persistInitializedCheckout(
      dependencies,
      input.purchaseOperationId,
      begin.attemptId,
      verifiedSession,
    );
  } catch {
    throw failure(
      "unavailable",
      "driver_plan_checkout_state_persistence_failed",
    );
  }
};
