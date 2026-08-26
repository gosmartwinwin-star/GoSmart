/* eslint-disable max-len, require-jsdoc */

import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  getMyLatestDriverPlanPaymentStatusForActor,
  validateDriverPlanCheckoutRecoveryPayload,
} from "./driver-plan-checkout-recovery-read-authority.js";

type Data = Record<string, unknown>;

const purchaseOperationId =
  "a".repeat(64);

const pointerPath =
  "driverLatestPlanCheckoutOperations/driver-1";

const operationPath =
  `driverPlanPurchaseOperations/${purchaseOperationId}`;

const now =
  Timestamp.fromDate(
    new Date(
      "2026-01-15T10:00:00.000Z",
    ),
  );

class FakeSnapshot {
  constructor(
    private readonly value:
      Data | undefined,
  ) {}

  get exists() {
    return this.value !== undefined;
  }

  data() {
    return this.value;
  }
}

class FakeDocument {
  constructor(
    private readonly fake:
      FakeFirestore,
    private readonly path:
      string,
  ) {}

  async get() {
    this.fake.reads.push(
      this.path,
    );

    return new FakeSnapshot(
      this.fake.get(
        this.path,
      ),
    );
  }
}

class FakeCollection {
  constructor(
    private readonly fake:
      FakeFirestore,
    private readonly name:
      string,
  ) {}

  doc(id: string) {
    return new FakeDocument(
      this.fake,
      `${this.name}/${id}`,
    );
  }
}

class FakeFirestore {
  readonly reads:
    string[] = [];

  private readonly docs =
    new Map<string, Data>();

  collection(name: string) {
    return new FakeCollection(
      this,
      name,
    );
  }

  set(
    path: string,
    value: Data,
  ) {
    this.docs.set(
      path,
      {...value},
    );
  }

  get(path: string) {
    return this.docs.get(
      path,
    );
  }
}

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

const seedPointer = (
  fake: FakeFirestore,
  value: Data = {
    purchaseOperationId,
    updatedAt: now,
  },
) => {
  fake.set(
    pointerPath,
    value,
  );
};

const seedOperation = (
  fake: FakeFirestore,
  value: Data = {
    driverId: "driver-1",
    status: "pending",
    paymentOutcome: "pending",
  },
) => {
  fake.set(
    operationPath,
    value,
  );
};

const recover = (
  fake: FakeFirestore,
  payload: unknown = {},
) =>
  getMyLatestDriverPlanPaymentStatusForActor(
    {
      firestore:
        fake as unknown as Firestore,
      loadApprovedDriverId:
        async () => "driver-1",
    },
    "uid-1",
    payload,
  );

test("recovery payload accepts only the exact empty object", () => {
  assert.deepEqual(
    validateDriverPlanCheckoutRecoveryPayload(
      {},
    ),
    {},
  );

  for (const payload of [
    null,
    [],
    {purchaseOperationId},
    {unexpected: true},
  ]) {
    assert.throws(
      () =>
        validateDriverPlanCheckoutRecoveryPayload(
          payload,
        ),
      reasonIs(
        "invalid_driver_plan_checkout_recovery_payload",
      ),
    );
  }
});

test("no latest checkout pointer returns null payment status", async () => {
  const fake =
    new FakeFirestore();

  assert.deepEqual(
    await recover(fake),
    {
      paymentStatus: null,
    },
  );

  assert.deepEqual(
    fake.reads,
    [pointerPath],
  );
});

test("latest pointer recovers pending payment status", async () => {
  const fake =
    new FakeFirestore();

  seedPointer(fake);
  seedOperation(fake);

  assert.deepEqual(
    await recover(fake),
    {
      paymentStatus: {
        purchaseOperationId,
        paymentOutcome: "pending",
      },
    },
  );
});

test("latest pointer recovers payment review status", async () => {
  const fake =
    new FakeFirestore();

  seedPointer(fake);

  seedOperation(
    fake,
    {
      driverId: "driver-1",
      status: "pending",
      paymentOutcome:
        "payment_review",
    },
  );

  assert.deepEqual(
    await recover(fake),
    {
      paymentStatus: {
        purchaseOperationId,
        paymentOutcome:
          "payment_review",
      },
    },
  );
});

test("latest pointer recovers payment failure status", async () => {
  const fake =
    new FakeFirestore();

  seedPointer(fake);

  seedOperation(
    fake,
    {
      driverId: "driver-1",
      status: "pending",
      paymentOutcome:
        "payment_failed",
    },
  );

  assert.deepEqual(
    await recover(fake),
    {
      paymentStatus: {
        purchaseOperationId,
        paymentOutcome:
          "payment_failed",
      },
    },
  );
});

test("settled operation dominates prior payment outcome", async () => {
  const fake =
    new FakeFirestore();

  seedPointer(fake);

  seedOperation(
    fake,
    {
      driverId: "driver-1",
      status: "settled",
      paymentOutcome:
        "payment_failed",
    },
  );

  assert.deepEqual(
    await recover(fake),
    {
      paymentStatus: {
        purchaseOperationId,
        paymentOutcome:
          "settled",
      },
    },
  );
});

test("legacy pending operation without payment outcome remains recoverable", async () => {
  const fake =
    new FakeFirestore();

  seedPointer(fake);

  seedOperation(
    fake,
    {
      driverId: "driver-1",
      status: "pending",
    },
  );

  assert.deepEqual(
    await recover(fake),
    {
      paymentStatus: {
        purchaseOperationId,
        paymentOutcome:
          "pending",
      },
    },
  );
});

test("malformed latest checkout pointer fails closed", async () => {
  const malformedPointers: Data[] = [
    {
      purchaseOperationId,
    },
    {
      purchaseOperationId,
      updatedAt: now,
      extra: true,
    },
    {
      purchaseOperationId:
        "A".repeat(64),
      updatedAt: now,
    },
    {
      purchaseOperationId,
      updatedAt:
        "2026-01-15T10:00:00.000Z",
    },
  ];

  for (const malformed of malformedPointers) {
    const fake =
      new FakeFirestore();

    seedPointer(
      fake,
      malformed,
    );

    await assert.rejects(
      () => recover(fake),
      reasonIs(
        "driver_plan_checkout_recovery_pointer_invalid",
      ),
    );
  }
});

test("missing referenced purchase operation fails closed", async () => {
  const fake =
    new FakeFirestore();

  seedPointer(fake);

  await assert.rejects(
    () => recover(fake),
    reasonIs(
      "purchase_operation_not_found",
    ),
  );
});

test("foreign referenced purchase operation is not disclosed", async () => {
  const fake =
    new FakeFirestore();

  seedPointer(fake);

  seedOperation(
    fake,
    {
      driverId: "driver-other",
      status: "pending",
      paymentOutcome:
        "pending",
    },
  );

  await assert.rejects(
    () => recover(fake),
    reasonIs(
      "purchase_operation_not_found",
    ),
  );
});

test("malformed referenced purchase operation fails closed", async () => {
  const fake =
    new FakeFirestore();

  seedPointer(fake);

  seedOperation(
    fake,
    {
      driverId: "driver-1",
      status: "invalid",
      paymentOutcome:
        "pending",
    },
  );

  await assert.rejects(
    () => recover(fake),
    reasonIs(
      "purchase_operation_invalid",
    ),
  );
});

test("recovery response and source expose no provider or commercial artifacts", async () => {
  const fake =
    new FakeFirestore();

  seedPointer(fake);
  seedOperation(fake);

  const result =
    await recover(fake);

  assert.deepEqual(
    Object.keys(result),
    [
      "paymentStatus",
    ],
  );

  assert.ok(
    result.paymentStatus,
  );

  assert.deepEqual(
    Object.keys(
      result.paymentStatus,
    ).sort(),
    [
      "paymentOutcome",
      "purchaseOperationId",
    ],
  );

  const encoded =
    JSON.stringify(result);

  for (const forbidden of [
    "paymentPageUrl",
    "token",
    "conversationId",
    "paymentSettlementId",
    "passId",
    "amountMinor",
    "currency",
  ]) {
    assert.equal(
      encoded.includes(
        forbidden,
      ),
      false,
      `forbidden recovery field: ${forbidden}`,
    );
  }

  const source =
    readFileSync(
      "src/driver-plan-checkout-recovery-read-authority.ts",
      "utf8",
    );

  assert.doesNotMatch(
    source,
    /\.create\(|\.set\(|\.update\(|runTransaction/u,
  );

  assert.doesNotMatch(
    source,
    /paymentPageUrl|conversationId|checkoutToken|driverPlanPaymentSettlements|driverAccessPasses|amountMinor|currency/u,
  );
});

/* eslint-enable max-len, require-jsdoc */
