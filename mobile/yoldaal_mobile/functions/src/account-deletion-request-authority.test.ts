import assert from "node:assert/strict";
import test from "node:test";

import type {Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {
  requestAccountDeletionForUser,
  validateAccountDeletionRequestPayload,
} from "./account-deletion-request-authority.js";

type StoredDocument = Record<string, unknown>;

const fakeFirestore = (
  initial?: StoredDocument,
) => {
  let stored = initial;
  let writes = 0;

  const documentReference = {
    id: "user-a",
    path: "accountDeletionRequests/user-a",
  };

  const firestore = {
    collection(name: string) {
      assert.equal(
        name,
        "accountDeletionRequests",
      );

      return {
        doc(uid: string) {
          assert.equal(uid, "user-a");
          return documentReference;
        },
      };
    },

    async runTransaction<T>(
      callback: (transaction: {
        get: (
          reference: unknown,
        ) => Promise<{
          exists: boolean;
          data: () => StoredDocument | undefined;
        }>;
        set: (
          reference: unknown,
          data: StoredDocument,
        ) => void;
      }) => Promise<T>,
    ): Promise<T> {
      const transaction = {
        async get(reference: unknown) {
          assert.equal(
            reference,
            documentReference,
          );

          return {
            exists: stored !== undefined,
            data: () => stored,
          };
        },

        set(
          reference: unknown,
          data: StoredDocument,
        ) {
          assert.equal(
            reference,
            documentReference,
          );

          writes += 1;
          stored = data;
        },
      };

      return callback(transaction);
    },
  } as unknown as Firestore;

  return {
    firestore,
    stored: () => stored,
    writes: () => writes,
  };
};

test(
  "payload accepts only null, undefined, or empty object",
  () => {
    assert.doesNotThrow(
      () => validateAccountDeletionRequestPayload(null),
    );

    assert.doesNotThrow(
      () => validateAccountDeletionRequestPayload(undefined),
    );

    assert.doesNotThrow(
      () => validateAccountDeletionRequestPayload({}),
    );

    for (
      const invalid of [
        "user-a",
        1,
        [],
        {uid: "user-a"},
        {userId: "user-a"},
        {authUid: "user-a"},
      ]
    ) {
      assert.throws(
        () =>
          validateAccountDeletionRequestPayload(
            invalid,
          ),
        (error: unknown) =>
          error instanceof HttpsError &&
          error.code === "invalid-argument",
      );
    }
  },
);

test(
  "first request writes only authenticated uid authority",
  async () => {
    const fake = fakeFirestore();

    const result =
      await requestAccountDeletionForUser(
        {firestore: fake.firestore},
        "user-a",
        {},
      );

    assert.deepEqual(
      result,
      {
        status: "requested",
        alreadyRequested: false,
      },
    );

    assert.equal(fake.writes(), 1);

    const stored = fake.stored();

    assert.equal(
      stored?.authUid,
      "user-a",
    );

    assert.equal(
      stored?.status,
      "requested",
    );

    assert.equal(
      stored?.source,
      "in_app",
    );

    assert.ok(stored?.requestedAt);
    assert.ok(stored?.updatedAt);

    assert.equal(
      Object.prototype.hasOwnProperty.call(
        stored,
        "phoneNumber",
      ),
      false,
    );
  },
);

test(
  "repeated request is idempotent and performs no second write",
  async () => {
    const fake = fakeFirestore({
      authUid: "user-a",
      status: "requested",
      source: "in_app",
      requestedAt: "existing",
      updatedAt: "existing",
    });

    const result =
      await requestAccountDeletionForUser(
        {firestore: fake.firestore},
        "user-a",
        null,
      );

    assert.deepEqual(
      result,
      {
        status: "requested",
        alreadyRequested: true,
      },
    );

    assert.equal(fake.writes(), 0);
  },
);

test(
  "malformed existing request fails closed",
  async () => {
    const fake = fakeFirestore({
      authUid: "other-user",
      status: "requested",
      source: "in_app",
    });

    await assert.rejects(
      requestAccountDeletionForUser(
        {firestore: fake.firestore},
        "user-a",
        {},
      ),
      (error: unknown) =>
        error instanceof HttpsError &&
        error.code === "failed-precondition",
    );
  },
);
