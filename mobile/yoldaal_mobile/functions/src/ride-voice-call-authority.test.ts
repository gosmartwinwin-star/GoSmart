import assert from "node:assert/strict";
import test from "node:test";
import {
  RideVoiceCallAuthorityError,
  createRideVoiceCallForActor,
  createRideVoiceOpaqueCallId,
  isRideVoiceAuthorityTransitionAllowed,
  isRideVoiceOpaqueCallId,
  type RideVoiceCallAuthorityDependencies,
  type RideVoiceExistingCall,
} from "./ride-voice-call-authority.js";

const rideId = "ride-voice-1";
const passengerUid = "passenger-uid";
const driverUid = "driver-uid";
const callId = "rvc_0123456789abcdef0123456789abcdef";

const baseRide = {
  id: rideId,
  version: 7,
  status: "driverEnRoute",
  passengerUid,
  driverUid,
};

const dependencies = (
  options: Readonly<{
    ride?: typeof baseRide | null;
    activeCall?: RideVoiceExistingCall | null;
    onLoadActive?: () => void;
    generatedCallId?: string;
    nowMillis?: number;
  }> = {},
): RideVoiceCallAuthorityDependencies => ({
  loadRide: async () =>
    options.ride === undefined ?
      baseRide :
      options.ride,
  loadActiveCall: async () => {
    options.onLoadActive?.();

    return options.activeCall === undefined ?
      null :
      options.activeCall;
  },
  newOpaqueCallId: () =>
    options.generatedCallId ?? callId,
  nowMillis: () =>
    options.nowMillis ?? 1_700_000_000_000,
});

const expectAuthorityError = async (
  action: () => Promise<unknown>,
  code: RideVoiceCallAuthorityError["code"],
): Promise<void> => {
  await assert.rejects(
    action,
    (error: unknown) =>
      error instanceof RideVoiceCallAuthorityError &&
      error.code === code,
  );
};

test(
  "create payload accepts only exact rideId",
  async () => {
    const result =
      await createRideVoiceCallForActor(
        dependencies(),
        passengerUid,
        {rideId},
      );

    assert.equal(result.rideId, rideId);

    for (const payload of [
      null,
      [],
      {},
      {rideId: ""},
      {rideId: " ride-voice-1"},
      {rideId: "ride/voice"},
      {rideId, passengerUid},
      {rideId, driverUid},
      {rideId, callId},
      {rideId, channel: "client-channel"},
      {rideId, token: "client-token"},
    ]) {
      await expectAuthorityError(
        () =>
          createRideVoiceCallForActor(
            dependencies(),
            passengerUid,
            payload,
          ),
        "invalid-argument",
      );
    }
  },
);

test(
  "passenger call derives both participant identities from server ride",
  async () => {
    const result =
      await createRideVoiceCallForActor(
        dependencies(),
        passengerUid,
        {rideId},
      );

    assert.deepEqual(
      result,
      {
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
        createdAtMillis: 1_700_000_000_000,
      },
    );
  },
);

test(
  "driver call derives reversed participant roles from same ride",
  async () => {
    const result =
      await createRideVoiceCallForActor(
        dependencies(),
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
  "outsider is denied before active-call authority is read",
  async () => {
    let activeReads = 0;

    await expectAuthorityError(
      () =>
        createRideVoiceCallForActor(
          dependencies({
            onLoadActive: () => {
              activeReads++;
            },
          }),
          "outsider-uid",
          {rideId},
        ),
      "permission-denied",
    );

    assert.equal(activeReads, 0);
  },
);

test(
  "voice creation accepts only the three eligible ride statuses",
  async () => {
    for (const status of [
      "driverEnRoute",
      "driverArrived",
      "inProgress",
    ]) {
      const result =
        await createRideVoiceCallForActor(
          dependencies({
            ride: {
              ...baseRide,
              status,
            },
          }),
          passengerUid,
          {rideId},
        );

      assert.equal(result.state, "ringing");
    }

    for (const status of [
      "matching",
      "completed",
      "cancelled",
      "expired",
    ]) {
      await expectAuthorityError(
        () =>
          createRideVoiceCallForActor(
            dependencies({
              ride: {
                ...baseRide,
                status,
              },
            }),
            passengerUid,
            {rideId},
          ),
        "failed-precondition",
      );
    }
  },
);

test(
  "missing or malformed authoritative ride fails closed",
  async () => {
    await expectAuthorityError(
      () =>
        createRideVoiceCallForActor(
          dependencies({ride: null}),
          passengerUid,
          {rideId},
        ),
      "not-found",
    );

    const malformedRides = [
      {
        ...baseRide,
        id: "other-ride",
      },
      {
        ...baseRide,
        version: 0,
      },
      {
        ...baseRide,
        passengerUid: "",
      },
      {
        ...baseRide,
        driverUid: passengerUid,
      },
    ];

    for (const ride of malformedRides) {
      await expectAuthorityError(
        () =>
          createRideVoiceCallForActor(
            dependencies({
              ride: ride as typeof baseRide,
            }),
            passengerUid,
            {rideId},
          ),
        "data-invalid",
      );
    }
  },
);

test(
  "non-terminal existing call blocks a second active call",
  async () => {
    for (const state of [
      "ringing",
      "accepted",
      "connecting",
      "active",
    ]) {
      await expectAuthorityError(
        () =>
          createRideVoiceCallForActor(
            dependencies({
              activeCall: {
                callId,
                rideId,
                state,
              },
            }),
            passengerUid,
            {rideId},
          ),
        "already-exists",
      );
    }
  },
);

test(
  "terminal existing call permits a new opaque call",
  async () => {
    for (const state of [
      "ended",
      "declined",
      "cancelled",
      "missed",
      "failed",
    ]) {
      const result =
        await createRideVoiceCallForActor(
          dependencies({
            activeCall: {
              callId,
              rideId,
              state,
            },
          }),
          passengerUid,
          {rideId},
        );

      assert.equal(result.callId, callId);
      assert.equal(result.state, "ringing");
    }
  },
);

test(
  "malformed existing call and generated identity fail closed",
  async () => {
    await expectAuthorityError(
      () =>
        createRideVoiceCallForActor(
          dependencies({
            activeCall: {
              callId: "ride-voice-1",
              rideId,
              state: "ringing",
            },
          }),
          passengerUid,
          {rideId},
        ),
      "data-invalid",
    );

    await expectAuthorityError(
      () =>
        createRideVoiceCallForActor(
          dependencies({
            generatedCallId:
              "rvc_ride-voice-1_passenger-uid",
          }),
          passengerUid,
          {rideId},
        ),
      "data-invalid",
    );
  },
);

test(
  "opaque call identity has a bounded non-authority format",
  () => {
    const generated =
      createRideVoiceOpaqueCallId();

    assert.equal(
      isRideVoiceOpaqueCallId(generated),
      true,
    );

    assert.match(
      generated,
      /^rvc_[0-9a-f]{32}$/u,
    );

    for (const value of [
      rideId,
      passengerUid,
      driverUid,
      "rvc_short",
      "",
      null,
    ]) {
      assert.equal(
        isRideVoiceOpaqueCallId(value),
        false,
      );
    }
  },
);

test(
  "participant transition authority is caller-callee bounded",
  () => {
    assert.equal(
      isRideVoiceAuthorityTransitionAllowed(
        "callee",
        "ringing",
        "accepted",
      ),
      true,
    );

    assert.equal(
      isRideVoiceAuthorityTransitionAllowed(
        "callee",
        "ringing",
        "declined",
      ),
      true,
    );

    assert.equal(
      isRideVoiceAuthorityTransitionAllowed(
        "caller",
        "ringing",
        "cancelled",
      ),
      true,
    );

    assert.equal(
      isRideVoiceAuthorityTransitionAllowed(
        "caller",
        "ringing",
        "accepted",
      ),
      false,
    );

    assert.equal(
      isRideVoiceAuthorityTransitionAllowed(
        "callee",
        "ringing",
        "cancelled",
      ),
      false,
    );

    for (const side of [
      "caller",
      "callee",
    ] as const) {
      assert.equal(
        isRideVoiceAuthorityTransitionAllowed(
          side,
          "accepted",
          "connecting",
        ),
        true,
      );

      assert.equal(
        isRideVoiceAuthorityTransitionAllowed(
          side,
          "connecting",
          "active",
        ),
        true,
      );

      assert.equal(
        isRideVoiceAuthorityTransitionAllowed(
          side,
          "active",
          "ended",
        ),
        true,
      );
    }
  },
);

test(
  "missed and failed are system transitions and terminals are immutable",
  () => {
    assert.equal(
      isRideVoiceAuthorityTransitionAllowed(
        "system",
        "ringing",
        "missed",
      ),
      true,
    );

    for (const from of [
      "ringing",
      "accepted",
      "connecting",
      "active",
    ]) {
      assert.equal(
        isRideVoiceAuthorityTransitionAllowed(
          "system",
          from,
          "failed",
        ),
        true,
      );

      assert.equal(
        isRideVoiceAuthorityTransitionAllowed(
          "caller",
          from,
          "failed",
        ),
        false,
      );

      assert.equal(
        isRideVoiceAuthorityTransitionAllowed(
          "callee",
          from,
          "failed",
        ),
        false,
      );
    }

    for (const terminal of [
      "ended",
      "declined",
      "cancelled",
      "missed",
      "failed",
    ]) {
      for (const target of [
        "ringing",
        "accepted",
        "connecting",
        "active",
        "ended",
        "declined",
        "cancelled",
        "missed",
        "failed",
      ]) {
        assert.equal(
          isRideVoiceAuthorityTransitionAllowed(
            "system",
            terminal,
            target,
          ),
          false,
        );
      }
    }
  },
);
