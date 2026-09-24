import assert from "node:assert/strict";
import test from "node:test";

import {
  RideVoiceCallAuthorityError,
} from "./ride-voice-call-authority.js";
import {
  getRideVoiceRtcSessionForActor,
  type RideVoiceRtcTokenBuilder,
} from "./ride-voice-call-rtc-session-authority.js";
import type {
  RideVoiceCallRecoveryResult,
} from "./ride-voice-call-recovery-authority.js";

const appId =
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const appCertificate =
  "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
const callId =
  "rvc_0123456789abcdef0123456789abcdef";

const recovered = (
  state:
    "ringing" |
    "accepted" |
    "connecting" |
    "active",
  side:
    "caller" |
    "callee",
): RideVoiceCallRecoveryResult => ({
  activeCall: {
    rideId: "ride-1",
    callId,
    state,
    role: "passenger",
    side,
  },
});

test(
  "RTC session requires exact empty input before recovery",
  async () => {
    let recoveryCalls = 0;

    await assert.rejects(
      getRideVoiceRtcSessionForActor(
        {
          recoverActiveCall: async () => {
            recoveryCalls += 1;
            return recovered(
              "accepted",
              "caller",
            );
          },
          appId,
          appCertificate,
          buildToken: () => "token",
        },
        "actor-1",
        {rideId: "client-selected"},
      ),
      (error: unknown) => {
        assert.ok(
          error instanceof
            RideVoiceCallAuthorityError,
        );
        assert.equal(
          error.code,
          "invalid-argument",
        );
        return true;
      },
    );

    assert.equal(recoveryCalls, 0);
  },
);

test(
  "accepted caller receives server-derived audio-only RTC session",
  async () => {
    const tokenCalls:
      Parameters<RideVoiceRtcTokenBuilder>[] =
      [];

    const buildToken:
      RideVoiceRtcTokenBuilder =
      (...args) => {
        tokenCalls.push(args);
        return "rtc-token";
      };

    const result =
      await getRideVoiceRtcSessionForActor(
        {
          recoverActiveCall: async (
            actorUid,
            input,
          ) => {
            assert.equal(
              actorUid,
              "actor-1",
            );
            assert.deepEqual(
              input,
              {},
            );
            return recovered(
              "accepted",
              "caller",
            );
          },
          appId,
          appCertificate,
          nowMillis: () => 1000,
          buildToken,
        },
        "actor-1",
        {},
      );

    assert.deepEqual(
      result,
      {
        appId,
        channelName: callId,
        token: "rtc-token",
        rtcUid: 1,
        expiresAtMillis: 901000,
      },
    );

    assert.deepEqual(
      Object.keys(result).sort(),
      [
        "appId",
        "channelName",
        "expiresAtMillis",
        "rtcUid",
        "token",
      ],
    );

    assert.deepEqual(
      tokenCalls,
      [[
        appId,
        appCertificate,
        callId,
        1,
        900,
        900,
        900,
        0,
        0,
      ]],
    );
  },
);

test(
  "connecting callee receives deterministic RTC uid two",
  async () => {
    const result =
      await getRideVoiceRtcSessionForActor(
        {
          recoverActiveCall: async () =>
            recovered(
              "connecting",
              "callee",
            ),
          appId,
          appCertificate,
          nowMillis: () => 5000,
          buildToken: (
            receivedAppId,
            receivedCertificate,
            receivedChannel,
            receivedUid,
          ) => {
            assert.equal(
              receivedAppId,
              appId,
            );
            assert.equal(
              receivedCertificate,
              appCertificate,
            );
            assert.equal(
              receivedChannel,
              callId,
            );
            assert.equal(
              receivedUid,
              2,
            );
            return "rtc-token-2";
          },
        },
        "actor-2",
        {},
      );

    assert.equal(
      result.rtcUid,
      2,
    );
    assert.equal(
      result.channelName,
      callId,
    );
    assert.equal(
      result.expiresAtMillis,
      905000,
    );
  },
);

test(
  "active call remains RTC-session eligible",
  async () => {
    const result =
      await getRideVoiceRtcSessionForActor(
        {
          recoverActiveCall: async () =>
            recovered(
              "active",
              "caller",
            ),
          appId,
          appCertificate,
          nowMillis: () => 9000,
          buildToken: () =>
            "active-token",
        },
        "actor-1",
        {},
      );

    assert.equal(
      result.token,
      "active-token",
    );
  },
);

test(
  "ringing and absent calls fail closed before credentials",
  async () => {
    for (
      const recovery of [
        recovered(
          "ringing",
          "caller",
        ),
        {
          activeCall: null,
        } satisfies
          RideVoiceCallRecoveryResult,
      ]
    ) {
      await assert.rejects(
        getRideVoiceRtcSessionForActor(
          {
            recoverActiveCall:
              async () => recovery,
            appId: "invalid",
            appCertificate: "invalid",
            buildToken: () =>
              "should-not-build",
          },
          "actor-1",
          {},
        ),
        (error: unknown) => {
          assert.ok(
            error instanceof
              RideVoiceCallAuthorityError,
          );
          assert.equal(
            error.code,
            "failed-precondition",
          );
          assert.equal(
            error.message,
            "Voice RTC session is unavailable.",
          );
          return true;
        },
      );
    }
  },
);

test(
  "invalid Agora configuration fails closed without token generation",
  async () => {
    let tokenCalls = 0;

    await assert.rejects(
      getRideVoiceRtcSessionForActor(
        {
          recoverActiveCall: async () =>
            recovered(
              "accepted",
              "caller",
            ),
          appId: "invalid",
          appCertificate,
          buildToken: () => {
            tokenCalls += 1;
            return "token";
          },
        },
        "actor-1",
        {},
      ),
      (error: unknown) => {
        assert.ok(
          error instanceof
            RideVoiceCallAuthorityError,
        );
        assert.equal(
          error.code,
          "failed-precondition",
        );
        return true;
      },
    );

    assert.equal(tokenCalls, 0);
  },
);

test(
  "invalid clock and token are data-invalid",
  async () => {
    await assert.rejects(
      getRideVoiceRtcSessionForActor(
        {
          recoverActiveCall: async () =>
            recovered(
              "accepted",
              "caller",
            ),
          appId,
          appCertificate,
          nowMillis: () => -1,
          buildToken: () => "token",
        },
        "actor-1",
        {},
      ),
      (error: unknown) => {
        assert.ok(
          error instanceof
            RideVoiceCallAuthorityError,
        );
        assert.equal(
          error.code,
          "data-invalid",
        );
        return true;
      },
    );

    await assert.rejects(
      getRideVoiceRtcSessionForActor(
        {
          recoverActiveCall: async () =>
            recovered(
              "accepted",
              "caller",
            ),
          appId,
          appCertificate,
          nowMillis: () => 0,
          buildToken: () => "",
        },
        "actor-1",
        {},
      ),
      (error: unknown) => {
        assert.ok(
          error instanceof
            RideVoiceCallAuthorityError,
        );
        assert.equal(
          error.code,
          "data-invalid",
        );
        return true;
      },
    );
  },
);
