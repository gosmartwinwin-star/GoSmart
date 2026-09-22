import assert from "node:assert/strict";
import test from "node:test";
import type {Firestore} from "firebase-admin/firestore";
import {Timestamp} from "firebase-admin/firestore";

import {
  recoverActiveRideVoiceCallForActor,
  type RideVoiceCallRecoveryDependencies,
} from "./ride-voice-call-recovery-authority.js";

const rideId =
  "ride-recovery-1";
const passengerUid =
  "passenger-a";
const driverId =
  "driver-profile-a";
const driverUid =
  "driver-auth-a";
const callId =
  "rvc_0123456789abcdef0123456789abcdef";

type Stored =
  Record<string, unknown>;

/**
 * Minimal Firestore document snapshot fixture.
 */
class FakeSnapshot {
  /**
   * Creates one fake snapshot.
   * @param {Stored|undefined} value Stored document value.
   */
  constructor(
    private readonly value:
      Stored | undefined,
  ) {}

  /**
   * Reports whether the document exists.
   * @return {boolean} True when stored.
   */
  get exists(): boolean {
    return this.value !== undefined;
  }

  /**
   * Returns the stored document body.
   * @return {Stored|undefined} Stored value.
   */
  data(): Stored | undefined {
    return this.value;
  }
}

/**
 * Minimal Firestore document reference fixture.
 */
class FakeReference {
  /**
   * Creates one fake document reference.
   * @param {FakeFirestore} store In-memory store.
   * @param {string} path Document path.
   */
  constructor(
    private readonly store:
      FakeFirestore,
    readonly path: string,
  ) {}

  /**
   * Creates a nested collection reference.
   * @param {string} name Collection name.
   * @return {FakeCollection} Nested collection.
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
   * Reads one fake document.
   * @return {Promise<FakeSnapshot>} Snapshot.
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

/**
 * Minimal Firestore collection reference fixture.
 */
class FakeCollection {
  /**
   * Creates one fake collection.
   * @param {FakeFirestore} store In-memory store.
   * @param {string} path Collection path.
   */
  constructor(
    private readonly store:
      FakeFirestore,
    private readonly path:
      string,
  ) {}

  /**
   * Creates one fake document reference.
   * @param {string} id Document ID.
   * @return {FakeReference} Document reference.
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

/**
 * Minimal in-memory Firestore fixture.
 */
class FakeFirestore {
  readonly docs =
    new Map<string, Stored>();
  readonly reads:
    string[] = [];

  /**
   * Creates one fake root collection.
   * @param {string} name Collection name.
   * @return {FakeCollection} Collection.
   */
  collection(
    name: string,
  ): FakeCollection {
    return new FakeCollection(
      this,
      name,
    );
  }
}

const now =
  Timestamp.fromMillis(
    1700000000000,
  );

const passengerPointerPath =
  `passengerActiveRides/${passengerUid}`;
const driverPointerPath =
  `driverActiveRides/${driverId}`;
const activeCallPath =
  `rideVoiceActiveCalls/${rideId}`;
const storedCallPath =
  `rides/${rideId}/voiceCalls/${callId}`;

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
    passengerPointerPath,
    {
      rideId,
      status: "driverEnRoute",
    },
  );
  store.docs.set(
    activeCallPath,
    {
      callId,
      rideId,
      state: "ringing",
      updatedAt: now,
    },
  );
  store.docs.set(
    storedCallPath,
    baseCall(),
  );

  return store;
};

const makeDependencies = (
  store: FakeFirestore,
  driverIdentity:
    string | null = null,
): RideVoiceCallRecoveryDependencies => ({
  firestore:
    store as unknown as Firestore,
  resolveDriverIdForActor:
    async () =>
      driverIdentity,
});

test(
  "payload accepts only exact empty object",
  async () => {
    const store =
      createStore();

    await assert.rejects(
      recoverActiveRideVoiceCallForActor(
        makeDependencies(store),
        passengerUid,
        {
          rideId,
        },
      ),
      {
        code:
          "invalid-argument",
      },
    );

    assert.deepEqual(
      store.reads,
      [],
    );
  },
);

test(
  "passenger recovers ringing call with privacy-bounded projection",
  async () => {
    const store =
      createStore();

    const result =
      await recoverActiveRideVoiceCallForActor(
        makeDependencies(store),
        passengerUid,
        {},
      );

    assert.deepEqual(
      result,
      {
        activeCall: {
          rideId,
          callId,
          state: "ringing",
          role: "passenger",
          side: "caller",
        },
      },
    );

    assert.deepEqual(
      Object.keys(
        result.activeCall ?? {},
      ).sort(),
      [
        "callId",
        "rideId",
        "role",
        "side",
        "state",
      ],
    );

    const encoded =
      JSON.stringify(result);

    assert.equal(
      encoded.includes(driverUid),
      false,
    );
    assert.equal(
      encoded.includes(driverId),
      false,
    );
  },
);

test(
  "driver recovers ringing call through canonical driver pointer",
  async () => {
    const store =
      createStore();

    store.docs.delete(
      passengerPointerPath,
    );
    store.docs.set(
      driverPointerPath,
      {
        rideId,
        status: "driverEnRoute",
      },
    );

    const result =
      await recoverActiveRideVoiceCallForActor(
        makeDependencies(
          store,
          driverId,
        ),
        driverUid,
        {},
      );

    assert.deepEqual(
      result,
      {
        activeCall: {
          rideId,
          callId,
          state: "ringing",
          role: "driver",
          side: "callee",
        },
      },
    );
  },
);

test(
  "no active ride returns null before voice reads",
  async () => {
    const store =
      createStore();

    store.docs.delete(
      passengerPointerPath,
    );

    const result =
      await recoverActiveRideVoiceCallForActor(
        makeDependencies(store),
        passengerUid,
        {},
      );

    assert.deepEqual(
      result,
      {
        activeCall: null,
      },
    );
    assert.equal(
      store.reads.includes(
        activeCallPath,
      ),
      false,
    );
  },
);

test(
  "conflicting passenger and driver active rides fail closed",
  async () => {
    const store =
      createStore();

    store.docs.set(
      driverPointerPath,
      {
        rideId: "ride-other",
        status: "driverEnRoute",
      },
    );

    await assert.rejects(
      recoverActiveRideVoiceCallForActor(
        makeDependencies(
          store,
          driverId,
        ),
        passengerUid,
        {},
      ),
      {
        code:
          "data-invalid",
      },
    );
  },
);

test(
  "stale passenger active ride pointer fails closed",
  async () => {
    const store =
      createStore();

    store.docs.set(
      passengerPointerPath,
      {
        rideId,
        status: "completed",
      },
    );

    await assert.rejects(
      recoverActiveRideVoiceCallForActor(
        makeDependencies(store),
        passengerUid,
        {},
      ),
      {
        code:
          "data-invalid",
      },
    );
  },
);

test(
  "missing active voice pointer returns null",
  async () => {
    const store =
      createStore();

    store.docs.delete(
      activeCallPath,
    );

    const result =
      await recoverActiveRideVoiceCallForActor(
        makeDependencies(store),
        passengerUid,
        {},
      );

    assert.deepEqual(
      result,
      {
        activeCall: null,
      },
    );
  },
);

test(
  "active pointer and nested call state must agree",
  async () => {
    const store =
      createStore();

    store.docs.set(
      activeCallPath,
      {
        callId,
        rideId,
        state: "accepted",
        updatedAt: now,
      },
    );

    await assert.rejects(
      recoverActiveRideVoiceCallForActor(
        makeDependencies(store),
        passengerUid,
        {},
      ),
      {
        code:
          "data-invalid",
      },
    );
  },
);

test(
  "stored participant pair must match authoritative ride",
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
      storedCallPath,
      call,
    );

    await assert.rejects(
      recoverActiveRideVoiceCallForActor(
        makeDependencies(store),
        passengerUid,
        {},
      ),
      {
        code:
          "data-invalid",
      },
    );
  },
);

test(
  "ringing call becomes unrecoverable after ride loses eligibility",
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
    store.docs.set(
      passengerPointerPath,
      {
        rideId,
        status: "completed",
      },
    );

    const result =
      await recoverActiveRideVoiceCallForActor(
        makeDependencies(store),
        passengerUid,
        {},
      );

    assert.deepEqual(
      result,
      {
        activeCall: null,
      },
    );
  },
);

test(
  "accepted call remains recoverable after ride loses eligibility",
  async () => {
    const store =
      createStore();
    const call =
      baseCall();

    call.state =
      "accepted";

    store.docs.set(
      `rides/${rideId}`,
      {
        passengerId: passengerUid,
        driverId,
        status: "completed",
      },
    );
    store.docs.set(
      passengerPointerPath,
      {
        rideId,
        status: "completed",
      },
    );
    store.docs.set(
      activeCallPath,
      {
        callId,
        rideId,
        state: "accepted",
        updatedAt: now,
      },
    );
    store.docs.set(
      storedCallPath,
      call,
    );

    const result =
      await recoverActiveRideVoiceCallForActor(
        makeDependencies(store),
        passengerUid,
        {},
      );

    assert.equal(
      result.activeCall?.state,
      "accepted",
    );
  },
);

test(
  "terminal pointer is validated then projected as no active call",
  async () => {
    const store =
      createStore();
    const call =
      baseCall();

    call.state =
      "ended";

    store.docs.set(
      activeCallPath,
      {
        callId,
        rideId,
        state: "ended",
        updatedAt: now,
      },
    );
    store.docs.set(
      storedCallPath,
      call,
    );

    const result =
      await recoverActiveRideVoiceCallForActor(
        makeDependencies(store),
        passengerUid,
        {},
      );

    assert.deepEqual(
      result,
      {
        activeCall: null,
      },
    );
    assert.equal(
      store.reads.includes(
        storedCallPath,
      ),
      true,
    );
  },
);

test(
  "driver profile must preserve distinct participant identities",
  async () => {
    const store =
      createStore();

    store.docs.set(
      `driverProfiles/${driverId}`,
      {
        authUserId: passengerUid,
      },
    );

    await assert.rejects(
      recoverActiveRideVoiceCallForActor(
        makeDependencies(store),
        passengerUid,
        {},
      ),
      {
        code:
          "data-invalid",
      },
    );
  },
);

test(
  "malformed canonical driver resolver output fails closed",
  async () => {
    const store =
      createStore();

    await assert.rejects(
      recoverActiveRideVoiceCallForActor(
        makeDependencies(
          store,
          "bad driver id",
        ),
        passengerUid,
        {},
      ),
      {
        code:
          "data-invalid",
      },
    );
  },
);

test(
  "projection contains no counterparty identity or timestamp fields",
  async () => {
    const store =
      createStore();

    const result =
      await recoverActiveRideVoiceCallForActor(
        makeDependencies(store),
        passengerUid,
        {},
      );

    const active =
      result.activeCall;

    assert.notEqual(
      active,
      null,
    );

    const keys =
      Object.keys(
        active ?? {},
      );

    for (
      const forbidden of [
        "uid",
        "driverId",
        "passengerId",
        "caller",
        "callee",
        "createdAt",
        "updatedAt",
        "fid",
        "email",
        "phone",
      ]
    ) {
      assert.equal(
        keys.includes(forbidden),
        false,
      );
    }
  },
);
