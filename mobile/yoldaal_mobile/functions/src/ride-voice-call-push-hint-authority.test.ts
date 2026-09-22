import assert from "node:assert/strict";
import test from "node:test";
import type {
  Firestore,
} from "firebase-admin/firestore";
import {Timestamp} from "firebase-admin/firestore";
import {
  dispatchRideVoiceCallPushHint,
  RIDE_VOICE_CALL_AVAILABLE_PUSH_HINT_TYPE,
  type RideVoiceCallPushHintBatchResponse,
  type RideVoiceCallPushHintMessage,
} from "./ride-voice-call-push-hint-authority.js";

const rideId =
  "ride-voice-push-1";
const callId =
  "rvc_0123456789abcdef0123456789abcdef";
const passengerUid =
  "passenger-a";
const driverId =
  "driver-profile-a";
const driverUid =
  "driver-auth-a";
const driverFid =
  "driver-fid-0001";
const passengerFid =
  "passenger-fid-0001";

type Stored =
  Record<string, unknown>;

/** In-memory Firestore snapshot fixture. */
class FakeSnapshot {
  /**
   * Creates a snapshot fixture.
   *
   * @param {Stored|undefined} value Stored document value.
   */
  constructor(
    private readonly value:
      Stored | undefined,
  ) {}

  /**
   * Reports whether the fixture contains a document.
   *
   * @return {boolean} True when a document exists.
   */
  get exists(): boolean {
    return this.value !== undefined;
  }

  /**
   * Returns the stored fixture data.
   *
   * @return {Stored|undefined} Stored document value.
   */
  data(): Stored | undefined {
    return this.value;
  }
}

/** In-memory Firestore document reference fixture. */
class FakeReference {
  /**
   * Creates a document reference fixture.
   *
   * @param {FakeFirestore} store Backing in-memory store.
   * @param {string} path Document path.
   */
  constructor(
    private readonly store:
      FakeFirestore,
    readonly path: string,
  ) {}

  /**
   * Creates a child collection fixture.
   *
   * @param {string} name Child collection name.
   * @return {FakeCollection} Child collection fixture.
   */
  collection(
    name: string,
  ): FakeCollection {
    return new FakeCollection(
      this.store,
      `${this.path}/${name}`,
    );
  }

  /**
   * Reads the referenced fixture document.
   *
   * @return {Promise<FakeSnapshot>} Snapshot fixture.
   */
  async get(): Promise<FakeSnapshot> {
    this.store.reads.push(
      this.path,
    );
    return new FakeSnapshot(
      this.store.docs.get(
        this.path,
      ),
    );
  }
}

/** In-memory Firestore collection fixture. */
class FakeCollection {
  /**
   * Creates a collection fixture.
   *
   * @param {FakeFirestore} store Backing in-memory store.
   * @param {string} path Collection path.
   */
  constructor(
    private readonly store:
      FakeFirestore,
    private readonly path:
      string,
  ) {}

  /**
   * Creates a document reference fixture.
   *
   * @param {string} id Document identifier.
   * @return {FakeReference} Document reference fixture.
   */
  doc(
    id: string,
  ): FakeReference {
    return new FakeReference(
      this.store,
      `${this.path}/${id}`,
    );
  }
}

/** In-memory Firestore transaction fixture. */
class FakeTransaction {
  /**
   * Creates a transaction fixture.
   *
   * @param {FakeFirestore} store Backing in-memory store.
   */
  constructor(
    private readonly store:
      FakeFirestore,
  ) {}

  /**
   * Reads a document through the transaction fixture.
   *
   * @param {FakeReference} reference Document reference fixture.
   * @return {Promise<FakeSnapshot>} Snapshot fixture.
   */
  async get(
    reference: FakeReference,
  ): Promise<FakeSnapshot> {
    this.store.transactionReads.push(
      reference.path,
    );
    return new FakeSnapshot(
      this.store.docs.get(
        reference.path,
      ),
    );
  }

  /**
   * Deletes a document through the transaction fixture.
   *
   * @param {FakeReference} reference Document reference fixture.
   * @return {void}
   */
  delete(
    reference: FakeReference,
  ): void {
    this.store.deletes.push(
      reference.path,
    );
    this.store.docs.delete(
      reference.path,
    );
  }
}

/** In-memory Firestore fixture used by authority tests. */
class FakeFirestore {
  readonly docs =
    new Map<string, Stored>();
  readonly reads:
    string[] = [];
  readonly transactionReads:
    string[] = [];
  readonly deletes:
    string[] = [];
  throwOnRideCollection =
    false;

  /**
   * Creates a top-level collection fixture.
   *
   * @param {string} name Collection name.
   * @return {FakeCollection} Collection fixture.
   */
  collection(
    name: string,
  ): FakeCollection {
    if (
      this.throwOnRideCollection &&
      name === "rides"
    ) {
      throw new Error(
        "synthetic read failure",
      );
    }

    return new FakeCollection(
      this,
      name,
    );
  }

  /**
   * Runs the supplied transaction callback.
   *
   * @param {Function} callback Transaction callback.
   * @return {Promise<*>} Callback result.
   */
  async runTransaction<T>(
    callback: (
      transaction:
        FakeTransaction,
    ) => Promise<T>,
  ): Promise<T> {
    return callback(
      new FakeTransaction(
        this,
      ),
    );
  }
}

const now =
  Timestamp.fromMillis(
    1700000000000,
  );

const callPath =
  `rides/${rideId}/voiceCalls/${callId}`;

const activePath =
  `rideVoiceActiveCalls/${rideId}`;

const driverTargetPath =
  `driverPushTargets/${driverId}`;

const passengerTargetPath =
  `passengerPushTargets/${passengerUid}`;

const baseCall = (): Stored => ({
  callId,
  rideId,
  rideVersion: 7,
  state: "ringing",
  caller: {
    uid: passengerUid,
    role: "passenger",
  },
  callee: {
    uid: driverUid,
    role: "driver",
  },
  createdAt: now,
  updatedAt: now,
});

const createStore = (): FakeFirestore => {
  const store =
    new FakeFirestore();

  store.docs.set(
    `rides/${rideId}`,
    {
      passengerId: passengerUid,
      driverId,
      status: "driverEnRoute",
    },
  );
  store.docs.set(
    `driverProfiles/${driverId}`,
    {
      authUserId: driverUid,
    },
  );
  store.docs.set(
    activePath,
    {
      callId,
      rideId,
      state: "ringing",
      updatedAt: now,
    },
  );
  store.docs.set(
    callPath,
    baseCall(),
  );
  store.docs.set(
    driverTargetPath,
    {
      driverId,
      fid: driverFid,
      platform: "android",
      updatedAt: now,
    },
  );
  store.docs.set(
    passengerTargetPath,
    {
      passengerId: passengerUid,
      fid: passengerFid,
      platform: "ios",
      updatedAt: now,
    },
  );

  return store;
};

type MessagingOptions = Readonly<{
  response?:
    RideVoiceCallPushHintBatchResponse;
  throwOnSend?: boolean;
  beforeResponse?: () => void;
}>;

const dependencies = (
  store: FakeFirestore,
  sent: RideVoiceCallPushHintMessage[],
  warnings: string[],
  options: MessagingOptions = {},
) => ({
  firestore:
    store as unknown as Firestore,
  getMessaging: () => ({
    sendEachForMulticast:
      async (
        message:
          RideVoiceCallPushHintMessage,
      ) => {
        sent.push(message);
        options.beforeResponse?.();

        if (options.throwOnSend) {
          throw new Error(
            "synthetic send failure",
          );
        }

        return options.response ?? {
          successCount: 1,
          failureCount: 0,
          responses: [
            {
              success: true,
            },
          ],
        };
      },
  }),
  warn: (
    message: string,
  ) => {
    warnings.push(
      message,
    );
  },
});

test(
  "invalid trigger payload fails closed before firestore reads",
  async () => {
    const store =
      createStore();
    const sent:
      RideVoiceCallPushHintMessage[] = [];
    const warnings:
      string[] = [];

    const result =
      await dispatchRideVoiceCallPushHint(
        dependencies(
          store,
          sent,
          warnings,
        ),
        {
          rideId,
          callId,
          extra: true,
        },
      );

    assert.equal(
      result,
      "skipped",
    );
    assert.deepEqual(
      store.reads,
      [],
    );
    assert.equal(
      sent.length,
      0,
    );
  },
);

test(
  "driver callee resolves profile target and sends opaque data-only hint",
  async () => {
    const store =
      createStore();
    const sent:
      RideVoiceCallPushHintMessage[] = [];
    const warnings:
      string[] = [];

    const result =
      await dispatchRideVoiceCallPushHint(
        dependencies(
          store,
          sent,
          warnings,
        ),
        {
          rideId,
          callId,
        },
      );

    assert.equal(
      result,
      "sent",
    );
    assert.deepEqual(
      sent,
      [
        {
          fids: [
            driverFid,
          ],
          data: {
            type:
              RIDE_VOICE_CALL_AVAILABLE_PUSH_HINT_TYPE,
          },
        },
      ],
    );
    assert.equal(
      JSON.stringify(
        sent[0],
      ).includes(
        rideId,
      ),
      false,
    );
    assert.equal(
      JSON.stringify(
        sent[0],
      ).includes(
        callId,
      ),
      false,
    );
    assert.ok(
      store.reads.includes(
        driverTargetPath,
      ),
    );
    assert.equal(
      warnings.length,
      0,
    );
  },
);

test(
  "passenger callee resolves Firebase uid push target",
  async () => {
    const store =
      createStore();
    const call =
      baseCall();

    call.caller = {
      uid: driverUid,
      role: "driver",
    };
    call.callee = {
      uid: passengerUid,
      role: "passenger",
    };
    store.docs.set(
      callPath,
      call,
    );

    const sent:
      RideVoiceCallPushHintMessage[] = [];
    const warnings:
      string[] = [];

    const result =
      await dispatchRideVoiceCallPushHint(
        dependencies(
          store,
          sent,
          warnings,
        ),
        {
          rideId,
          callId,
        },
      );

    assert.equal(
      result,
      "sent",
    );
    assert.deepEqual(
      sent[0]?.fids,
      [
        passengerFid,
      ],
    );
    assert.ok(
      store.reads.includes(
        passengerTargetPath,
      ),
    );
  },
);

test(
  "ineligible current ride stops before push target load",
  async () => {
    const store =
      createStore();

    store.docs.set(
      `rides/${rideId}`,
      {
        passengerId: passengerUid,
        driverId,
        status: "completed",
      },
    );

    const sent:
      RideVoiceCallPushHintMessage[] = [];
    const warnings:
      string[] = [];

    const result =
      await dispatchRideVoiceCallPushHint(
        dependencies(
          store,
          sent,
          warnings,
        ),
        {
          rideId,
          callId,
        },
      );

    assert.equal(
      result,
      "skipped",
    );
    assert.equal(
      sent.length,
      0,
    );
    assert.equal(
      store.reads.includes(
        driverTargetPath,
      ),
      false,
    );
  },
);

test(
  "active pointer mismatch fails closed",
  async () => {
    const store =
      createStore();

    store.docs.set(
      activePath,
      {
        callId:
          "rvc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        rideId,
        state: "ringing",
        updatedAt: now,
      },
    );

    const sent:
      RideVoiceCallPushHintMessage[] = [];
    const warnings:
      string[] = [];

    const result =
      await dispatchRideVoiceCallPushHint(
        dependencies(
          store,
          sent,
          warnings,
        ),
        {
          rideId,
          callId,
        },
      );

    assert.equal(
      result,
      "skipped",
    );
    assert.equal(
      sent.length,
      0,
    );
  },
);

test(
  "stored call must still be ringing",
  async () => {
    const store =
      createStore();

    store.docs.set(
      callPath,
      {
        ...baseCall(),
        state: "accepted",
      },
    );

    const sent:
      RideVoiceCallPushHintMessage[] = [];
    const warnings:
      string[] = [];

    const result =
      await dispatchRideVoiceCallPushHint(
        dependencies(
          store,
          sent,
          warnings,
        ),
        {
          rideId,
          callId,
        },
      );

    assert.equal(
      result,
      "skipped",
    );
    assert.equal(
      sent.length,
      0,
    );
  },
);

test(
  "stored participants must match authoritative ride identities",
  async () => {
    const store =
      createStore();

    const call =
      baseCall();
    call.callee = {
      uid: "other-driver",
      role: "driver",
    };
    store.docs.set(
      callPath,
      call,
    );

    const sent:
      RideVoiceCallPushHintMessage[] = [];
    const warnings:
      string[] = [];

    const result =
      await dispatchRideVoiceCallPushHint(
        dependencies(
          store,
          sent,
          warnings,
        ),
        {
          rideId,
          callId,
        },
      );

    assert.equal(
      result,
      "skipped",
    );
    assert.equal(
      sent.length,
      0,
    );
  },
);

test(
  "missing push target is a fail-soft skipped wake",
  async () => {
    const store =
      createStore();
    store.docs.delete(
      driverTargetPath,
    );

    const sent:
      RideVoiceCallPushHintMessage[] = [];
    const warnings:
      string[] = [];

    const result =
      await dispatchRideVoiceCallPushHint(
        dependencies(
          store,
          sent,
          warnings,
        ),
        {
          rideId,
          callId,
        },
      );

    assert.equal(
      result,
      "skipped",
    );
    assert.equal(
      sent.length,
      0,
    );
  },
);

test(
  "unregistered current FID is deleted conditionally",
  async () => {
    const store =
      createStore();
    const sent:
      RideVoiceCallPushHintMessage[] = [];
    const warnings:
      string[] = [];

    const result =
      await dispatchRideVoiceCallPushHint(
        dependencies(
          store,
          sent,
          warnings,
          {
            response: {
              successCount: 0,
              failureCount: 1,
              responses: [
                {
                  success: false,
                  error: {
                    code:
                      "messaging/installation-id-not-registered",
                  },
                },
              ],
            },
          },
        ),
        {
          rideId,
          callId,
        },
      );

    assert.equal(
      result,
      "failed",
    );
    assert.equal(
      store.docs.has(
        driverTargetPath,
      ),
      false,
    );
    assert.deepEqual(
      store.deletes,
      [
        driverTargetPath,
      ],
    );
  },
);

test(
  "rotated FID survives stale unregistered delivery failure",
  async () => {
    const store =
      createStore();
    const sent:
      RideVoiceCallPushHintMessage[] = [];
    const warnings:
      string[] = [];
    const rotatedFid =
      "driver-fid-rotated";

    const result =
      await dispatchRideVoiceCallPushHint(
        dependencies(
          store,
          sent,
          warnings,
          {
            beforeResponse: () => {
              store.docs.set(
                driverTargetPath,
                {
                  driverId,
                  fid: rotatedFid,
                  platform: "android",
                  updatedAt: now,
                },
              );
            },
            response: {
              successCount: 0,
              failureCount: 1,
              responses: [
                {
                  success: false,
                  error: {
                    code:
                      "messaging/registration-token-not-registered",
                  },
                },
              ],
            },
          },
        ),
        {
          rideId,
          callId,
        },
      );

    assert.equal(
      result,
      "failed",
    );
    assert.equal(
      store.deletes.length,
      0,
    );
    assert.equal(
      store.docs.get(
        driverTargetPath,
      )?.fid,
      rotatedFid,
    );
  },
);

test(
  "messaging exception remains fail-soft and leaves target intact",
  async () => {
    const store =
      createStore();
    const sent:
      RideVoiceCallPushHintMessage[] = [];
    const warnings:
      string[] = [];

    const result =
      await dispatchRideVoiceCallPushHint(
        dependencies(
          store,
          sent,
          warnings,
          {
            throwOnSend: true,
          },
        ),
        {
          rideId,
          callId,
        },
      );

    assert.equal(
      result,
      "failed",
    );
    assert.equal(
      store.docs.has(
        driverTargetPath,
      ),
      true,
    );
    assert.deepEqual(
      warnings,
      [
        "ride_voice_call_push_hint_send_failed",
      ],
    );
  },
);

test(
  "non-unregistered delivery failure does not delete target",
  async () => {
    const store =
      createStore();
    const sent:
      RideVoiceCallPushHintMessage[] = [];
    const warnings:
      string[] = [];

    const result =
      await dispatchRideVoiceCallPushHint(
        dependencies(
          store,
          sent,
          warnings,
          {
            response: {
              successCount: 0,
              failureCount: 1,
              responses: [
                {
                  success: false,
                  error: {
                    code:
                      "messaging/server-unavailable",
                  },
                },
              ],
            },
          },
        ),
        {
          rideId,
          callId,
        },
      );

    assert.equal(
      result,
      "failed",
    );
    assert.equal(
      store.docs.has(
        driverTargetPath,
      ),
      true,
    );
    assert.equal(
      store.deletes.length,
      0,
    );
  },
);

test(
  "authority read failure sends nothing and reports fail-soft result",
  async () => {
    const store =
      createStore();
    const sent:
      RideVoiceCallPushHintMessage[] = [];
    const warnings:
      string[] = [];

    store.throwOnRideCollection =
      true;

    const result =
      await dispatchRideVoiceCallPushHint(
        dependencies(
          store,
          sent,
          warnings,
        ),
        {
          rideId,
          callId,
        },
      );

    assert.equal(
      result,
      "failed",
    );
    assert.equal(
      sent.length,
      0,
    );
    assert.deepEqual(
      warnings,
      [
        "ride_voice_call_push_hint_authority_read_failed",
      ],
    );
  },
);

test(
  "source message contract contains only FID list and type data",
  () => {
    const message:
      RideVoiceCallPushHintMessage = {
        fids: [
          driverFid,
        ],
        data: {
          type:
            RIDE_VOICE_CALL_AVAILABLE_PUSH_HINT_TYPE,
        },
      };

    assert.deepEqual(
      Object.keys(
        message,
      ).sort(),
      [
        "data",
        "fids",
      ],
    );
    assert.deepEqual(
      Object.keys(
        message.data,
      ),
      [
        "type",
      ],
    );
  },
);
