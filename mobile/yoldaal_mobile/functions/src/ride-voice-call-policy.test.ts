import assert from "node:assert/strict";
import test from "node:test";
import {
  RIDE_VOICE_CALL_STATES,
  RIDE_VOICE_ELIGIBLE_RIDE_STATUSES,
  RIDE_VOICE_PARTICIPANT_ROLES,
  RIDE_VOICE_TERMINAL_CALL_STATES,
  isRideVoiceCallState,
  isRideVoiceCallTransitionAllowed,
  isRideVoiceEligibleRideStatus,
  isRideVoiceParticipantRole,
  isRideVoiceTerminalCallState,
} from "./ride-voice-call-policy.js";

test(
  "voice call state vocabulary is exact and stable",
  () => {
    assert.deepEqual(
      RIDE_VOICE_CALL_STATES,
      [
        "ringing",
        "accepted",
        "connecting",
        "active",
        "ended",
        "declined",
        "cancelled",
        "missed",
        "failed",
      ],
    );

    assert.equal(
      new Set(RIDE_VOICE_CALL_STATES).size,
      RIDE_VOICE_CALL_STATES.length,
    );
  },
);

test(
  "voice participant roles are driver and passenger only",
  () => {
    assert.deepEqual(
      RIDE_VOICE_PARTICIPANT_ROLES,
      [
        "driver",
        "passenger",
      ],
    );

    assert.equal(
      isRideVoiceParticipantRole("driver"),
      true,
    );

    assert.equal(
      isRideVoiceParticipantRole("passenger"),
      true,
    );

    for (const value of [
      "admin",
      "support",
      "anonymous",
      "",
      null,
      42,
    ]) {
      assert.equal(
        isRideVoiceParticipantRole(value),
        false,
      );
    }
  },
);

test(
  "voice eligibility is limited to active participant ride phases",
  () => {
    assert.deepEqual(
      RIDE_VOICE_ELIGIBLE_RIDE_STATUSES,
      [
        "driverEnRoute",
        "driverArrived",
        "inProgress",
      ],
    );

    for (const status of [
      "driverEnRoute",
      "driverArrived",
      "inProgress",
    ]) {
      assert.equal(
        isRideVoiceEligibleRideStatus(status),
        true,
      );
    }

    for (const status of [
      "matching",
      "completed",
      "cancelled",
      "expired",
      "",
      null,
      42,
    ]) {
      assert.equal(
        isRideVoiceEligibleRideStatus(status),
        false,
      );
    }
  },
);

test(
  "terminal call states are exact and cannot transition",
  () => {
    assert.deepEqual(
      RIDE_VOICE_TERMINAL_CALL_STATES,
      [
        "ended",
        "declined",
        "cancelled",
        "missed",
        "failed",
      ],
    );

    for (const state of RIDE_VOICE_TERMINAL_CALL_STATES) {
      assert.equal(
        isRideVoiceTerminalCallState(state),
        true,
      );

      for (const candidate of RIDE_VOICE_CALL_STATES) {
        assert.equal(
          isRideVoiceCallTransitionAllowed(
            state,
            candidate,
          ),
          false,
        );
      }
    }

    for (const state of [
      "ringing",
      "accepted",
      "connecting",
      "active",
    ]) {
      assert.equal(
        isRideVoiceTerminalCallState(state),
        false,
      );
    }
  },
);

test(
  "ringing transition policy is bounded",
  () => {
    for (const target of [
      "accepted",
      "declined",
      "cancelled",
      "missed",
      "failed",
    ]) {
      assert.equal(
        isRideVoiceCallTransitionAllowed(
          "ringing",
          target,
        ),
        true,
      );
    }

    for (const target of [
      "ringing",
      "connecting",
      "active",
      "ended",
    ]) {
      assert.equal(
        isRideVoiceCallTransitionAllowed(
          "ringing",
          target,
        ),
        false,
      );
    }
  },
);

test(
  "accepted transition policy requires connection progression",
  () => {
    for (const target of [
      "connecting",
      "ended",
      "failed",
    ]) {
      assert.equal(
        isRideVoiceCallTransitionAllowed(
          "accepted",
          target,
        ),
        true,
      );
    }

    for (const target of [
      "ringing",
      "accepted",
      "active",
      "declined",
      "cancelled",
      "missed",
    ]) {
      assert.equal(
        isRideVoiceCallTransitionAllowed(
          "accepted",
          target,
        ),
        false,
      );
    }
  },
);

test(
  "connecting transition policy permits active end or failure",
  () => {
    for (const target of [
      "active",
      "ended",
      "failed",
    ]) {
      assert.equal(
        isRideVoiceCallTransitionAllowed(
          "connecting",
          target,
        ),
        true,
      );
    }

    for (const target of [
      "ringing",
      "accepted",
      "connecting",
      "declined",
      "cancelled",
      "missed",
    ]) {
      assert.equal(
        isRideVoiceCallTransitionAllowed(
          "connecting",
          target,
        ),
        false,
      );
    }
  },
);

test(
  "active calls can only end or fail",
  () => {
    assert.equal(
      isRideVoiceCallTransitionAllowed(
        "active",
        "ended",
      ),
      true,
    );

    assert.equal(
      isRideVoiceCallTransitionAllowed(
        "active",
        "failed",
      ),
      true,
    );

    for (const target of [
      "ringing",
      "accepted",
      "connecting",
      "active",
      "declined",
      "cancelled",
      "missed",
    ]) {
      assert.equal(
        isRideVoiceCallTransitionAllowed(
          "active",
          target,
        ),
        false,
      );
    }
  },
);

test(
  "unknown values and self transitions fail closed",
  () => {
    for (const state of RIDE_VOICE_CALL_STATES) {
      assert.equal(
        isRideVoiceCallState(state),
        true,
      );

      assert.equal(
        isRideVoiceCallTransitionAllowed(
          state,
          state,
        ),
        false,
      );
    }

    for (const value of [
      "",
      "unknown",
      "pending",
      "reconnecting",
      null,
      undefined,
      42,
      true,
    ]) {
      assert.equal(
        isRideVoiceCallState(value),
        false,
      );

      assert.equal(
        isRideVoiceCallTransitionAllowed(
          value,
          "ringing",
        ),
        false,
      );

      assert.equal(
        isRideVoiceCallTransitionAllowed(
          "ringing",
          value,
        ),
        false,
      );
    }
  },
);
