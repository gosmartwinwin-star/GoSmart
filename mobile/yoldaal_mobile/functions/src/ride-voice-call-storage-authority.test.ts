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
  createStoredRideVoiceCallForActor,
} from "./ride-voice-call-storage-authority.js";

const rideId = "ride-storage-1";
const passengerUid = "passenger-uid";
const driverUid = "driver-auth-uid";
const driverId = "driver-profile-1";

const callId =
  "rvc_0123456789abcdef0123456789abcdef";

const nowMillis =
  1_700_000_000_000;

type FakeDocument = Record<string, unknown>;

/** Minimal fake Firestore document reference for storage tests. */
class FakeDocumentReference {
  readonly id: string;
  readonly path: string;
  private readonly firestore: FakeFirestore;

  /**
   * Creates a path-bound fake Firestore reference.
   * @param {FakeFirestore} firestore Fake Firestore owner.
   * @param {string} path Canonical fake document path.
   */
  constructor(
    firestore: FakeFirestore,
    path: string,
  ) {
    this.firestore = firestore;
    this.path = path;
    const parts =
      path.split("/");

    this.id =
      parts[parts.length - 1] ?? "";
  }

  /**
   * Creates a child fake collection reference.
   * @param {string} name Child collection name.
   * @return {FakeCollectionReference} Child collection reference.
   */
  collection(
    name: string,
  ): FakeCollectionReference {
    return new FakeCollectionReference(
      this.firestore,
      `${this.path}/${name}`,
    );
  }
}

/** Minimal fake Firestore collection reference for storage tests. */
class FakeCollectionReference {
  private readonly firestore: FakeFirestore;
  private readonly path: string;

  /**
   * Creates a path-bound fake Firestore reference.
   * @param {FakeFirestore} firestore Fake Firestore owner.
   * @param {string} path Canonical fake document path.
   */
  constructor(
    firestore: FakeFirestore,
    path: string,
  ) {
    this.firestore = firestore;
    this.path = path;
  }

  /**
   * Creates a fake document reference in this collection.
   * @param {string} id Fake document identifier.
   * @return {FakeDocumentReference} Fake document reference.
   */
  doc(
    id: string,
  ): FakeDocumentReference {
    return new FakeDocumentReference(
      this.firestore,
      `${this.path}/${id}`,
    );
  }
}

/** Minimal fake Firestore document snapshot for storage tests. */
class FakeSnapshot {
  readonly exists: boolean;
  readonly id: string;
  private readonly value:
    FakeDocument | undefined;

  /**
   * Creates a fake document snapshot.
   * @param {string} path Canonical fake document path.
   * @param {Object|undefined} value Fake document data.
   */
  constructor(
    path: string,
    value: FakeDocument | undefined,
  ) {
    this.exists = value !== undefined;
    const parts =
      path.split("/");

    this.id =
      parts[parts.length - 1] ?? "";
    this.value = value;
  }

  /**
   * Returns fake document data.
   * @return {Object|undefined} Fake document data.
   */
  data(): FakeDocument | undefined {
    return this.value;
  }
}

type FakeWrite = Readonly<{
  kind: "create" | "set";
  path: string;
  data: FakeDocument;
}>;

/** Minimal fake Firestore transaction for storage tests. */
class FakeTransaction {
  readonly reads: string[] = [];
  readonly writes: FakeWrite[] = [];
  private readonly firestore: FakeFirestore;

  /**
   * Creates a fake Firestore transaction.
   * @param {FakeFirestore} firestore Fake Firestore owner.
   */
  constructor(
    firestore: FakeFirestore,
  ) {
    this.firestore = firestore;
  }

  /**
   * Reads a fake document snapshot.
   * @param {FakeDocumentReference} reference Target document reference.
   * @return {Promise} Fake document snapshot promise.
   */
  async get(
    reference: FakeDocumentReference,
  ): Promise<FakeSnapshot> {
    this.reads.push(reference.path);

    return new FakeSnapshot(
      reference.path,
      this.firestore.documents.get(
        reference.path,
      ),
    );
  }

  /**
   * Records a fake transaction create write.
   * @param {FakeDocumentReference} reference Target document reference.
   * @param {Object} data Fake document data.
   */
  create(
    reference: FakeDocumentReference,
    data: FakeDocument,
  ): void {
    this.writes.push({
      kind: "create",
      path: reference.path,
      data,
    });
  }

  /**
   * Records a fake transaction set write.
   * @param {FakeDocumentReference} reference Target document reference.
   * @param {Object} data Fake document data.
   */
  set(
    reference: FakeDocumentReference,
    data: FakeDocument,
  ): void {
    this.writes.push({
      kind: "set",
      path: reference.path,
      data,
    });
  }
}

/** Minimal fake Firestore implementation for storage tests. */
class FakeFirestore {
  readonly documents:
    Map<string, FakeDocument>;

  readonly transaction:
    FakeTransaction;

  runTransactionCalls = 0;

  /**
   * Creates fake Firestore with initial document records.
   * @param {Object} initial Initial fake document records.
   */
  constructor(
    initial: Readonly<
      Record<string, FakeDocument>
    >,
  ) {
    this.documents =
      new Map(Object.entries(initial));

    this.transaction =
      new FakeTransaction(this);
  }

  /**
   * Creates a child fake collection reference.
   * @param {string} name Child collection name.
   * @return {FakeCollectionReference} Child collection reference.
   */
  collection(
    name: string,
  ): FakeCollectionReference {
    return new FakeCollectionReference(
      this,
      name,
    );
  }

  /**
   * Executes one fake Firestore transaction callback.
   * @param {Function} action Transaction callback.
   * @return {Promise} Transaction result promise.
   */
  async runTransaction<T>(
    action: (
      transaction: FakeTransaction,
    ) => Promise<T>,
  ): Promise<T> {
    this.runTransactionCalls++;

    return action(this.transaction);
  }
}

const baseDocuments = (
  overrides: Readonly<
    Record<string, FakeDocument>
  > = {},
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
  ...overrides,
});

const dependencies = (
  fake: FakeFirestore,
) => ({
  firestore:
    fake as unknown as Firestore,
  newOpaqueCallId: () => callId,
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

test(
  "passenger create writes canonical call and pointer",
  async () => {
    const fake =
      new FakeFirestore(baseDocuments());

    const result =
      await createStoredRideVoiceCallForActor(
        dependencies(fake),
        passengerUid,
        {rideId},
      );

    assert.equal(
      result.callId,
      callId,
    );

    assert.deepEqual(
      result.caller,
      {
        uid: passengerUid,
        role: "passenger",
      },
    );

    assert.deepEqual(
      result.callee,
      {
        uid: driverUid,
        role: "driver",
      },
    );

    assert.deepEqual(
      fake.transaction.reads,
      [
        `rides/${rideId}`,
        `driverProfiles/${driverId}`,
        `rideVoiceActiveCalls/${rideId}`,
      ],
    );

    assert.equal(
      fake.transaction.writes.length,
      2,
    );

    const callWrite =
      fake.transaction.writes[0];

    assert.equal(
      callWrite.kind,
      "create",
    );

    assert.equal(
      callWrite.path,
      `rides/${rideId}/voiceCalls/${callId}`,
    );

    assert.equal(
      callWrite.data.callId,
      callId,
    );

    assert.equal(
      callWrite.data.rideId,
      rideId,
    );

    assert.equal(
      callWrite.data.rideVersion,
      7,
    );

    assert.equal(
      callWrite.data.state,
      "ringing",
    );

    assert.deepEqual(
      callWrite.data.caller,
      {
        uid: passengerUid,
        role: "passenger",
      },
    );

    assert.deepEqual(
      callWrite.data.callee,
      {
        uid: driverUid,
        role: "driver",
      },
    );

    assert.ok(
      callWrite.data.createdAt instanceof
        Timestamp,
    );

    assert.equal(
      (
        callWrite.data.createdAt as
          Timestamp
      ).toMillis(),
      nowMillis,
    );

    assert.equal(
      (
        callWrite.data.updatedAt as
          Timestamp
      ).toMillis(),
      nowMillis,
    );

    const pointerWrite =
      fake.transaction.writes[1];

    assert.equal(
      pointerWrite.kind,
      "set",
    );

    assert.equal(
      pointerWrite.path,
      `rideVoiceActiveCalls/${rideId}`,
    );

    assert.equal(
      pointerWrite.data.callId,
      callId,
    );

    assert.equal(
      pointerWrite.data.state,
      "ringing",
    );
  },
);

test(
  "driver actor is resolved from driver profile auth uid",
  async () => {
    const fake =
      new FakeFirestore(baseDocuments());

    const result =
      await createStoredRideVoiceCallForActor(
        dependencies(fake),
        driverUid,
        {rideId},
      );

    assert.deepEqual(
      result.caller,
      {
        uid: driverUid,
        role: "driver",
      },
    );

    assert.deepEqual(
      result.callee,
      {
        uid: passengerUid,
        role: "passenger",
      },
    );
  },
);

test(
  "outsider is denied before active pointer read",
  async () => {
    const activePath =
      `rideVoiceActiveCalls/${rideId}`;

    const fake =
      new FakeFirestore(
        baseDocuments({
          [activePath]: {
            callId,
            rideId,
            state: "ringing",
          },
        }),
      );

    await expectAuthorityError(
      () =>
        createStoredRideVoiceCallForActor(
          dependencies(fake),
          "outsider-uid",
          {rideId},
        ),
      "permission-denied",
    );

    assert.equal(
      fake.transaction.reads.includes(
        activePath,
      ),
      false,
    );

    assert.equal(
      fake.transaction.writes.length,
      0,
    );
  },
);

test(
  "nonterminal pointer blocks second call",
  async () => {
    const fake =
      new FakeFirestore(
        baseDocuments({
          [`rideVoiceActiveCalls/${rideId}`]: {
            callId,
            rideId,
            state: "active",
          },
        }),
      );

    await expectAuthorityError(
      () =>
        createStoredRideVoiceCallForActor(
          dependencies(fake),
          passengerUid,
          {rideId},
        ),
      "already-exists",
    );

    assert.equal(
      fake.transaction.writes.length,
      0,
    );
  },
);

test(
  "terminal pointer permits atomic replacement",
  async () => {
    const fake =
      new FakeFirestore(
        baseDocuments({
          [`rideVoiceActiveCalls/${rideId}`]: {
            callId:
              "rvc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            rideId,
            state: "ended",
          },
        }),
      );

    const result =
      await createStoredRideVoiceCallForActor(
        dependencies(fake),
        passengerUid,
        {rideId},
      );

    assert.equal(
      result.state,
      "ringing",
    );

    assert.equal(
      fake.transaction.writes.length,
      2,
    );

    assert.equal(
      fake.transaction.writes[1].path,
      `rideVoiceActiveCalls/${rideId}`,
    );

    assert.equal(
      fake.transaction.writes[1]
        .data.callId,
      callId,
    );
  },
);

test(
  "missing ride fails before profile and pointer reads",
  async () => {
    const fake =
      new FakeFirestore({});

    await expectAuthorityError(
      () =>
        createStoredRideVoiceCallForActor(
          dependencies(fake),
          passengerUid,
          {rideId},
        ),
      "not-found",
    );

    assert.deepEqual(
      fake.transaction.reads,
      [`rides/${rideId}`],
    );

    assert.equal(
      fake.transaction.writes.length,
      0,
    );
  },
);

test(
  "malformed ride driver identity fails closed",
  async () => {
    const fake =
      new FakeFirestore({
        [`rides/${rideId}`]: {
          version: 7,
          status: "driverEnRoute",
          passengerId: passengerUid,
          driverId: null,
        },
      });

    await expectAuthorityError(
      () =>
        createStoredRideVoiceCallForActor(
          dependencies(fake),
          passengerUid,
          {rideId},
        ),
      "data-invalid",
    );

    assert.deepEqual(
      fake.transaction.reads,
      [`rides/${rideId}`],
    );

    assert.equal(
      fake.transaction.writes.length,
      0,
    );
  },
);

test(
  "missing driver profile fails before pointer read",
  async () => {
    const fake =
      new FakeFirestore({
        [`rides/${rideId}`]: {
          version: 7,
          status: "driverEnRoute",
          passengerId: passengerUid,
          driverId,
        },
      });

    await expectAuthorityError(
      () =>
        createStoredRideVoiceCallForActor(
          dependencies(fake),
          passengerUid,
          {rideId},
        ),
      "data-invalid",
    );

    assert.deepEqual(
      fake.transaction.reads,
      [
        `rides/${rideId}`,
        `driverProfiles/${driverId}`,
      ],
    );

    assert.equal(
      fake.transaction.writes.length,
      0,
    );
  },
);

test(
  "malformed active pointer fails closed without writes",
  async () => {
    const fake =
      new FakeFirestore(
        baseDocuments({
          [`rideVoiceActiveCalls/${rideId}`]: {
            callId: "bad-call-id",
            rideId,
            state: "ringing",
          },
        }),
      );

    await expectAuthorityError(
      () =>
        createStoredRideVoiceCallForActor(
          dependencies(fake),
          passengerUid,
          {rideId},
        ),
      "data-invalid",
    );

    assert.equal(
      fake.transaction.writes.length,
      0,
    );
  },
);

test(
  "extra create payload fails before firestore reads",
  async () => {
    const fake =
      new FakeFirestore(baseDocuments());

    await expectAuthorityError(
      () =>
        createStoredRideVoiceCallForActor(
          dependencies(fake),
          passengerUid,
          {
            rideId,
            callerUid: passengerUid,
          },
        ),
      "invalid-argument",
    );

    assert.equal(
      fake.transaction.reads.length,
      0,
    );

    assert.equal(
      fake.transaction.writes.length,
      0,
    );
  },
);

test(
  "storage layer runs one transaction only",
  async () => {
    const fake =
      new FakeFirestore(baseDocuments());

    await createStoredRideVoiceCallForActor(
      dependencies(fake),
      passengerUid,
      {rideId},
    );

    assert.equal(
      fake.runTransactionCalls,
      1,
    );
  },
);

test(
  "generated call id stays opaque from raw ride identity",
  async () => {
    const fake =
      new FakeFirestore(baseDocuments());

    const result =
      await createStoredRideVoiceCallForActor(
        dependencies(fake),
        passengerUid,
        {rideId},
      );

    assert.equal(
      result.callId.includes(rideId),
      false,
    );

    assert.match(
      result.callId,
      /^rvc_[0-9a-f]{32}$/u,
    );
  },
);
