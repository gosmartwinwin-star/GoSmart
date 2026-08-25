/* eslint-disable max-len, require-jsdoc */

import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  DriverPlanPaymentProviderException,
  DriverPlanPaymentRetrieveInput,
  DriverPlanPaymentRetrieveResult,
  DriverPlanPaymentRetriever,
} from "./driver-plan-payment-provider.js";
import {
  handleDriverPlanCheckoutCallback,
  validateDriverPlanCheckoutCallbackPayload,
} from "./driver-plan-checkout-callback-authority.js";

type Data = Record<string, unknown>;

const nestedValue = (
  data: Data | undefined,
  field: string,
): unknown => {
  let current: unknown = data;

  for (const part of field.split(".")) {
    if (
      typeof current !== "object" ||
      current === null ||
      Array.isArray(current)
    ) {
      return undefined;
    }

    current =
      (current as Data)[part];
  }

  return current;
};

class Snap {
  constructor(
    readonly id: string,
    private readonly value:
      Data | undefined,
  ) {}

  get exists() {
    return this.value !== undefined;
  }

  data() {
    return this.value;
  }

  get(field: string) {
    return nestedValue(
      this.value,
      field,
    );
  }
}

class Ref {
  constructor(
    readonly fs: FakeFirestore,
    readonly path: string,
  ) {}

  get id() {
    return this.path.substring(
      this.path.lastIndexOf("/") + 1,
    );
  }

  get() {
    return Promise.resolve(
      this.fs.snap(this.path),
    );
  }
}

interface Filter {
  field: string;
  value: unknown;
}

class Query {
  constructor(
    readonly fs: FakeFirestore,
    readonly collectionName: string,
    readonly filters: Filter[] = [],
    readonly orderField:
      string | undefined = undefined,
    readonly descending = false,
    readonly limitCount:
      number | undefined = undefined,
  ) {}

  where(
    field: string,
    operator: string,
    value: unknown,
  ) {
    if (operator !== "==") {
      throw new Error(
        `Unsupported operator: ${operator}`,
      );
    }

    return new Query(
      this.fs,
      this.collectionName,
      [
        ...this.filters,
        {field, value},
      ],
      this.orderField,
      this.descending,
      this.limitCount,
    );
  }

  orderBy(
    field: string,
    direction = "asc",
  ) {
    return new Query(
      this.fs,
      this.collectionName,
      this.filters,
      field,
      direction === "desc",
      this.limitCount,
    );
  }

  limit(count: number) {
    return new Query(
      this.fs,
      this.collectionName,
      this.filters,
      this.orderField,
      this.descending,
      count,
    );
  }

  get() {
    return Promise.resolve(
      this.fs.query(this),
    );
  }
}

class Collection extends Query {
  constructor(
    fs: FakeFirestore,
    collectionName: string,
  ) {
    super(fs, collectionName);
  }

  doc(id: string) {
    return new Ref(
      this.fs,
      `${this.collectionName}/${id}`,
    );
  }
}

type Mutation =
  | {
    type: "create";
    path: string;
    data: Data;
  }
  | {
    type: "update";
    path: string;
    data: Data;
  };

class Tx {
  private readonly mutations:
    Mutation[] = [];

  constructor(
    private readonly fs:
      FakeFirestore,
  ) {}

  get(
    target: Ref | Query,
  ): Promise<unknown> {
    if (target instanceof Ref) {
      return Promise.resolve(
        this.fs.snap(target.path),
      );
    }

    return Promise.resolve(
      this.fs.query(target),
    );
  }

  create(
    ref: Ref,
    data: Data,
  ) {
    this.mutations.push({
      type: "create",
      path: ref.path,
      data,
    });
  }

  update(
    ref: Ref,
    data: Data,
  ) {
    this.mutations.push({
      type: "update",
      path: ref.path,
      data,
    });
  }

  commit() {
    for (const mutation of this.mutations) {
      if (
        mutation.type === "create" &&
        this.fs.get(mutation.path) !==
          undefined
      ) {
        throw new Error(
          `Document exists: ${mutation.path}`,
        );
      }

      if (mutation.type === "create") {
        this.fs.set(
          mutation.path,
          mutation.data,
        );
        continue;
      }

      const current =
        this.fs.get(mutation.path);

      if (current === undefined) {
        throw new Error(
          `Document missing: ${mutation.path}`,
        );
      }

      this.fs.set(
        mutation.path,
        {
          ...current,
          ...mutation.data,
        },
      );
    }
  }
}

class FakeFirestore {
  private readonly docs =
    new Map<string, Data>();

  collection(name: string) {
    return new Collection(
      this,
      name,
    );
  }

  async runTransaction<T>(
    callback:
      (transaction: Transaction) =>
        Promise<T>,
  ): Promise<T> {
    const tx =
      new Tx(this);

    const result =
      await callback(
        tx as unknown as Transaction,
      );

    tx.commit();

    return result;
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

  count(collectionName: string) {
    const prefix =
      `${collectionName}/`;

    return [...this.docs.keys()]
      .filter(
        (path) =>
          path.startsWith(prefix) &&
          !path.substring(
            prefix.length,
          ).includes("/"),
      )
      .length;
  }

  query(query: Query) {
    const prefix =
      `${query.collectionName}/`;

    let entries =
      [...this.docs.entries()]
        .filter(([path]) =>
          path.startsWith(prefix) &&
          !path.substring(
            prefix.length,
          ).includes("/"),
        )
        .map(
          ([path, data]) =>
            new Snap(
              path.substring(
                path.lastIndexOf("/") + 1,
              ),
              data,
            ),
        );

    for (const filter of query.filters) {
      entries =
        entries.filter(
          (document) =>
            document.get(filter.field) ===
            filter.value,
        );
    }

    if (query.orderField !== undefined) {
      const field =
        query.orderField;

      entries.sort((left, right) => {
        const leftValue =
          left.get(field);

        const rightValue =
          right.get(field);

        const leftMillis =
          leftValue instanceof Timestamp ?
            leftValue.toMillis() :
            0;

        const rightMillis =
          rightValue instanceof Timestamp ?
            rightValue.toMillis() :
            0;

        return query.descending ?
          rightMillis - leftMillis :
          leftMillis - rightMillis;
      });
    }

    if (
      query.limitCount !== undefined
    ) {
      entries =
        entries.slice(
          0,
          query.limitCount,
        );
    }

    return {
      docs: entries,
      empty:
        entries.length === 0,
      size:
        entries.length,
    };
  }
}

class FakeRetriever
implements DriverPlanPaymentRetriever {
  calls = 0;

  lastInput:
    DriverPlanPaymentRetrieveInput |
    undefined;

  constructor(
    public result:
      DriverPlanPaymentRetrieveResult,
    public error:
      unknown = undefined,
  ) {}

  async retrieve(
    input:
      DriverPlanPaymentRetrieveInput,
  ): Promise<DriverPlanPaymentRetrieveResult> {
    this.calls++;
    this.lastInput = input;

    if (this.error !== undefined) {
      throw this.error;
    }

    return this.result;
  }
}

const operationId =
  "a".repeat(64);

const token =
  "checkout-token-123";

const conversationId =
  "checkout-conversation-123";

const now =
  Timestamp.fromDate(
    new Date(
      "2026-08-20T12:00:00.000Z",
    ),
  );

const paymentResult = (
  overrides:
    Partial<DriverPlanPaymentRetrieveResult> = {},
): DriverPlanPaymentRetrieveResult => ({
  provider:
    "iyzico_checkout_form",
  conversationId,
  token,
  paymentStatus: "SUCCESS",
  paymentId: "payment-123",
  fraudStatus: 1,
  basketId: operationId,
  currency: "TRY",
  priceDecimal: "123.45",
  paidPriceDecimal: "123.45",
  ...overrides,
});

const setup = (
  retrieveResult =
  paymentResult(),
) => {
  const fake =
    new FakeFirestore();

  fake.set(
    `driverPlanPurchaseOperations/${operationId}`,
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
      paymentCheckout: {
        status: "initialized",
        provider:
          "iyzico_checkout_form",
        attemptId:
          "attempt_1234567890",
        conversationId,
        basketId:
          operationId,
        startedAt: now,
        updatedAt: now,
        token,
        paymentPageUrl:
          "https://sandbox-cpp.iyzipay.com?token=checkout-token-123",
        initializedAt: now,
      },
    },
  );

  const retriever =
    new FakeRetriever(
      retrieveResult,
    );

  return {
    fake,
    retriever,
    dependencies: {
      firestore:
        fake as unknown as Firestore,
      retriever,
      now: () => now,
    },
  };
};

const reasonIs =
  (expected: string) =>
    (error: unknown): boolean =>
      error instanceof HttpsError &&
      (
        error.details as
          Record<string, unknown> |
          undefined
      )?.reason === expected;

test("callback payload accepts only provider token", () => {
  assert.deepEqual(
    validateDriverPlanCheckoutCallbackPayload({
      token,
    }),
    {token},
  );

  for (const extra of [
    {token, amountMinor: 1},
    {token, currency: "TRY"},
    {token, paymentId: "fake"},
    {token, conversationId: "fake"},
    {token, basketId: "fake"},
  ]) {
    assert.throws(
      () =>
        validateDriverPlanCheckoutCallbackPayload(
          extra,
        ),
      reasonIs(
        "invalid_driver_plan_checkout_callback_payload",
      ),
    );
  }
});

test("valid verified success settles exactly one pass", async () => {
  const context =
    setup();

  const result =
    await handleDriverPlanCheckoutCallback(
      context.dependencies,
      {token},
    );

  assert.equal(
    result.status,
    "settled",
  );

  assert.equal(
    context.retriever.calls,
    1,
  );

  assert.deepEqual(
    context.retriever.lastInput,
    {
      conversationId,
      token,
    },
  );

  assert.equal(
    context.fake.count(
      "driverAccessPasses",
    ),
    1,
  );

  assert.equal(
    context.fake.count(
      "driverPlanPaymentSettlements",
    ),
    1,
  );
});

test("duplicate callback replays one deterministic settlement", async () => {
  const context =
    setup();

  const first =
    await handleDriverPlanCheckoutCallback(
      context.dependencies,
      {token},
    );

  const second =
    await handleDriverPlanCheckoutCallback(
      context.dependencies,
      {token},
    );

  assert.deepEqual(
    second,
    first,
  );

  assert.equal(
    context.fake.count(
      "driverAccessPasses",
    ),
    1,
  );

  assert.equal(
    context.fake.count(
      "driverPlanPaymentSettlements",
    ),
    1,
  );
});

test("provider correlation mismatches never settle", async () => {
  const cases:
    Array<Partial<DriverPlanPaymentRetrieveResult>> = [
      {token: "other-token"},
      {
        conversationId:
          "other-conversation",
      },
      {
        basketId:
          "c".repeat(64),
      },
      {currency: "USD"},
      {priceDecimal: "123.44"},
      {paidPriceDecimal: "123.44"},
    ];

  for (const overrides of cases) {
    const context =
      setup(
        paymentResult(
          overrides,
        ),
      );

    await assert.rejects(
      () =>
        handleDriverPlanCheckoutCallback(
          context.dependencies,
          {token},
        ),
    );

    assert.equal(
      context.fake.count(
        "driverAccessPasses",
      ),
      0,
    );

    assert.equal(
      context.fake.count(
        "driverPlanPaymentSettlements",
      ),
      0,
    );
  }
});

test("failed and fraud-rejected payments never grant access", async () => {
  for (const result of [
    paymentResult({
      paymentStatus: "FAILURE",
      fraudStatus: 1,
    }),
    paymentResult({
      fraudStatus: -1,
    }),
  ]) {
    const context =
      setup(result);

    const callback =
      await handleDriverPlanCheckoutCallback(
        context.dependencies,
        {token},
      );

    assert.equal(
      callback.status,
      "payment_failed",
    );

    assert.equal(
      context.fake.count(
        "driverAccessPasses",
      ),
      0,
    );

    assert.equal(
      context.fake.count(
        "driverPlanPaymentSettlements",
      ),
      0,
    );
  }
});

test("fraud review remains pending without entitlement", async () => {
  const context =
    setup(
      paymentResult({
        fraudStatus: 0,
      }),
    );

  const result =
    await handleDriverPlanCheckoutCallback(
      context.dependencies,
      {token},
    );

  assert.equal(
    result.status,
    "payment_review",
  );

  assert.equal(
    context.fake.count(
      "driverAccessPasses",
    ),
    0,
  );

  assert.equal(
    context.fake.count(
      "driverPlanPaymentSettlements",
    ),
    0,
  );
});

test("retrieve transport uncertainty fails closed", async () => {
  const context =
    setup();

  context.retriever.error =
    new DriverPlanPaymentProviderException(
      "unavailable",
      "provider_transport_failure",
    );

  await assert.rejects(
    () =>
      handleDriverPlanCheckoutCallback(
        context.dependencies,
        {token},
      ),
    reasonIs(
      "driver_plan_checkout_retrieve_unavailable",
    ),
  );

  assert.equal(
    context.fake.count(
      "driverAccessPasses",
    ),
    0,
  );

  assert.equal(
    context.fake.count(
      "driverPlanPaymentSettlements",
    ),
    0,
  );
});

test("unknown callback token never invokes provider", async () => {
  const context =
    setup();

  await assert.rejects(
    () =>
      handleDriverPlanCheckoutCallback(
        context.dependencies,
        {
          token:
            "unknown-token",
        },
      ),
    reasonIs(
      "driver_plan_checkout_callback_operation_not_found",
    ),
  );

  assert.equal(
    context.retriever.calls,
    0,
  );

  assert.equal(
    context.fake.count(
      "driverAccessPasses",
    ),
    0,
  );
});

test("failed and review callbacks persist authoritative operation outcomes", async () => {
  for (const current of [
    {
      result: paymentResult({
        paymentStatus: "FAILURE",
        fraudStatus: 1,
      }),
      expected: "payment_failed",
    },
    {
      result: paymentResult({
        fraudStatus: 0,
      }),
      expected: "payment_review",
    },
  ]) {
    const context =
      setup(current.result);

    await handleDriverPlanCheckoutCallback(
      context.dependencies,
      {token},
    );

    const operation =
      context.fake.get(
        `driverPlanPurchaseOperations/${operationId}`,
      );

    assert.ok(operation);

    assert.equal(
      operation.status,
      "pending",
    );

    assert.equal(
      operation.paymentOutcome,
      current.expected,
    );

    assert.ok(
      operation.paymentOutcomeUpdatedAt instanceof Timestamp,
    );

    assert.equal(
      (
        operation.paymentOutcomeUpdatedAt as Timestamp
      ).toMillis(),
      now.toMillis(),
    );
  }
});

test("payment review may fail later but payment failure remains terminal", async () => {
  const operationPath =
    `driverPlanPurchaseOperations/${operationId}`;

  const reviewContext =
    setup(
      paymentResult({
        fraudStatus: 0,
      }),
    );

  await handleDriverPlanCheckoutCallback(
    reviewContext.dependencies,
    {token},
  );

  const reviewedOperation =
    reviewContext.fake.get(
      operationPath,
    );

  assert.ok(reviewedOperation);
  assert.equal(
    reviewedOperation.paymentOutcome,
    "payment_review",
  );

  const failureContext =
    setup(
      paymentResult({
        paymentStatus: "FAILURE",
        fraudStatus: 1,
      }),
    );

  failureContext.fake.set(
    operationPath,
    {...reviewedOperation},
  );

  await handleDriverPlanCheckoutCallback(
    failureContext.dependencies,
    {token},
  );

  const failedOperation =
    failureContext.fake.get(
      operationPath,
    );

  assert.ok(failedOperation);

  assert.equal(
    failedOperation.paymentOutcome,
    "payment_failed",
  );

  const frozenTimestamp =
    Timestamp.fromMillis(
      now.toMillis() - 1000,
    );

  const reviewAfterFailureContext =
    setup(
      paymentResult({
        fraudStatus: 0,
      }),
    );

  reviewAfterFailureContext.fake.set(
    operationPath,
    {
      ...failedOperation,
      paymentOutcomeUpdatedAt:
        frozenTimestamp,
      updatedAt:
        frozenTimestamp,
    },
  );

  await handleDriverPlanCheckoutCallback(
    reviewAfterFailureContext.dependencies,
    {token},
  );

  const stillFailed =
    reviewAfterFailureContext.fake.get(
      operationPath,
    );

  assert.ok(stillFailed);

  assert.equal(
    stillFailed.paymentOutcome,
    "payment_failed",
  );

  assert.equal(
    (
      stillFailed.paymentOutcomeUpdatedAt as Timestamp
    ).toMillis(),
    frozenTimestamp.toMillis(),
  );
});

test("settled outcome cannot be downgraded by a later failed callback", async () => {
  const operationPath =
    `driverPlanPurchaseOperations/${operationId}`;

  const successfulContext =
    setup();

  const settledResult =
    await handleDriverPlanCheckoutCallback(
      successfulContext.dependencies,
      {token},
    );

  assert.equal(
    settledResult.status,
    "settled",
  );

  const settledOperation =
    successfulContext.fake.get(
      operationPath,
    );

  assert.ok(settledOperation);

  assert.equal(
    settledOperation.status,
    "settled",
  );

  assert.equal(
    settledOperation.paymentOutcome,
    "settled",
  );

  assert.ok(
    settledOperation.paymentOutcomeUpdatedAt instanceof Timestamp,
  );

  const settledOutcomeUpdatedAt =
    (
      settledOperation.paymentOutcomeUpdatedAt as Timestamp
    ).toMillis();

  const laterFailureContext =
    setup(
      paymentResult({
        paymentStatus: "FAILURE",
        fraudStatus: 1,
      }),
    );

  laterFailureContext.fake.set(
    operationPath,
    {...settledOperation},
  );

  await handleDriverPlanCheckoutCallback(
    laterFailureContext.dependencies,
    {token},
  );

  const afterFailure =
    laterFailureContext.fake.get(
      operationPath,
    );

  assert.ok(afterFailure);

  assert.equal(
    afterFailure.status,
    "settled",
  );

  assert.equal(
    afterFailure.paymentOutcome,
    "settled",
  );

  assert.equal(
    (
      afterFailure.paymentOutcomeUpdatedAt as Timestamp
    ).toMillis(),
    settledOutcomeUpdatedAt,
  );

  assert.equal(
    laterFailureContext.fake.count(
      "driverAccessPasses",
    ),
    0,
  );

  assert.equal(
    laterFailureContext.fake.count(
      "driverPlanPaymentSettlements",
    ),
    0,
  );
});

test("callback source persists failure and review without downgrading settlement", () => {
  const source =
    readFileSync(
      "src/driver-plan-checkout-callback-authority.ts",
      "utf8",
    );

  assert.match(
    source,
    /if\s*\(data\.status\s*===\s*"settled"\)\s*\{\s*return;\s*\}/u,
  );

  assert.match(
    source,
    /if\s*\(currentOutcome\s*===\s*"payment_failed"\)\s*\{\s*return;\s*\}/u,
  );

  assert.match(
    source,
    /await persistPaymentOutcome\(\s*dependencies,\s*operation\.purchaseOperationId,\s*"payment_failed",\s*\);/u,
  );

  assert.match(
    source,
    /await persistPaymentOutcome\(\s*dependencies,\s*operation\.purchaseOperationId,\s*"payment_review",\s*\);/u,
  );

  assert.match(
    source,
    /paymentOutcomeUpdatedAt:\s*now/u,
  );
});
