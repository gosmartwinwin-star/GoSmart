/* eslint-disable max-len, require-jsdoc */
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  getDriverPlanPaymentStatusForActor,
  validateDriverPlanPaymentStatusReadPayload,
} from "./driver-plan-payment-status-read-authority.js";

type Data = Record<string, unknown>;

const purchaseOperationId =
  "a".repeat(64);

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
    this.fake.reads += 1;

    return new FakeSnapshot(
      this.fake.get(this.path),
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
  private readonly documents =
    new Map<string, Data>();

  reads = 0;

  collection(name: string) {
    return new FakeCollection(
      this,
      name,
    );
  }

  set(
    path: string,
    data: Data,
  ) {
    this.documents.set(
      path,
      {...data},
    );
  }

  get(path: string) {
    return this.documents.get(path);
  }
}

const firestoreOf = (
  fake: FakeFirestore,
): Firestore =>
  fake as unknown as Firestore;

const reasonIs = (
  expected: string,
) => (error: unknown): boolean => {
  if (!(error instanceof HttpsError)) {
    return false;
  }

  return (
    error.details as
      Record<string, unknown> |
      undefined
  )?.reason === expected;
};

const seedOperation = (
  fake: FakeFirestore,
  data: Data,
) => {
  fake.set(
    `driverPlanPurchaseOperations/${purchaseOperationId}`,
    data,
  );
};

const readStatus = async (
  fake: FakeFirestore,
  approvedDriverId:
    string = "driver-1",
) =>
  getDriverPlanPaymentStatusForActor(
    {
      firestore:
        firestoreOf(fake),
      loadApprovedDriverId:
        async (
          actualFirestore,
          actorUid,
        ) => {
          assert.equal(
            actualFirestore,
            firestoreOf(fake),
          );

          assert.equal(
            actorUid,
            "uid-1",
          );

          return approvedDriverId;
        },
    },
    "uid-1",
    {purchaseOperationId},
  );

test("status read payload accepts only exact lowercase purchaseOperationId", () => {
  assert.deepEqual(
    validateDriverPlanPaymentStatusReadPayload({
      purchaseOperationId,
    }),
    {purchaseOperationId},
  );

  for (const payload of [
    null,
    {},
    {
      purchaseOperationId:
        "A".repeat(64),
    },
    {
      purchaseOperationId:
        "a".repeat(63),
    },
    {
      purchaseOperationId,
      driverId: "driver-1",
    },
  ]) {
    assert.throws(
      () =>
        validateDriverPlanPaymentStatusReadPayload(
          payload,
        ),
    );
  }
});

test("owner receives authoritative outcome with legacy fallbacks", async () => {
  const cases:
    Array<{
      status: string;
      paymentOutcome?: string;
      expected:
        | "pending"
        | "payment_failed"
        | "payment_review"
        | "settled";
    }> = [
      {
        status: "pending",
        expected: "pending",
      },
      {
        status: "pending",
        paymentOutcome: "pending",
        expected: "pending",
      },
      {
        status: "pending",
        paymentOutcome:
          "payment_review",
        expected:
          "payment_review",
      },
      {
        status: "pending",
        paymentOutcome:
          "payment_failed",
        expected:
          "payment_failed",
      },
      {
        status: "settled",
        expected: "settled",
      },
      {
        status: "settled",
        paymentOutcome:
          "payment_failed",
        expected: "settled",
      },
    ];

  for (const current of cases) {
    const fake =
      new FakeFirestore();

    const operation: Data = {
      driverId: "driver-1",
      status: current.status,
      token: "must-not-leak",
      conversationId:
        "must-not-leak",
      paymentPageUrl:
        "https://example.test/private",
      paymentId: "must-not-leak",
      paymentSettlementId:
        "must-not-leak",
      passId: "must-not-leak",
      amountMinor: 999,
      currency: "TRY",
    };

    if (
      current.paymentOutcome !==
      undefined
    ) {
      operation.paymentOutcome =
        current.paymentOutcome;
    }

    seedOperation(
      fake,
      operation,
    );

    const result =
      await readStatus(fake);

    assert.deepEqual(
      result,
      {
        purchaseOperationId,
        paymentOutcome:
          current.expected,
      },
    );

    assert.deepEqual(
      Object.keys(result).sort(),
      [
        "paymentOutcome",
        "purchaseOperationId",
      ],
    );
  }
});

test("foreign operation is hidden behind not-found", async () => {
  const fake =
    new FakeFirestore();

  seedOperation(
    fake,
    {
      driverId: "driver-other",
      status: "pending",
      paymentOutcome:
        "payment_review",
    },
  );

  await assert.rejects(
    () =>
      readStatus(
        fake,
        "driver-1",
      ),
    reasonIs(
      "purchase_operation_not_found",
    ),
  );
});

test("driver approval failure stops before operation lookup", async () => {
  const fake =
    new FakeFirestore();

  seedOperation(
    fake,
    {
      driverId: "driver-1",
      status: "pending",
    },
  );

  const identityFailure =
    new HttpsError(
      "permission-denied",
      "Driver is not approved.",
      {
        reason:
          "driver_profile_not_approved",
      },
    );

  await assert.rejects(
    () =>
      getDriverPlanPaymentStatusForActor(
        {
          firestore:
            firestoreOf(fake),
          loadApprovedDriverId:
            async () => {
              throw identityFailure;
            },
        },
        "uid-unapproved",
        {purchaseOperationId},
      ),
    (error: unknown) =>
      error === identityFailure,
  );

  assert.equal(
    fake.reads,
    0,
  );
});

test("malformed operation state fails closed", async () => {
  for (const operation of [
    {
      driverId: "driver-1",
      status: "unexpected",
    },
    {
      driverId: "driver-1",
      status: "pending",
      paymentOutcome:
        "unexpected",
    },
    {
      driverId: "",
      status: "pending",
    },
  ]) {
    const fake =
      new FakeFirestore();

    seedOperation(
      fake,
      operation,
    );

    await assert.rejects(
      () => readStatus(fake),
      reasonIs(
        "purchase_operation_invalid",
      ),
    );
  }
});

test("missing purchase operation uses the same non-disclosing not-found surface", async () => {
  const fake =
    new FakeFirestore();

  await assert.rejects(
    () => readStatus(fake),
    reasonIs(
      "purchase_operation_not_found",
    ),
  );
});

test("pending operation cannot claim a persisted settled outcome", async () => {
  const fake =
    new FakeFirestore();

  seedOperation(
    fake,
    {
      driverId: "driver-1",
      status: "pending",
      paymentOutcome: "settled",
    },
  );

  await assert.rejects(
    () => readStatus(fake),
    reasonIs(
      "purchase_operation_invalid",
    ),
  );
});

test("status read authority has no settlement or entitlement mutation", () => {
  const source =
    readFileSync(
      "src/driver-plan-payment-status-read-authority.ts",
      "utf8",
    );

  assert.doesNotMatch(
    source,
    /\.create\(|\.set\(|\.update\(|runTransaction|driverPlanPaymentSettlements|driverAccessPasses/u,
  );

  assert.doesNotMatch(
    source,
    /token|conversationId|paymentPageUrl|paymentSettlementId|passId|amountMinor|currency/u,
  );
});
/* eslint-enable max-len, require-jsdoc */
