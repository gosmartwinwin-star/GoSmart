import assert from "node:assert/strict";
import test from "node:test";

import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {
  consumeRideChatRateLimit,
  deriveRideChatParticipant,
  requireRideChatReadWindow,
  requireRideChatSendStatus,
  rideChatRateLimitId,
  RIDE_CHAT_RETENTION_MILLIS,
  RIDE_CHAT_TERMINAL_READ_MILLIS,
  validateRideChatListPayload,
  validateRideChatSendPayload,
} from "./ride-chat-authority.js";

const caughtError = (
  callback: () => unknown,
): HttpsError => {
  try {
    callback();
  } catch (error: unknown) {
    assert.ok(
      error instanceof HttpsError,
    );

    return error;
  }

  assert.fail("Expected HttpsError.");
};

test(
  "chat send payload trims text and accepts exactly the frozen fields",
  () => {
    assert.deepEqual(
      validateRideChatSendPayload({
        rideId: "ride-a",
        requestId:
          "request_123456789",
        text: "  Merhaba  ",
      }),
      {
        rideId: "ride-a",
        requestId:
          "request_123456789",
        text: "Merhaba",
      },
    );
  },
);

test(
  "chat send payload rejects empty, oversized, or extra-field input",
  () => {
    for (const input of [
      {
        rideId: "ride-a",
        requestId:
          "request_123456789",
        text: "   ",
      },
      {
        rideId: "ride-a",
        requestId:
          "request_123456789",
        text: "x".repeat(1001),
      },
      {
        rideId: "ride-a",
        requestId:
          "request_123456789",
        text: "ok",
        driverId: "driver-a",
      },
    ]) {
      assert.equal(
        caughtError(
          () =>
            validateRideChatSendPayload(
              input,
            ),
        ).code,
        "invalid-argument",
      );
    }

    assert.equal(
      [
        ...validateRideChatSendPayload({
          rideId: "ride-a",
          requestId:
            "request_123456789",
          text: "😀".repeat(1000),
        }).text,
      ].length,
      1000,
    );
  },
);

test(
  "chat list payload defaults to 50 and validates bounded cursor paging",
  () => {
    assert.deepEqual(
      validateRideChatListPayload({
        rideId: "ride-a",
      }),
      {
        rideId: "ride-a",
        pageSize: 50,
        cursor: null,
      },
    );

    assert.deepEqual(
      validateRideChatListPayload({
        rideId: "ride-a",
        pageSize: 25,
        cursor: {
          expiresAtMillis: 3000,
          createdAtMillis: 2000,
          messageId: "abc123",
        },
      }),
      {
        rideId: "ride-a",
        pageSize: 25,
        cursor: {
          expiresAtMillis: 3000,
          createdAtMillis: 2000,
          messageId: "abc123",
        },
      },
    );

    assert.equal(
      caughtError(
        () =>
          validateRideChatListPayload({
            rideId: "ride-a",
            pageSize: 51,
          }),
      ).code,
      "invalid-argument",
    );
  },
);

test(
  "chat participant authority accepts only current participants",
  () => {
    assert.deepEqual(
      deriveRideChatParticipant(
        "passenger-a",
        "passenger-a",
        "driver-a",
        null,
      ),
      {role: "passenger"},
    );

    assert.deepEqual(
      deriveRideChatParticipant(
        "driver-auth-a",
        "passenger-a",
        "driver-a",
        "driver-a",
      ),
      {role: "driver"},
    );

    assert.equal(
      caughtError(
        () =>
          deriveRideChatParticipant(
            "old-driver-auth",
            "passenger-a",
            "driver-new",
            "driver-old",
          ),
      ).code,
      "permission-denied",
    );
  },
);

test(
  "chat send is restricted to the three assigned active statuses",
  () => {
    for (const status of [
      "driverEnRoute",
      "driverArrived",
      "inProgress",
    ]) {
      assert.equal(
        requireRideChatSendStatus(
          status,
        ),
        status,
      );
    }

    for (const status of [
      "matching",
      "completed",
      "cancelled",
      "expired",
    ]) {
      assert.equal(
        caughtError(
          () =>
            requireRideChatSendStatus(
              status,
            ),
        ).code,
        "failed-precondition",
      );
    }
  },
);

test(
  "terminal chat read denies the exact 24h boundary",
  () => {
    const completedAt =
      Timestamp.fromMillis(
        1_700_000_000_000,
      );

    const justBefore =
      Timestamp.fromMillis(
        completedAt.toMillis() +
          RIDE_CHAT_TERMINAL_READ_MILLIS -
          1,
      );

    assert.equal(
      requireRideChatReadWindow(
        {
          status: "completed",
          completedAt,
        },
        justBefore,
      ),
      "completed",
    );

    const exactBoundary =
      Timestamp.fromMillis(
        completedAt.toMillis() +
          RIDE_CHAT_TERMINAL_READ_MILLIS,
      );

    const error =
      caughtError(
        () =>
          requireRideChatReadWindow(
            {
              status: "completed",
              completedAt,
            },
            exactBoundary,
          ),
      );

    assert.equal(
      error.code,
      "failed-precondition",
    );

    assert.equal(
      (
        error.details as
          {reason?: string}
      ).reason,
      "ride_chat_terminal_read_window_closed",
    );
  },
);

test(
  "matching rides have no chat read window",
  () => {
    assert.equal(
      caughtError(
        () =>
          requireRideChatReadWindow(
            {status: "matching"},
            Timestamp.fromMillis(
              1_700_000_000_000,
            ),
          ),
      ).code,
      "failed-precondition",
    );
  },
);

test(
  "rate limiter starts with burst ten and refreshes its 30 day ttl",
  () => {
    const now =
      Timestamp.fromMillis(
        1_700_000_000_000,
      );

    const state =
      consumeRideChatRateLimit(
        null,
        now,
      );

    assert.equal(state.tokens, 9);
    assert.equal(
      state.lastRefillAt.toMillis(),
      now.toMillis(),
    );
    assert.equal(
      state.expiresAt.toMillis(),
      now.toMillis() +
        RIDE_CHAT_RETENTION_MILLIS,
    );
  },
);

test(
  "rate limiter refills after two seconds",
  () => {
    const base =
      Timestamp.fromMillis(10_000);

    const state = {
      tokens: 0,
      lastRefillAt: base,
      expiresAt:
        Timestamp.fromMillis(
          base.toMillis() +
            RIDE_CHAT_RETENTION_MILLIS,
        ),
    };

    const denied =
      caughtError(
        () =>
          consumeRideChatRateLimit(
            state,
            Timestamp.fromMillis(
              base.toMillis() + 1999,
            ),
          ),
      );

    assert.equal(
      denied.code,
      "resource-exhausted",
    );

    const accepted =
      consumeRideChatRateLimit(
        state,
        Timestamp.fromMillis(
          base.toMillis() + 2000,
        ),
      );

    assert.equal(
      accepted.tokens,
      0,
    );
  },
);

test(
  "expired rate state resets to full burst before consuming one token",
  () => {
    const now =
      Timestamp.fromMillis(50_000);

    const state =
      consumeRideChatRateLimit(
        {
          tokens: 0,
          lastRefillAt:
            Timestamp.fromMillis(1),
          expiresAt:
            Timestamp.fromMillis(
              now.toMillis(),
            ),
        },
        now,
      );

    assert.equal(state.tokens, 9);
  },
);

test(
  "rate limit document id is deterministic sha256 without raw uid or ride id",
  () => {
    const first =
      rideChatRateLimitId(
        "ride-a",
        "user-sensitive-a",
      );

    assert.match(
      first,
      /^[a-f0-9]{64}$/u,
    );

    assert.equal(
      first,
      rideChatRateLimitId(
        "ride-a",
        "user-sensitive-a",
      ),
    );

    assert.equal(
      first.includes("ride-a"),
      false,
    );

    assert.equal(
      first.includes(
        "user-sensitive-a",
      ),
      false,
    );
  },
);
