/* eslint-disable max-len, require-jsdoc */
import assert from "node:assert/strict";
import {test} from "node:test";
import {
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {
  parsePersistedPassengerPushTarget,
  registerPassengerPushTarget,
  validateRegisterPassengerPushTargetPayload,
} from "./passenger-push-target-authority.js";

class FakePassengerPushFirestore {
  readonly writes =
    new Map<string, Record<string, unknown>>();

  failWrite = false;

  collection(name: string): {
    doc: (id: string) => {
      set: (
        value: Record<string, unknown>,
      ) => Promise<void>;
    };
  } {
    return {
      doc: (id: string) => ({
        set: async (
          value: Record<string, unknown>,
        ): Promise<void> => {
          if (this.failWrite) {
            throw new Error("write failed");
          }

          this.writes.set(
            `${name}/${id}`,
            value,
          );
        },
      }),
    };
  }

  asFirestore(): Firestore {
    return this as unknown as Firestore;
  }
}

const hasCode = (
  code: string,
) =>
  (error: unknown): boolean =>
    error instanceof HttpsError &&
    error.code === code;

test(
  "passenger push target payload accepts canonical Android and iOS values",
  () => {
    assert.deepEqual(
      validateRegisterPassengerPushTargetPayload({
        fid: "opaque-fid-0001",
        platform: "android",
      }),
      {
        fid: "opaque-fid-0001",
        platform: "android",
      },
    );

    assert.deepEqual(
      validateRegisterPassengerPushTargetPayload({
        fid: "opaque/fid+value=alpha",
        platform: "ios",
      }),
      {
        fid: "opaque/fid+value=alpha",
        platform: "ios",
      },
    );
  },
);

test(
  "passenger push target payload is exact and FID stays opaque and bounded",
  () => {
    assert.equal(
      validateRegisterPassengerPushTargetPayload({
        fid: "12345678",
        platform: "android",
      }).fid.length,
      8,
    );

    assert.equal(
      validateRegisterPassengerPushTargetPayload({
        fid: "x".repeat(512),
        platform: "ios",
      }).fid.length,
      512,
    );

    assert.throws(
      () =>
        validateRegisterPassengerPushTargetPayload({
          fid: "1234567",
          platform: "android",
        }),
      hasCode("invalid-argument"),
    );

    assert.throws(
      () =>
        validateRegisterPassengerPushTargetPayload({
          fid: "x".repeat(513),
          platform: "android",
        }),
      hasCode("invalid-argument"),
    );

    assert.throws(
      () =>
        validateRegisterPassengerPushTargetPayload({
          fid: "opaque fid",
          platform: "android",
        }),
      hasCode("invalid-argument"),
    );

    assert.throws(
      () =>
        validateRegisterPassengerPushTargetPayload({
          fid: "opaque-fid-0001",
          platform: "web",
        }),
      hasCode("invalid-argument"),
    );

    assert.throws(
      () =>
        validateRegisterPassengerPushTargetPayload({
          fid: "opaque-fid-0001",
          platform: "android",
          passengerId: "attacker",
        }),
      hasCode("invalid-argument"),
    );
  },
);

test(
  "persisted passenger target parser requires exact server-owned schema",
  () => {
    const updatedAt =
      Timestamp.fromMillis(
        1_700_000_000_000,
      );

    assert.deepEqual(
      parsePersistedPassengerPushTarget(
        "passenger-a",
        {
          passengerId: "passenger-a",
          fid: "opaque-fid-0001",
          platform: "android",
          updatedAt,
        },
      ),
      {
        passengerId: "passenger-a",
        fid: "opaque-fid-0001",
        platform: "android",
        updatedAt,
      },
    );

    assert.equal(
      parsePersistedPassengerPushTarget(
        "passenger-a",
        {
          passengerId: "passenger-b",
          fid: "opaque-fid-0001",
          platform: "android",
          updatedAt,
        },
      ),
      null,
    );

    assert.equal(
      parsePersistedPassengerPushTarget(
        "passenger-a",
        {
          passengerId: "passenger-a",
          fid: "opaque-fid-0001",
          platform: "android",
          updatedAt,
          extra: true,
        },
      ),
      null,
    );
  },
);

test(
  "registration writes one server-derived passenger target",
  async () => {
    const fake =
      new FakePassengerPushFirestore();

    const now =
      Timestamp.fromMillis(
        1_700_000_123_456,
      );

    const result =
      await registerPassengerPushTarget(
        {
          firestore: fake.asFirestore(),
          now: () => now,
        },
        "passenger-a",
        {
          fid: "opaque-fid-0001",
          platform: "android",
        },
      );

    assert.deepEqual(
      result,
      {
        updatedAtMillis: now.toMillis(),
      },
    );

    assert.deepEqual(
      fake.writes.get(
        "passengerPushTargets/passenger-a",
      ),
      {
        passengerId: "passenger-a",
        fid: "opaque-fid-0001",
        platform: "android",
        updatedAt: now,
      },
    );

    assert.equal(
      fake.writes.size,
      1,
    );
  },
);

test(
  "registration sanitizes persistence failure",
  async () => {
    const fake =
      new FakePassengerPushFirestore();

    fake.failWrite = true;

    await assert.rejects(
      registerPassengerPushTarget(
        {
          firestore: fake.asFirestore(),
        },
        "passenger-a",
        {
          fid: "opaque-fid-0001",
          platform: "android",
        },
      ),
      hasCode("unavailable"),
    );
  },
);
