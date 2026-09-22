import assert from "node:assert/strict";
import test from "node:test";

import {
  Timestamp,
  type Firestore,
} from "firebase-admin/firestore";

import {
  RideVoiceCallAuthorityError,
} from "./ride-voice-call-authority.js";

import {
  transitionStoredRideVoiceCallForActor,
  transitionStoredRideVoiceCallForSystem,
} from "./ride-voice-call-lifecycle-storage.js";

import {
  type RideVoiceCallState,
} from "./ride-voice-call-policy.js";

const rideId = "ride-lifecycle-1";
const passengerUid = "passenger-uid";
const driverUid = "driver-auth-uid";
const driverId = "driver-profile-1";
const callId =
  "rvc_0123456789abcdef0123456789abcdef";
const initialMillis = 1000;
const nowMillis = 2000;

type FakeDocument =
  Record<string, unknown>;

type FakeReference = Readonly<{
  path: string;
  collection: (
    name: string,
  ) => FakeCollection;
}>;

type FakeCollection = Readonly<{
  doc: (
    id: string,
  ) => FakeReference;
}>;

type FakeWrite = Readonly<{
  path: string;
  data: FakeDocument;
}>;

type FakeFirestore = Readonly<{
  documents: Map<string, FakeDocument>;
  reads: string[];
  updates: FakeWrite[];
  transactionCalls: {
    value: number;
  };
  collection: (
    name: string,
  ) => FakeCollection;
  runTransaction: <T>(
    action: (
      transaction: {
        get: (
          reference: FakeReference,
        ) => Promise<{
          exists: boolean;
          id: string;
          data: () => FakeDocument | undefined;
        }>;
        update: (
          reference: FakeReference,
          data: FakeDocument,
        ) => void;
      },
    ) => Promise<T>,
  ) => Promise<T>;
}>;

const makeReference = (
  path: string,
): FakeReference => ({
  path,
  collection: (
    name: string,
  ): FakeCollection =>
    makeCollection(
      `${path}/${name}`,
    ),
});

const makeCollection = (
  path: string,
): FakeCollection => ({
  doc: (
    id: string,
  ): FakeReference =>
    makeReference(
      `${path}/${id}`,
    ),
});

const referenceId = (
  path: string,
): string => {
  const parts =
    path.split("/");

  return (
    parts[parts.length - 1] ??
    ""
  );
};

const createFakeFirestore = (
  initial: Record<string, FakeDocument>,
): FakeFirestore => {
  const documents =
    new Map<string, FakeDocument>(
      Object.entries(initial),
    );

  const reads: string[] = [];
  const updates: FakeWrite[] = [];
  const transactionCalls = {
    value: 0,
  };

  return {
    documents,
    reads,
    updates,
    transactionCalls,
    collection: (
      name: string,
    ): FakeCollection =>
      makeCollection(name),
    runTransaction: async <T>(
      action: (
        transaction: {
          get: (
            reference: FakeReference,
          ) => Promise<{
            exists: boolean;
            id: string;
            data: () => FakeDocument | undefined;
          }>;
          update: (
            reference: FakeReference,
            data: FakeDocument,
          ) => void;
        },
      ) => Promise<T>,
    ): Promise<T> => {
      transactionCalls.value += 1;

      const transaction = {
        get: async (
          reference: FakeReference,
        ) => {
          reads.push(reference.path);

          const value =
            documents.get(
              reference.path,
            );

          return {
            exists: value !== undefined,
            id: referenceId(
              reference.path,
            ),
            data: () => value,
          };
        },
        update: (
          reference: FakeReference,
          data: FakeDocument,
        ): void => {
          updates.push({
            path: reference.path,
            data,
          });

          const current =
            documents.get(
              reference.path,
            );

          if (current === undefined) {
            throw new Error(
              "Fake update target is missing.",
            );
          }

          documents.set(
            reference.path,
            {
              ...current,
              ...data,
            },
          );
        },
      };

      return action(transaction);
    },
  };
};

const baseDocuments = (
  state: RideVoiceCallState = "ringing",
  callerUid = passengerUid,
  callerRole:
    "passenger" | "driver" = "passenger",
  calleeUid = driverUid,
  calleeRole:
    "passenger" | "driver" = "driver",
): Record<string, FakeDocument> => ({
  [`rides/${rideId}`]: {
    version: 7,
    status: "driverEnRoute",
    passengerId: passengerUid,
    driverId,
  },
  [`driverProfiles/${driverId}`]: {
    authUserId: driverUid,
  },
  [`rideVoiceActiveCalls/${rideId}`]: {
    callId,
    rideId,
    state,
    updatedAt:
      Timestamp.fromMillis(
        initialMillis,
      ),
  },
  [`rides/${rideId}/voiceCalls/${callId}`]: {
    callId,
    rideId,
    rideVersion: 6,
    state,
    caller: {
      uid: callerUid,
      role: callerRole,
    },
    callee: {
      uid: calleeUid,
      role: calleeRole,
    },
    createdAt:
      Timestamp.fromMillis(
        initialMillis,
      ),
    updatedAt:
      Timestamp.fromMillis(
        initialMillis,
      ),
  },
});

const dependencies = (
  fake: FakeFirestore,
) => ({
  firestore:
    fake as unknown as Firestore,
  nowMillis: () => nowMillis,
});

const expectAuthorityError = async (
  action: () => Promise<unknown>,
  code: RideVoiceCallAuthorityError["code"],
): Promise<void> => {
  await assert.rejects(
    action,
    (error: unknown) =>
      error instanceof
        RideVoiceCallAuthorityError &&
      error.code === code,
  );
};

const updateMillis = (
  value: unknown,
): number => {
  assert.ok(
    value instanceof Timestamp,
  );

  return value.toMillis();
};

test(
  "transition payload is exact before transaction",
  async () => {
    const fake =
      createFakeFirestore(
        baseDocuments(),
      );

    await expectAuthorityError(
      () =>
        transitionStoredRideVoiceCallForActor(
          dependencies(fake),
          passengerUid,
          {
            rideId,
            callId,
            toState: "cancelled",
            actorSide: "caller",
          },
        ),
      "invalid-argument",
    );

    assert.equal(
      fake.transactionCalls.value,
      0,
    );

    assert.deepEqual(
      fake.reads,
      [],
    );

    assert.deepEqual(
      fake.updates,
      [],
    );
  },
);

test(
  "caller can cancel ringing atomically",
  async () => {
    const fake =
      createFakeFirestore(
        baseDocuments(),
      );

    const result =
      await transitionStoredRideVoiceCallForActor(
        dependencies(fake),
        passengerUid,
        {
          rideId,
          callId,
          toState: "cancelled",
        },
      );

    assert.deepEqual(
      result,
      {
        rideId,
        callId,
        state: "cancelled",
        updatedAtMillis: nowMillis,
      },
    );

    assert.equal(
      fake.updates.length,
      2,
    );

    assert.equal(
      fake.updates[0]?.data.state,
      "cancelled",
    );

    assert.equal(
      fake.updates[1]?.data.state,
      "cancelled",
    );

    assert.equal(
      updateMillis(
        fake.updates[0]?.data.updatedAt,
      ),
      nowMillis,
    );

    assert.equal(
      updateMillis(
        fake.updates[1]?.data.updatedAt,
      ),
      nowMillis,
    );
  },
);

test(
  "callee can accept ringing",
  async () => {
    const fake =
      createFakeFirestore(
        baseDocuments(),
      );

    const result =
      await transitionStoredRideVoiceCallForActor(
        dependencies(fake),
        driverUid,
        {
          rideId,
          callId,
          toState: "accepted",
        },
      );

    assert.equal(
      result.state,
      "accepted",
    );

    assert.equal(
      fake.updates.length,
      2,
    );
  },
);

test(
  "ringing actor sides are bounded",
  async () => {
    const callerFake =
      createFakeFirestore(
        baseDocuments(),
      );

    await expectAuthorityError(
      () =>
        transitionStoredRideVoiceCallForActor(
          dependencies(callerFake),
          passengerUid,
          {
            rideId,
            callId,
            toState: "accepted",
          },
        ),
      "failed-precondition",
    );

    assert.equal(
      callerFake.updates.length,
      0,
    );

    const calleeFake =
      createFakeFirestore(
        baseDocuments(),
      );

    await expectAuthorityError(
      () =>
        transitionStoredRideVoiceCallForActor(
          dependencies(calleeFake),
          driverUid,
          {
            rideId,
            callId,
            toState: "cancelled",
          },
        ),
      "failed-precondition",
    );

    assert.equal(
      calleeFake.updates.length,
      0,
    );
  },
);

test(
  "outsider is denied before call authority reads",
  async () => {
    const fake =
      createFakeFirestore(
        baseDocuments(),
      );

    await expectAuthorityError(
      () =>
        transitionStoredRideVoiceCallForActor(
          dependencies(fake),
          "outsider-uid",
          {
            rideId,
            callId,
            toState: "cancelled",
          },
        ),
      "permission-denied",
    );

    assert.deepEqual(
      fake.reads,
      [
        `rides/${rideId}`,
        `driverProfiles/${driverId}`,
      ],
    );

    assert.equal(
      fake.updates.length,
      0,
    );
  },
);

test(
  "participants can progress connection lifecycle",
  async () => {
    const cases:
      ReadonlyArray<
        Readonly<{
          from: RideVoiceCallState;
          to: RideVoiceCallState;
        }>
      > = [
        {
          from: "accepted",
          to: "connecting",
        },
        {
          from: "connecting",
          to: "active",
        },
        {
          from: "active",
          to: "ended",
        },
      ];

    for (const item of cases) {
      const fake =
        createFakeFirestore(
          baseDocuments(
            item.from,
          ),
        );

      const result =
        await transitionStoredRideVoiceCallForActor(
          dependencies(fake),
          passengerUid,
          {
            rideId,
            callId,
            toState: item.to,
          },
        );

      assert.equal(
        result.state,
        item.to,
      );

      assert.equal(
        fake.updates.length,
        2,
      );
    }
  },
);

test(
  "system owns missed and failed transitions",
  async () => {
    const actorFake =
      createFakeFirestore(
        baseDocuments(),
      );

    await expectAuthorityError(
      () =>
        transitionStoredRideVoiceCallForActor(
          dependencies(actorFake),
          passengerUid,
          {
            rideId,
            callId,
            toState: "missed",
          },
        ),
      "failed-precondition",
    );

    const missedFake =
      createFakeFirestore(
        baseDocuments(),
      );

    const missed =
      await transitionStoredRideVoiceCallForSystem(
        dependencies(missedFake),
        {
          rideId,
          callId,
          toState: "missed",
        },
      );

    assert.equal(
      missed.state,
      "missed",
    );

    const failedFake =
      createFakeFirestore(
        baseDocuments(
          "active",
        ),
      );

    const failed =
      await transitionStoredRideVoiceCallForSystem(
        dependencies(failedFake),
        {
          rideId,
          callId,
          toState: "failed",
        },
      );

    assert.equal(
      failed.state,
      "failed",
    );
  },
);

test(
  "terminal call states are immutable",
  async () => {
    const fake =
      createFakeFirestore(
        baseDocuments(
          "ended",
        ),
      );

    await expectAuthorityError(
      () =>
        transitionStoredRideVoiceCallForActor(
          dependencies(fake),
          passengerUid,
          {
            rideId,
            callId,
            toState: "active",
          },
        ),
      "failed-precondition",
    );

    assert.equal(
      fake.updates.length,
      0,
    );
  },
);

test(
  "active pointer absence or mismatch fails closed",
  async () => {
    const missing =
      baseDocuments();

    delete missing[
      `rideVoiceActiveCalls/${rideId}`
    ];

    const missingFake =
      createFakeFirestore(missing);

    await expectAuthorityError(
      () =>
        transitionStoredRideVoiceCallForActor(
          dependencies(missingFake),
          passengerUid,
          {
            rideId,
            callId,
            toState: "cancelled",
          },
        ),
      "not-found",
    );

    const mismatch =
      baseDocuments();

    mismatch[
      `rideVoiceActiveCalls/${rideId}`
    ] = {
      callId:
        "rvc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      rideId,
      state: "ringing",
      updatedAt:
        Timestamp.fromMillis(
          initialMillis,
        ),
    };

    const mismatchFake =
      createFakeFirestore(mismatch);

    await expectAuthorityError(
      () =>
        transitionStoredRideVoiceCallForActor(
          dependencies(mismatchFake),
          passengerUid,
          {
            rideId,
            callId,
            toState: "cancelled",
          },
        ),
      "data-invalid",
    );

    assert.equal(
      mismatchFake.updates.length,
      0,
    );
  },
);

test(
  "stored call absence or state mismatch fails closed",
  async () => {
    const missing =
      baseDocuments();

    delete missing[
      `rides/${rideId}/voiceCalls/${callId}`
    ];

    const missingFake =
      createFakeFirestore(missing);

    await expectAuthorityError(
      () =>
        transitionStoredRideVoiceCallForActor(
          dependencies(missingFake),
          passengerUid,
          {
            rideId,
            callId,
            toState: "cancelled",
          },
        ),
      "not-found",
    );

    const mismatch =
      baseDocuments();

    const callPath =
      `rides/${rideId}/voiceCalls/${callId}`;

    mismatch[callPath] = {
      ...mismatch[callPath],
      state: "accepted",
    };

    const mismatchFake =
      createFakeFirestore(mismatch);

    await expectAuthorityError(
      () =>
        transitionStoredRideVoiceCallForActor(
          dependencies(mismatchFake),
          passengerUid,
          {
            rideId,
            callId,
            toState: "cancelled",
          },
        ),
      "data-invalid",
    );

    assert.equal(
      mismatchFake.updates.length,
      0,
    );
  },
);

test(
  "stored participants must match authoritative ride",
  async () => {
    const fake =
      createFakeFirestore(
        baseDocuments(
          "ringing",
          passengerUid,
          "passenger",
          "foreign-driver",
          "driver",
        ),
      );

    await expectAuthorityError(
      () =>
        transitionStoredRideVoiceCallForActor(
          dependencies(fake),
          passengerUid,
          {
            rideId,
            callId,
            toState: "cancelled",
          },
        ),
      "data-invalid",
    );

    assert.equal(
      fake.updates.length,
      0,
    );
  },
);

test(
  "one transaction preserves exact authority read order",
  async () => {
    const fake =
      createFakeFirestore(
        baseDocuments(),
      );

    await transitionStoredRideVoiceCallForActor(
      dependencies(fake),
      passengerUid,
      {
        rideId,
        callId,
        toState: "cancelled",
      },
    );

    assert.equal(
      fake.transactionCalls.value,
      1,
    );

    assert.deepEqual(
      fake.reads,
      [
        `rides/${rideId}`,
        `driverProfiles/${driverId}`,
        `rideVoiceActiveCalls/${rideId}`,
        `rides/${rideId}/voiceCalls/${callId}`,
      ],
    );

    assert.deepEqual(
      fake.updates.map(
        (item) => item.path,
      ),
      [
        `rides/${rideId}/voiceCalls/${callId}`,
        `rideVoiceActiveCalls/${rideId}`,
      ],
    );

    assert.equal(
      updateMillis(
        fake.updates[0]?.data.updatedAt,
      ),
      updateMillis(
        fake.updates[1]?.data.updatedAt,
      ),
    );
  },
);
