import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";

import {
  deriveRideSupportParticipant,
  rideSupportCaseId,
  validateRideSupportPayload,
} from "./ride-support-authority.js";
import {
  ACTIVE_RIDE_SUPPORT_STATUSES,
  requireActiveRideSupportStatus,
  rideActiveSupportCaseId,
} from "./ride-active-support-authority.js";

const requestId =
  "active_support_request_1234567890";

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
  "active support statuses are exactly frozen active ride statuses",
  () => {
    assert.deepEqual(
      ACTIVE_RIDE_SUPPORT_STATUSES,
      [
        "driverEnRoute",
        "driverArrived",
        "inProgress",
      ],
    );
  },
);

test(
  "active support accepts every frozen active ride status",
  () => {
    for (
      const status of
      ACTIVE_RIDE_SUPPORT_STATUSES
    ) {
      assert.equal(
        requireActiveRideSupportStatus(status),
        status,
      );
    }
  },
);

test(
  "active support rejects matching and every terminal status",
  () => {
    for (
      const status of [
        "matching",
        "completed",
        "cancelled",
        "expired",
      ]
    ) {
      assert.equal(
        reasonOf(() =>
          requireActiveRideSupportStatus(status),
        ),
        "ride_active_support_requires_active_ride",
      );
    }
  },
);

test(
  "active support reuses exact ride support payload contract",
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

    assert.equal(
      reasonOf(() =>
        validateRideSupportPayload({
          rideId: "ride_1",
          category: "safety",
          requestId,
          counterpartyId: "attacker",
        }),
      ),
      "invalid_ride_support_payload",
    );
  },
);

test(
  "active support case id has separate callable namespace",
  () => {
    const terminalCaseId =
      rideSupportCaseId(
        "passenger-a",
        requestId,
      );

    const activeCaseId =
      rideActiveSupportCaseId(
        "passenger-a",
        requestId,
      );

    assert.notEqual(
      activeCaseId,
      terminalCaseId,
    );

    assert.equal(
      activeCaseId,
      rideActiveSupportCaseId(
        "passenger-a",
        requestId,
      ),
    );
  },
);

test(
  "active support participant identity remains server derived",
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

    assert.deepEqual(
      deriveRideSupportParticipant(
        "driver-auth-a",
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
