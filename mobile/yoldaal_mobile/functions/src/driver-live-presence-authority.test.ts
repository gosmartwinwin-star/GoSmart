/* eslint-disable require-jsdoc */
import assert from "node:assert/strict";
import test from "node:test";
import {
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  publishDriverLivePresence,
} from "./driver-live-presence-authority.js";

type SetCall = {
  reference: unknown;
  data: unknown;
  argumentCount: number;
};

class FakeTransaction {
  readonly setCalls: SetCall[] = [];

  set(
    reference: unknown,
    data: unknown,
    ...rest: unknown[]
  ): FakeTransaction {
    this.setCalls.push({
      reference,
      data,
      argumentCount:
        2 + rest.length,
    });

    return this;
  }
}

class FakeFirestore {
  readonly transaction =
    new FakeTransaction();

  runTransactionCalls = 0;
  collectionNames: string[] = [];
  documentIds: string[] = [];
  transactionFailure:
    Error | null = null;

  collection(name: string) {
    this.collectionNames.push(name);

    return {
      doc: (id: string) => {
        this.documentIds.push(id);

        return {
          path: `${name}/${id}`,
        };
      },
    };
  }

  async runTransaction<T>(
    operation: (
      transaction: Transaction,
    ) => Promise<T>,
  ): Promise<T> {
    this.runTransactionCalls++;

    if (this.transactionFailure !== null) {
      throw this.transactionFailure;
    }

    return operation(
      this.transaction as unknown as Transaction,
    );
  }
}

type InvocationTrace = {
  identityUids: string[];
  identityTransactions: unknown[];
  accessDriverIds: string[];
  accessTimes: Timestamp[];
  accessTransactions: unknown[];
};

type InvocationOverrides = {
  driverId?: string;
  now?: Timestamp;
  identityError?: HttpsError;
  accessError?: HttpsError;
};

const fixedNow =
  Timestamp.fromMillis(123456789);

const newTrace = (): InvocationTrace => ({
  identityUids: [],
  identityTransactions: [],
  accessDriverIds: [],
  accessTimes: [],
  accessTransactions: [],
});

const reasonIs = (
  expected: string,
) => (
  error: unknown,
): boolean => {
  assert.ok(
    error instanceof HttpsError,
  );

  assert.equal(
    (
      error.details as
        {reason?: string} | undefined
    )?.reason,
    expected,
  );

  return true;
};

const invoke = (
  fake: FakeFirestore,
  trace: InvocationTrace,
  payload: unknown = {
    latitude: 41.0082,
    longitude: 28.9784,
  },
  overrides:
    InvocationOverrides = {},
) => {
  const now =
    overrides.now ??
    fixedNow;

  return publishDriverLivePresence(
    {
      firestore:
        fake as unknown as Firestore,
      now:
        () => now,
      loadApprovedDriverIdInTransaction:
        async (
          _firestore,
          actorUid,
          transaction,
        ) => {
          trace.identityUids.push(
            actorUid,
          );
          trace.identityTransactions.push(
            transaction,
          );

          if (
            overrides.identityError !==
            undefined
          ) {
            throw overrides.identityError;
          }

          return (
            overrides.driverId ??
            "driver-1"
          );
        },
      requireDriverAccessInTransaction:
        async (input) => {
          trace.accessDriverIds.push(
            input.driverId,
          );
          trace.accessTimes.push(
            input.now,
          );
          trace.accessTransactions.push(
            input.transaction,
          );

          if (
            overrides.accessError !==
            undefined
          ) {
            throw overrides.accessError;
          }

          return "launchFree";
        },
    },
    "uid-1",
    payload,
  );
};

test(
  "valid payload writes exact record and returns only updatedAtMillis",
  async () => {
    const fake =
      new FakeFirestore();
    const trace =
      newTrace();

    const result =
      await invoke(fake, trace);

    assert.deepEqual(
      Object.keys(result),
      ["updatedAtMillis"],
    );

    assert.equal(
      result.updatedAtMillis,
      fixedNow.toMillis(),
    );

    assert.equal(
      fake.transaction.setCalls.length,
      1,
    );

    const data =
      fake.transaction.setCalls[0]
        .data as Record<string, unknown>;

    assert.deepEqual(
      Object.keys(data).sort(),
      [
        "driverId",
        "latitude",
        "longitude",
        "updatedAt",
      ],
    );

    assert.equal(
      data.driverId,
      "driver-1",
    );
    assert.equal(
      data.latitude,
      41.0082,
    );
    assert.equal(
      data.longitude,
      28.9784,
    );
    assert.equal(
      data.updatedAt,
      fixedNow,
    );
  },
);

test(
  "document path uses server-derived driver id",
  async () => {
    const fake =
      new FakeFirestore();
    const trace =
      newTrace();

    await invoke(
      fake,
      trace,
      undefined,
      {
        driverId:
          "driver-authoritative",
      },
    );

    assert.deepEqual(
      fake.collectionNames,
      ["driverLivePresences"],
    );

    assert.deepEqual(
      fake.documentIds,
      ["driver-authoritative"],
    );

    const reference =
      fake.transaction.setCalls[0]
        .reference as {path: string};

    assert.equal(
      reference.path,
      "driverLivePresences/driver-authoritative",
    );
  },
);

test(
  "timestamp dependency is shared by record and response",
  async () => {
    const fake =
      new FakeFirestore();
    const trace =
      newTrace();
    const now =
      Timestamp.fromMillis(987654321);

    const result =
      await invoke(
        fake,
        trace,
        undefined,
        {now},
      );

    const data =
      fake.transaction.setCalls[0]
        .data as Record<string, unknown>;

    assert.equal(
      data.updatedAt,
      now,
    );
    assert.equal(
      result.updatedAtMillis,
      now.toMillis(),
    );
  },
);

test(
  "identity loader runs inside transaction",
  async () => {
    const fake =
      new FakeFirestore();
    const trace =
      newTrace();

    await invoke(fake, trace);

    assert.deepEqual(
      trace.identityUids,
      ["uid-1"],
    );
    assert.equal(
      trace.identityTransactions[0],
      fake.transaction,
    );
  },
);

test(
  "access checker uses same driver id transaction and timestamp",
  async () => {
    const fake =
      new FakeFirestore();
    const trace =
      newTrace();

    await invoke(
      fake,
      trace,
      undefined,
      {
        driverId:
          "driver-access",
      },
    );

    assert.deepEqual(
      trace.accessDriverIds,
      ["driver-access"],
    );
    assert.equal(
      trace.accessTimes[0],
      fixedNow,
    );
    assert.equal(
      trace.accessTransactions[0],
      fake.transaction,
    );
  },
);

test(
  "transaction set uses no merge options",
  async () => {
    const fake =
      new FakeFirestore();
    const trace =
      newTrace();

    await invoke(fake, trace);

    assert.equal(
      fake.transaction.setCalls[0]
        .argumentCount,
      2,
    );
  },
);

test(
  "invalid B1 payload causes zero transaction and zero write",
  async () => {
    const fake =
      new FakeFirestore();
    const trace =
      newTrace();

    await assert.rejects(
      () =>
        invoke(
          fake,
          trace,
          {
            latitude: 41,
            longitude: 29,
            driverId:
              "client-injected",
          },
        ),
      reasonIs(
        "invalid_driver_live_location",
      ),
    );

    assert.equal(
      fake.runTransactionCalls,
      0,
    );
    assert.equal(
      fake.transaction.setCalls.length,
      0,
    );
  },
);

test(
  "identity HttpsError is preserved and causes zero write",
  async () => {
    const fake =
      new FakeFirestore();
    const trace =
      newTrace();

    const identityError =
      new HttpsError(
        "failed-precondition",
        "identity failed",
        {
          reason:
            "driver_profile_required",
        },
      );

    await assert.rejects(
      () =>
        invoke(
          fake,
          trace,
          undefined,
          {identityError},
        ),
      (error: unknown) =>
        error === identityError,
    );

    assert.equal(
      fake.transaction.setCalls.length,
      0,
    );
  },
);

test(
  "access HttpsError is preserved and causes zero write",
  async () => {
    const fake =
      new FakeFirestore();
    const trace =
      newTrace();

    const accessError =
      new HttpsError(
        "failed-precondition",
        "access failed",
        {
          reason:
            "driver_access_required",
        },
      );

    await assert.rejects(
      () =>
        invoke(
          fake,
          trace,
          undefined,
          {accessError},
        ),
      (error: unknown) =>
        error === accessError,
    );

    assert.equal(
      fake.transaction.setCalls.length,
      0,
    );
  },
);

test(
  "unknown transaction failure maps to safe persistence error",
  async () => {
    const fake =
      new FakeFirestore();
    const trace =
      newTrace();

    fake.transactionFailure =
      new Error(
        "raw firestore failure",
      );

    await assert.rejects(
      () => invoke(fake, trace),
      reasonIs(
        "driver_live_presence_persistence_failed",
      ),
    );

    assert.equal(
      fake.transaction.setCalls.length,
      0,
    );
  },
);

test(
  "result exposes no driver identity coordinates online or access data",
  async () => {
    const fake =
      new FakeFirestore();
    const trace =
      newTrace();

    const result =
      await invoke(fake, trace);

    assert.deepEqual(
      Object.keys(result),
      ["updatedAtMillis"],
    );

    assert.equal(
      "driverId" in result,
      false,
    );
    assert.equal(
      "latitude" in result,
      false,
    );
    assert.equal(
      "longitude" in result,
      false,
    );
    assert.equal(
      "online" in result,
      false,
    );
    assert.equal(
      "accessMode" in result,
      false,
    );
  },
);
/* eslint-enable require-jsdoc */
