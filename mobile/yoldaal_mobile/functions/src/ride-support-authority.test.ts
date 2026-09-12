import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";

import {
  deriveRideSupportParticipant,
  RIDE_SUPPORT_CATEGORIES,
  rideSupportCaseId,
  validateRideSupportPayload,
} from "./ride-support-authority.js";

const requestId =
  "support_request_1234567890";

const reasonOf = (
  callback: () => unknown,
): string | null => {
  try {
    callback();
    return null;
  } catch (error: unknown) {
    if (!(error instanceof HttpsError)) {
      throw error;
    }

    const details =
      error.details as
        | Record<string, unknown>
        | undefined;

    return typeof details?.reason === "string" ?
      details.reason :
      null;
  }
};

test(
  "ride support payload accepts exact frozen input",
  () => {
    assert.deepEqual(
      validateRideSupportPayload({
        rideId: "ride_1",
        category: "safety",
        requestId,
      }),
      {
        rideId: "ride_1",
        category: "safety",
        requestId,
      },
    );
  },
);

test(
  "ride support payload accepts every frozen category",
  () => {
    assert.deepEqual(
      RIDE_SUPPORT_CATEGORIES,
      [
        "safety",
        "behavior",
        "fare",
        "route",
        "pickup",
        "no-show",
        "cancel",
        "vehicle",
        "technical",
        "lost-item",
      ],
    );

    for (
      const category of
      RIDE_SUPPORT_CATEGORIES
    ) {
      assert.equal(
        validateRideSupportPayload({
          rideId: "ride_1",
          category,
          requestId,
        }).category,
        category,
      );
    }
  },
);

test(
  "ride support payload rejects client authority fields",
  () => {
    for (
      const injected of [
        {participantId: "user-a"},
        {counterpartyId: "user-b"},
        {reporterRole: "passenger"},
        {rideStatus: "completed"},
        {createdAt: 123},
        {caseId: "attacker"},
      ]
    ) {
      assert.equal(
        reasonOf(() =>
          validateRideSupportPayload({
            rideId: "ride_1",
            category: "behavior",
            requestId,
            ...injected,
          }),
        ),
        "invalid_ride_support_payload",
      );
    }
  },
);

test(
  "ride support payload rejects missing fields",
  () => {
    assert.equal(
      reasonOf(() =>
        validateRideSupportPayload({
          rideId: "ride_1",
          category: "route",
        }),
      ),
      "invalid_ride_support_payload",
    );

    assert.equal(
      reasonOf(() =>
        validateRideSupportPayload({
          rideId: "ride_1",
          requestId,
        }),
      ),
      "invalid_ride_support_payload",
    );
  },
);

test(
  "ride support payload validates ride category and request id",
  () => {
    assert.equal(
      reasonOf(() =>
        validateRideSupportPayload({
          rideId: "ride/invalid",
          category: "route",
          requestId,
        }),
      ),
      "invalid_ride_id",
    );

    assert.equal(
      reasonOf(() =>
        validateRideSupportPayload({
          rideId: "ride_1",
          category: "invented",
          requestId,
        }),
      ),
      "invalid_ride_support_category",
    );

    assert.equal(
      reasonOf(() =>
        validateRideSupportPayload({
          rideId: "ride_1",
          category: "route",
          requestId: "short",
        }),
      ),
      "invalid_request_id",
    );
  },
);

test(
  "passenger reporter is server derived with assigned driver",
  () => {
    assert.deepEqual(
      deriveRideSupportParticipant(
        "passenger-a",
        "passenger-a",
        "driver-a",
        null,
      ),
      {
        role: "passenger",
        reporterId: "passenger-a",
        counterpartyId: "driver-a",
      },
    );
  },
);

test(
  "passenger reporter supports terminal ride with no assigned driver",
  () => {
    assert.deepEqual(
      deriveRideSupportParticipant(
        "passenger-a",
        "passenger-a",
        null,
        null,
      ),
      {
        role: "passenger",
        reporterId: "passenger-a",
        counterpartyId: null,
      },
    );
  },
);

test(
  "approved assigned driver reporter is server derived",
  () => {
    assert.deepEqual(
      deriveRideSupportParticipant(
        "driver-auth-user",
        "passenger-a",
        "driver-a",
        "driver-a",
      ),
      {
        role: "driver",
        reporterId: "driver-a",
        counterpartyId: "passenger-a",
      },
    );
  },
);

test(
  "outsider or mismatched driver cannot become reporter",
  () => {
    assert.equal(
      reasonOf(() =>
        deriveRideSupportParticipant(
          "outsider",
          "passenger-a",
          "driver-a",
          null,
        ),
      ),
      "ride_support_participant_required",
    );

    assert.equal(
      reasonOf(() =>
        deriveRideSupportParticipant(
          "other-driver-auth",
          "passenger-a",
          "driver-a",
          "driver-b",
        ),
      ),
      "ride_support_participant_required",
    );

    assert.equal(
      reasonOf(() =>
        deriveRideSupportParticipant(
          "driver-auth",
          "passenger-a",
          null,
          "driver-a",
        ),
      ),
      "ride_support_participant_required",
    );
  },
);

test(
  "support case id is deterministic and request scoped",
  () => {
    const first =
      rideSupportCaseId(
        "user-a",
        requestId,
      );

    const replay =
      rideSupportCaseId(
        "user-a",
        requestId,
      );

    const differentRequest =
      rideSupportCaseId(
        "user-a",
        "support_request_2234567890",
      );

    assert.equal(first, replay);
    assert.notEqual(first, differentRequest);
    assert.ok(first.length > 0);
  },
);
