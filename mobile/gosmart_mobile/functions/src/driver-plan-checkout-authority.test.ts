/* eslint-disable max-len, require-jsdoc */
import assert from "node:assert/strict";
import test from "node:test";
import {
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  DriverPlanPaymentInitializeInput,
  DriverPlanPaymentProvider,
  DriverPlanPaymentProviderException,
  DriverPlanPaymentSession,
} from "./driver-plan-payment-provider.js";
import {
  DriverPlanCheckoutDependencies,
  formatDriverPlanAmountDecimal,
  initializeDriverPlanCheckout,
  validateDriverPlanCheckoutPayload,
} from "./driver-plan-checkout-authority.js";

type Data =
  Record<string, unknown>;

class Snap {
  constructor(
    readonly id: string,
    private readonly value?: Data,
  ) {}

  get exists() {
    return this.value !== undefined;
  }

  data() {
    return this.value;
  }

  get(field: string) {
    return this.value?.[field];
  }
}

class Ref {
  constructor(readonly path: string) {}
}

class Collection {
  constructor(readonly name: string) {}

  doc(id: string) {
    return new Ref(
      `${this.name}/${id}`,
    );
  }
}

class Tx {
  constructor(
    private readonly fs: FakeFirestore,
  ) {}

  get(ref: Ref) {
    return Promise.resolve(
      this.fs.snap(ref.path),
    );
  }

  update(
    ref: Ref,
    value: Data,
  ) {
    const current =
      this.fs.get(ref.path);

    if (current === undefined) {
      throw new Error(
        `missing:${ref.path}`,
      );
    }

    this.fs.set(
      ref.path,
      {
        ...current,
        ...value,
      },
    );

    return this;
  }
}

class FakeFirestore {
  private readonly docs =
    new Map<string, Data>();

  collection(name: string) {
    return new Collection(name);
  }

  async runTransaction<T>(
    callback:
      (transaction: Transaction) =>
        Promise<T>,
  ): Promise<T> {
    const transaction =
      new Tx(this) as unknown as Transaction;

    return callback(transaction);
  }

  set(
    path: string,
    data: Data,
  ) {
    this.docs.set(
      path,
      {...data},
    );
  }

  get(path: string) {
    return this.docs.get(path);
  }

  snap(path: string) {
    return new Snap(
      path.substring(
        path.lastIndexOf("/") + 1,
      ),
      this.docs.get(path),
    );
  }
}

class StubProvider
implements DriverPlanPaymentProvider {
  readonly calls:
    DriverPlanPaymentInitializeInput[] = [];

  handler:
    (
      input:
        DriverPlanPaymentInitializeInput,
    ) => Promise<DriverPlanPaymentSession>;

  constructor(
    handler?: (
      input:
        DriverPlanPaymentInitializeInput,
    ) => Promise<DriverPlanPaymentSession>,
  ) {
    this.handler =
      handler ??
      (async (input) => ({
        provider:
          "iyzico_checkout_form",
        purchaseOperationId:
          input.purchaseOperationId,
        conversationId:
          input.conversationId,
        token:
          "checkout-token-123",
        paymentPageUrl:
          "https://sandbox-cpp.iyzipay.com/checkoutform/payment/mock",
      }));
  }

  async initialize(
    input:
      DriverPlanPaymentInitializeInput,
  ): Promise<DriverPlanPaymentSession> {
    this.calls.push(input);
    return this.handler(input);
  }
}

const operationId =
  "a".repeat(64);

const operationPath =
  `driverPlanPurchaseOperations/${operationId}`;

const input = () => ({
  purchaseOperationId:
    operationId,
  buyer: {
    name: "Ali",
    surname: "Veli",
    identityNumber:
      "11111111111",
    email:
      "driver@example.com",
    registrationAddress:
      "Test Address 1",
    city: "Istanbul",
    country: "Turkey",
    zipCode: "34000",
  },
  billingAddress: {
    address:
      "Test Billing Address 1",
    contactName:
      "Ali Veli",
    city: "Istanbul",
    country: "Turkey",
    zipCode: "34000",
  },
});

const reasonIs =
  (expected: string) =>
    (error: unknown): boolean => {
      if (
        !(error instanceof HttpsError)
      ) {
        return false;
      }

      return (
        error.details as
          | Record<string, unknown>
          | undefined
      )?.reason === expected;
    };

const setup = () => {
  const firestore =
    new FakeFirestore();

  const provider =
    new StubProvider();

  const now =
    Timestamp.fromDate(
      new Date(
        "2026-01-15T10:00:00.000Z",
      ),
    );

  firestore.set(
    operationPath,
    {
      actorUid: "uid-1",
      driverId: "driver-1",
      requestDigest:
        "b".repeat(64),
      status: "pending",
      catalogVersion:
        "catalog-v1",
      planId: "daily",
      amountMinor: 12345,
      currency: "TRY",
      createdAt: now,
      updatedAt: now,
      result: {
        purchaseOperationId:
          operationId,
        status: "pending",
        catalogVersion:
          "catalog-v1",
        planId: "daily",
        amountMinor: 12345,
        currency: "TRY",
      },
    },
  );

  let attempt = 0;

  const dependencies:
  DriverPlanCheckoutDependencies = {
    firestore:
      firestore as unknown as Firestore,
    provider,
    now: () => now,
    randomId: () =>
      `attempt_${++attempt}_1234567890`,
    identityLoader:
      async () => "driver-1",
  };

  return {
    firestore,
    provider,
    dependencies,
    runtime: {
      gsmNumber:
        "+905350000000",
      ipAddress:
        "127.0.0.1",
      callbackUrl:
        "https://example.com/iyzico/callback",
    },
  };
};

test("checkout payload is exact and rejects server-owned payment fields", () => {
  assert.deepEqual(
    validateDriverPlanCheckoutPayload(
      input(),
    ),
    input(),
  );

  assert.throws(
    () =>
      validateDriverPlanCheckoutPayload({
        ...input(),
        amountMinor: 12345,
      }),
    reasonIs(
      "invalid_driver_plan_checkout_payload",
    ),
  );

  assert.throws(
    () =>
      validateDriverPlanCheckoutPayload({
        ...input(),
        buyer: {
          ...input().buyer,
          id: "fabricated-driver",
        },
      }),
    reasonIs(
      "invalid_driver_plan_checkout_buyer",
    ),
  );

  assert.throws(
    () =>
      validateDriverPlanCheckoutPayload({
        ...input(),
        buyer: {
          ...input().buyer,
          gsmNumber:
            "+905550000000",
        },
      }),
    reasonIs(
      "invalid_driver_plan_checkout_buyer",
    ),
  );
});

test("amount formatting uses explicit iyzico currency scale", () => {
  assert.equal(
    formatDriverPlanAmountDecimal(
      12345,
      "TRY",
    ),
    "123.45",
  );

  assert.equal(
    formatDriverPlanAmountDecimal(
      5,
      "EUR",
    ),
    "0.05",
  );

  assert.equal(
    formatDriverPlanAmountDecimal(
      0,
      "USD",
    ),
    "0.00",
  );

  assert.throws(
    () =>
      formatDriverPlanAmountDecimal(
        100,
        "JPY",
      ),
    reasonIs(
      "driver_plan_checkout_currency_not_supported",
    ),
  );
});

test("provider request derives all server-owned commercial identity fields", async () => {
  const context = setup();

  const result =
    await initializeDriverPlanCheckout(
      context.dependencies,
      "uid-1",
      input(),
      context.runtime,
    );

  assert.deepEqual(
    result,
    {
      purchaseOperationId:
        operationId,
      status: "initialized",
      provider:
        "iyzico_checkout_form",
      paymentPageUrl:
        "https://sandbox-cpp.iyzipay.com/checkoutform/payment/mock",
    },
  );

  assert.equal(
    Object.prototype.hasOwnProperty.call(
      result,
      "token",
    ),
    false,
  );

  assert.equal(
    context.provider.calls.length,
    1,
  );

  const request =
    context.provider.calls[0];

  assert.equal(
    request.purchaseOperationId,
    operationId,
  );

  assert.equal(
    request.amountDecimal,
    "123.45",
  );

  assert.equal(
    request.currency,
    "TRY",
  );

  assert.equal(
    request.buyer.id,
    "driver-1",
  );

  assert.equal(
    request.buyer.gsmNumber,
    context.runtime.gsmNumber,
  );

  assert.equal(
    request.buyer.ip,
    context.runtime.ipAddress,
  );

  assert.equal(
    request.callbackUrl,
    context.runtime.callbackUrl,
  );

  assert.equal(
    request.basketItem.id,
    operationId,
  );

  assert.equal(
    request.basketItem.category1,
    "Driver Plan",
  );
});

test("buyer and billing PII are not persisted", async () => {
  const context = setup();

  await initializeDriverPlanCheckout(
    context.dependencies,
    "uid-1",
    input(),
    context.runtime,
  );

  const persisted =
    context.firestore
      .get(operationPath)
      ?.paymentCheckout;

  assert.equal(
    typeof persisted,
    "object",
  );

  const encoded =
    JSON.stringify(persisted);

  for (const pii of [
    "Ali",
    "Veli",
    "11111111111",
    "driver@example.com",
    "Test Address 1",
    "Test Billing Address 1",
    "+905350000000",
    "127.0.0.1",
  ]) {
    assert.equal(
      encoded.includes(pii),
      false,
      `PII persisted: ${pii}`,
    );
  }
});

test("initialized checkout replays without second provider initialization", async () => {
  const context = setup();

  const first =
    await initializeDriverPlanCheckout(
      context.dependencies,
      "uid-1",
      input(),
      context.runtime,
    );

  const changed = input();
  changed.buyer.name =
    "Different";
  changed.billingAddress.address =
    "Different Billing Address";

  const replay =
    await initializeDriverPlanCheckout(
      context.dependencies,
      "uid-1",
      changed,
      context.runtime,
    );

  assert.deepEqual(
    replay,
    first,
  );

  assert.equal(
    context.provider.calls.length,
    1,
  );
});

test("initializing state blocks duplicate provider call", async () => {
  const context = setup();

  const now =
    Timestamp.fromDate(
      new Date(
        "2026-01-15T10:00:00.000Z",
      ),
    );

  const current =
    context.firestore
      .get(operationPath);

  assert.ok(current);

  context.firestore.set(
    operationPath,
    {
      ...current,
      paymentCheckout: {
        status:
          "initializing",
        provider:
          "iyzico_checkout_form",
        attemptId:
          "attempt_existing_123456",
        conversationId:
          "conversation_existing_123456",
        basketId:
          operationId,
        startedAt: now,
        updatedAt: now,
      },
    },
  );

  await assert.rejects(
    () =>
      initializeDriverPlanCheckout(
        context.dependencies,
        "uid-1",
        input(),
        context.runtime,
      ),
    reasonIs(
      "driver_plan_checkout_in_progress",
    ),
  );

  assert.equal(
    context.provider.calls.length,
    0,
  );
});

test("transport ambiguity becomes uncertain and blocks automatic retry", async () => {
  const context = setup();

  context.provider.handler =
    async () => {
      throw new DriverPlanPaymentProviderException(
        "unavailable",
        "iyzico_transport_failure",
      );
    };

  await assert.rejects(
    () =>
      initializeDriverPlanCheckout(
        context.dependencies,
        "uid-1",
        input(),
        context.runtime,
      ),
    reasonIs(
      "driver_plan_checkout_uncertain",
    ),
  );

  const state =
    context.firestore
      .get(operationPath)
      ?.paymentCheckout as Data;

  assert.equal(
    state.status,
    "uncertain",
  );

  assert.equal(
    context.provider.calls.length,
    1,
  );

  await assert.rejects(
    () =>
      initializeDriverPlanCheckout(
        context.dependencies,
        "uid-1",
        input(),
        context.runtime,
      ),
    reasonIs(
      "driver_plan_checkout_uncertain",
    ),
  );

  assert.equal(
    context.provider.calls.length,
    1,
  );
});

test("definitive provider rejection allows later safe retry", async () => {
  const context = setup();

  let reject = true;

  context.provider.handler =
    async (request) => {
      if (reject) {
        reject = false;

        throw new DriverPlanPaymentProviderException(
          "provider-rejected",
          "iyzico_checkout_initialize_rejected",
        );
      }

      return {
        provider:
          "iyzico_checkout_form",
        purchaseOperationId:
          request.purchaseOperationId,
        conversationId:
          request.conversationId,
        token:
          "retry-token",
        paymentPageUrl:
          "https://sandbox-cpp.iyzipay.com/checkoutform/payment/retry",
      };
    };

  await assert.rejects(
    () =>
      initializeDriverPlanCheckout(
        context.dependencies,
        "uid-1",
        input(),
        context.runtime,
      ),
    reasonIs(
      "driver_plan_checkout_rejected",
    ),
  );

  const rejected =
    context.firestore
      .get(operationPath)
      ?.paymentCheckout as Data;

  assert.equal(
    rejected.status,
    "rejected",
  );

  const result =
    await initializeDriverPlanCheckout(
      context.dependencies,
      "uid-1",
      input(),
      context.runtime,
    );

  assert.equal(
    result.status,
    "initialized",
  );

  assert.equal(
    context.provider.calls.length,
    2,
  );
});

test("purchase owner and approved driver identity are server-controlled", async () => {
  const actorMismatch =
    setup();

  const original =
    actorMismatch.firestore
      .get(operationPath);

  assert.ok(original);

  actorMismatch.firestore.set(
    operationPath,
    {
      ...original,
      actorUid: "uid-other",
    },
  );

  await assert.rejects(
    () =>
      initializeDriverPlanCheckout(
        actorMismatch.dependencies,
        "uid-1",
        input(),
        actorMismatch.runtime,
      ),
    reasonIs(
      "purchase_operation_actor_mismatch",
    ),
  );

  assert.equal(
    actorMismatch.provider.calls.length,
    0,
  );

  const driverMismatch =
    setup();

  driverMismatch.dependencies
    .identityLoader =
      async () => "driver-other";

  await assert.rejects(
    () =>
      initializeDriverPlanCheckout(
        driverMismatch.dependencies,
        "uid-1",
        input(),
        driverMismatch.runtime,
      ),
    reasonIs(
      "driver_identity_changed",
    ),
  );

  assert.equal(
    driverMismatch.provider.calls.length,
    0,
  );
});

test("settled purchase cannot start another checkout", async () => {
  const context = setup();

  const original =
    context.firestore
      .get(operationPath);

  assert.ok(original);

  context.firestore.set(
    operationPath,
    {
      ...original,
      status: "settled",
      paymentSettlementId:
        "settlement-doc",
      passId:
        "pass-doc",
    },
  );

  await assert.rejects(
    () =>
      initializeDriverPlanCheckout(
        context.dependencies,
        "uid-1",
        input(),
        context.runtime,
      ),
    reasonIs(
      "driver_plan_purchase_already_settled",
    ),
  );

  assert.equal(
    context.provider.calls.length,
    0,
  );
});
