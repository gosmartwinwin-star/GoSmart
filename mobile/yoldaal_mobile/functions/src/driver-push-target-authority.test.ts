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
  parsePersistedDriverPushTarget,
  registerDriverPushTarget,
  validateRegisterDriverPushTargetPayload,
} from "./driver-push-target-authority.js";

class FakeTransaction {
  readonly calls:
    Array<{
      path: string;
      data: unknown;
    }> = [];

  set(
    reference: unknown,
    data: unknown,
  ): FakeTransaction {
    this.calls.push({
      path:
        (
          reference as
            {path: string}
        ).path,
      data,
    });

    return this;
  }
}

class FakeFirestore {
  readonly transaction =
    new FakeTransaction();

  async runTransaction<T>(
    operation: (
      transaction: Transaction,
    ) => Promise<T>,
  ): Promise<T> {
    return operation(
      this.transaction as
        unknown as Transaction,
    );
  }

  collection(name: string) {
    return {
      doc: (driverId: string) => ({
        path:
          `${name}/${driverId}`,
      }),
    };
  }
}

const fixedNow =
  Timestamp.fromMillis(
    1_700_000_000_000,
  );

const laterNow =
  Timestamp.fromMillis(
    1_700_000_001_000,
  );

const reasonIs = (
  reason: string,
) => (
  error: unknown,
): boolean => {
  assert.ok(
    error instanceof HttpsError,
  );

  assert.equal(
    (
      error.details as
        {reason?: string} |
        undefined
    )?.reason,
    reason,
  );

  return true;
};

const dependenciesFor = (
  firestore: FakeFirestore,
  now = fixedNow,
) => ({
  firestore:
    firestore as
      unknown as Firestore,
  now:
    () => now,
  loadApprovedDriverIdInTransaction:
    async (
      _firestore: Firestore,
      uid: string,
    ) => {
      assert.equal(
        uid,
        "uid-1",
      );

      return "driver-1";
    },
  requireDriverAccessInTransaction:
    async (
      input: {
        driverId: string;
        now: Timestamp;
      },
    ) => {
      assert.equal(
        input.driverId,
        "driver-1",
      );

      assert.equal(
        input.now,
        now,
      );

      return "launchFree" as const;
    },
});

test(
  "push target payload accepts canonical FID",
  () => {
    assert.deepEqual(
      validateRegisterDriverPushTargetPayload({
        fid:
          "cR4Vv5T6u7W8x9Y0z1_A-b",
        platform:
          "android",
      }),
      {
        fid:
          "cR4Vv5T6u7W8x9Y0z1_A-b",
        platform:
          "android",
      },
    );
  },
);

test(
  "push target payload rejects extra fields",
  () => {
    assert.throws(
      () =>
        validateRegisterDriverPushTargetPayload({
          fid:
            "cR4Vv5T6u7W8x9Y0z1_A-b",
          platform:
            "ios",
          token:
            "forbidden",
        }),
      reasonIs(
        "driver_push_payload_invalid",
      ),
    );
  },
);

test(
  "push target payload treats non-whitespace FID as opaque",
  () => {
    const fid =
      "opaque/fid+value=alpha";

    assert.deepEqual(
      validateRegisterDriverPushTargetPayload({
        fid,
        platform:
          "android",
      }),
      {
        fid,
        platform:
          "android",
      },
    );
  },
);

test(
  "push target payload accepts exact 512 character FID",
  () => {
    const fid =
      "a".repeat(512);

    assert.equal(
      validateRegisterDriverPushTargetPayload({
        fid,
        platform:
          "ios",
      }).fid,
      fid,
    );
  },
);

test(
  "push target payload rejects FID shorter than eight",
  () => {
    assert.throws(
      () =>
        validateRegisterDriverPushTargetPayload({
          fid:
            "a".repeat(7),
          platform:
            "android",
        }),
      reasonIs(
        "driver_push_fid_invalid",
      ),
    );
  },
);

test(
  "push target payload rejects surrounding whitespace",
  () => {
    assert.throws(
      () =>
        validateRegisterDriverPushTargetPayload({
          fid:
            " abcdefgh",
          platform:
            "ios",
        }),
      reasonIs(
        "driver_push_fid_invalid",
      ),
    );
  },
);

test(
  "push target payload rejects embedded whitespace",
  () => {
    assert.throws(
      () =>
        validateRegisterDriverPushTargetPayload({
          fid:
            "abcd efgh",
          platform:
            "android",
        }),
      reasonIs(
        "driver_push_fid_invalid",
      ),
    );
  },
);

test(
  "push target payload rejects FID longer than 512",
  () => {
    assert.throws(
      () =>
        validateRegisterDriverPushTargetPayload({
          fid:
            "a".repeat(513),
          platform:
            "ios",
        }),
      reasonIs(
        "driver_push_fid_invalid",
      ),
    );
  },
);
test(
  "persisted push target parser accepts exact bounded record",
  () => {
    assert.deepEqual(
      parsePersistedDriverPushTarget(
        "driver-1",
        {
          driverId:
            "driver-1",
          fid:
            "opaque/fid+value=alpha",
          platform:
            "android",
          updatedAt:
            fixedNow,
        },
      ),
      {
        driverId:
          "driver-1",
        fid:
          "opaque/fid+value=alpha",
        platform:
          "android",
        updatedAt:
          fixedNow,
      },
    );
  },
);

test(
  "persisted push target parser rejects identity mismatch",
  () => {
    assert.equal(
      parsePersistedDriverPushTarget(
        "driver-1",
        {
          driverId:
            "driver-2",
          fid:
            "opaque/fid+value=alpha",
          platform:
            "ios",
          updatedAt:
            fixedNow,
        },
      ),
      null,
    );

    assert.equal(
      parsePersistedDriverPushTarget(
        " driver-1",
        {
          driverId:
            " driver-1",
          fid:
            "opaque/fid+value=alpha",
          platform:
            "ios",
          updatedAt:
            fixedNow,
        },
      ),
      null,
    );
  },
);

test(
  "persisted push target parser rejects malformed fields",
  () => {
    assert.equal(
      parsePersistedDriverPushTarget(
        "driver-1",
        {
          driverId:
            "driver-1",
          fid:
            "short",
          platform:
            "android",
          updatedAt:
            fixedNow,
        },
      ),
      null,
    );

    assert.equal(
      parsePersistedDriverPushTarget(
        "driver-1",
        {
          driverId:
            "driver-1",
          fid:
            "opaque/fid+value=alpha",
          platform:
            "web",
          updatedAt:
            fixedNow,
        },
      ),
      null,
    );

    assert.equal(
      parsePersistedDriverPushTarget(
        "driver-1",
        {
          driverId:
            "driver-1",
          fid:
            "opaque/fid+value=alpha",
          platform:
            "android",
          updatedAt:
            fixedNow.toMillis(),
        },
      ),
      null,
    );
  },
);

test(
  "persisted push target parser rejects missing or extra fields",
  () => {
    assert.equal(
      parsePersistedDriverPushTarget(
        "driver-1",
        {
          driverId:
            "driver-1",
          fid:
            "opaque/fid+value=alpha",
          platform:
            "android",
        },
      ),
      null,
    );

    assert.equal(
      parsePersistedDriverPushTarget(
        "driver-1",
        {
          driverId:
            "driver-1",
          fid:
            "opaque/fid+value=alpha",
          platform:
            "android",
          updatedAt:
            fixedNow,
          token:
            "forbidden",
        },
      ),
      null,
    );
  },
);

test(
  "persisted push target parser rejects non-record values",
  () => {
    for (
      const value of [
        null,
        [],
        "target",
        42,
      ]
    ) {
      assert.equal(
        parsePersistedDriverPushTarget(
          "driver-1",
          value,
        ),
        null,
      );
    }
  },
);
test(
  "registration writes one bounded server driver target",
  async () => {
    const firestore =
      new FakeFirestore();

    const result =
      await registerDriverPushTarget(
        dependenciesFor(
          firestore,
        ),
        "uid-1",
        {
          fid:
            "cR4Vv5T6u7W8x9Y0z1_A-b",
          platform:
            "ios",
        },
      );

    assert.deepEqual(
      result,
      {
        updatedAtMillis:
          fixedNow.toMillis(),
      },
    );

    assert.equal(
      firestore.transaction
        .calls.length,
      1,
    );

    assert.deepEqual(
      firestore.transaction.calls[0],
      {
        path:
          "driverPushTargets/driver-1",
        data: {
          driverId:
            "driver-1",
          fid:
            "cR4Vv5T6u7W8x9Y0z1_A-b",
          platform:
            "ios",
          updatedAt:
            fixedNow,
        },
      },
    );
  },
);

test(
  "later FID replaces the same bounded driver target path",
  async () => {
    const firestore =
      new FakeFirestore();

    await registerDriverPushTarget(
      dependenciesFor(
        firestore,
        fixedNow,
      ),
      "uid-1",
      {
        fid:
          "cR4Vv5T6u7W8x9Y0z1_A-b",
        platform:
          "android",
      },
    );

    await registerDriverPushTarget(
      dependenciesFor(
        firestore,
        laterNow,
      ),
      "uid-1",
      {
        fid:
          "dS5Ww6U7v8X9y0Z1a2_B-c",
        platform:
          "ios",
      },
    );

    assert.equal(
      firestore.transaction
        .calls.length,
      2,
    );

    assert.equal(
      firestore.transaction
        .calls[0]?.path,
      "driverPushTargets/driver-1",
    );

    assert.equal(
      firestore.transaction
        .calls[1]?.path,
      "driverPushTargets/driver-1",
    );

    assert.deepEqual(
      firestore.transaction
        .calls[1]?.data,
      {
        driverId:
          "driver-1",
        fid:
          "dS5Ww6U7v8X9y0Z1a2_B-c",
        platform:
          "ios",
        updatedAt:
          laterNow,
      },
    );
  },
);

test(
  "driver access failure remains authoritative",
  async () => {
    const firestore =
      new FakeFirestore();

    await assert.rejects(
      registerDriverPushTarget(
        {
          firestore:
            firestore as
              unknown as Firestore,
          loadApprovedDriverIdInTransaction:
            async () =>
              "driver-1",
          requireDriverAccessInTransaction:
            async () => {
              throw new HttpsError(
                "failed-precondition",
                "denied",
                {
                  reason:
                    "subscription_required",
                },
              );
            },
        },
        "uid-1",
        {
          fid:
            "cR4Vv5T6u7W8x9Y0z1_A-b",
          platform:
            "android",
        },
      ),
      reasonIs(
        "subscription_required",
      ),
    );
  },
);
