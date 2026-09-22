import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";

const source =
  readFileSync(
    "src/index.ts",
    "utf8",
  );

test(
  "index imports Voice wake and recovery authorities",
  () => {
    assert.match(
      source,
      /dispatchRideVoiceCallPushHint/u,
    );
    assert.match(
      source,
      /ride-voice-call-push-hint-authority\.js/u,
    );
    assert.match(
      source,
      /recoverActiveRideVoiceCallForActor/u,
    );
    assert.match(
      source,
      /ride-voice-call-recovery-authority\.js/u,
    );
    assert.match(
      source,
      /loadApprovedDriverId/u,
    );
    assert.match(
      source,
      /loadDriverProfileId/u,
    );
    assert.match(
      source,
      /ride-driver-identity\.js/u,
    );
  },
);

test(
  "Voice call create trigger is create-only and ride nested",
  () => {
    const start =
      source.indexOf(
        "export const onRideVoiceCallCreated",
      );
    const end =
      source.indexOf(
        "export const onRideChatMessageCreated",
      );

    assert.ok(start >= 0);
    assert.ok(end > start);

    const trigger =
      source.slice(
        start,
        end,
      );

    assert.match(
      trigger,
      /onDocumentCreated/u,
    );
    assert.match(
      trigger,
      /rides\/\{rideId\}\/voiceCalls\/\{callId\}/u,
    );
    assert.match(
      trigger,
      /region: "europe-west1"/u,
    );
    assert.doesNotMatch(
      trigger,
      /onDocumentWritten/u,
    );
  },
);

test(
  "Voice call create trigger delegates only event param identity",
  () => {
    const start =
      source.indexOf(
        "export const onRideVoiceCallCreated",
      );
    const end =
      source.indexOf(
        "export const onRideChatMessageCreated",
      );
    const trigger =
      source.slice(
        start,
        end,
      );

    assert.match(
      trigger,
      /dispatchRideVoiceCallPushHint/u,
    );
    assert.match(
      trigger,
      /rideId: event\.params\.rideId/u,
    );
    assert.match(
      trigger,
      /callId: event\.params\.callId/u,
    );
    assert.doesNotMatch(
      trigger,
      /event\.data/u,
    );
  },
);

test(
  "Voice wake adapter preserves FID-native multicast message",
  () => {
    const start =
      source.indexOf(
        "export const onRideVoiceCallCreated",
      );
    const end =
      source.indexOf(
        "export const onRideChatMessageCreated",
      );
    const trigger =
      source.slice(
        start,
        end,
      );

    assert.match(
      trigger,
      /sendEachForMulticast:/u,
    );
    assert.match(
      trigger,
      /\.sendEachForMulticast\(/u,
    );
    assert.match(
      trigger,
      /message,/u,
    );
    assert.doesNotMatch(
      trigger,
      /tokens:\s*message\.fids/u,
    );
  },
);

test(
  "Voice wake trigger exposes no client authority or PII payload",
  () => {
    const start =
      source.indexOf(
        "export const onRideVoiceCallCreated",
      );
    const end =
      source.indexOf(
        "export const onRideChatMessageCreated",
      );
    const trigger =
      source.slice(
        start,
        end,
      );

    for (
      const forbidden of [
        "passengerId",
        "driverId",
        "phone",
        "email",
        "authUserId",
      ]
    ) {
      assert.equal(
        trigger.includes(forbidden),
        false,
      );
    }
  },
);

test(
  "active Voice recovery callable enforces App Check and bounded runtime",
  () => {
    const start =
      source.indexOf(
        "export const getMyActiveRideVoiceCall",
      );
    const end =
      source.indexOf(
        "export const sendRideChatMessage",
      );

    assert.ok(start >= 0);
    assert.ok(end > start);

    const callable =
      source.slice(
        start,
        end,
      );

    assert.match(
      callable,
      /enforceAppCheck: true/u,
    );
    assert.match(
      callable,
      /region: "europe-west1"/u,
    );
    assert.match(
      callable,
      /timeoutSeconds: 15/u,
    );
    assert.match(
      callable,
      /memory: "256MiB"/u,
    );
    assert.match(
      callable,
      /minInstances: 0/u,
    );
    assert.match(
      callable,
      /maxInstances: 3/u,
    );
  },
);

test(
  "active Voice recovery authenticates before authority delegation",
  () => {
    const start =
      source.indexOf(
        "export const getMyActiveRideVoiceCall",
      );
    const end =
      source.indexOf(
        "export const sendRideChatMessage",
      );
    const callable =
      source.slice(
        start,
        end,
      );

    const authGate =
      callable.indexOf(
        "if (!request.auth?.uid)",
      );
    const delegate =
      callable.indexOf(
        "recoverActiveRideVoiceCallForActor",
      );

    assert.ok(authGate >= 0);
    assert.ok(delegate > authGate);
    assert.match(
      callable,
      /request\.auth\.uid/u,
    );
    assert.match(
      callable,
      /request\.data/u,
    );
  },
);

test(
  "active Voice recovery uses nullable generic driver profile resolver",
  () => {
    const start =
      source.indexOf(
        "export const getMyActiveRideVoiceCall",
      );
    const end =
      source.indexOf(
        "export const sendRideChatMessage",
      );
    const callable =
      source.slice(
        start,
        end,
      );

    assert.match(
      callable,
      /resolveDriverIdForActor:/u,
    );
    assert.match(
      callable,
      /loadDriverProfileId\(/u,
    );
    assert.match(
      callable,
      /firestore,/u,
    );
    assert.match(
      callable,
      /uid,/u,
    );
    assert.doesNotMatch(
      callable,
      /loadApprovedDriverId/u,
    );
  },
);

test(
  "active Voice recovery reuses safe Voice HTTPS error mapper",
  () => {
    const start =
      source.indexOf(
        "export const getMyActiveRideVoiceCall",
      );
    const end =
      source.indexOf(
        "export const sendRideChatMessage",
      );
    const callable =
      source.slice(
        start,
        end,
      );

    assert.match(
      callable,
      /catch \(error: unknown\)/u,
    );
    assert.match(
      callable,
      /throw toRideVoiceHttpsError\(error\)/u,
    );
  },
);

test(
  "new public wiring exposes no system transition or Agora authority",
  () => {
    const wakeStart =
      source.indexOf(
        "export const onRideVoiceCallCreated",
      );
    const wakeEnd =
      source.indexOf(
        "export const onRideChatMessageCreated",
      );
    const recoveryStart =
      source.indexOf(
        "export const getMyActiveRideVoiceCall",
      );
    const recoveryEnd =
      source.indexOf(
        "export const sendRideChatMessage",
      );

    const combined =
      source.slice(
        wakeStart,
        wakeEnd,
      ) +
      source.slice(
        recoveryStart,
        recoveryEnd,
      );

    assert.doesNotMatch(
      combined,
      /transitionStoredRideVoiceCallForSystem/u,
    );
    assert.doesNotMatch(
      combined,
      /Agora|agora|channel|token/u,
    );
  },
);
