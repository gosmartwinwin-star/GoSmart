import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  validateRideHistoryPayload,
} from "./ride-history-helpers.js";

const reason = (callback: () => unknown): string | null => {
  try {
    callback();
    return null;
  } catch (error) {
    if (error instanceof HttpsError &&
        typeof error.details === "object" &&
        error.details !== null &&
        "reason" in error.details) {
      return String(
        (error.details as Record<string, unknown>).reason,
      );
    }
    throw error;
  }
};

test("ride history payload accepts exact passenger request", () => {
  assert.deepEqual(
    validateRideHistoryPayload({
      scope: "passenger",
      pageSize: 20,
      cursor: null,
    }),
    {
      scope: "passenger",
      pageSize: 20,
      cursor: null,
    },
  );
});

test("ride history payload accepts exact driver cursor", () => {
  assert.deepEqual(
    validateRideHistoryPayload({
      scope: "driver",
      pageSize: 10,
      cursor: {
        updatedAtMillis: 123456789,
        rideId: "ride_123",
      },
    }),
    {
      scope: "driver",
      pageSize: 10,
      cursor: {
        updatedAtMillis: 123456789,
        rideId: "ride_123",
      },
    },
  );
});

test("ride history payload rejects injected participant ids", () => {
  for (const key of [
    "passengerId",
    "driverId",
    "authUserId",
    "uid",
  ]) {
    assert.equal(
      reason(() => validateRideHistoryPayload({
        scope: "passenger",
        pageSize: 20,
        cursor: null,
        [key]: "injected",
      })),
      "invalid_ride_history_payload",
    );
  }
});

test("ride history payload rejects invalid scopes and sizes", () => {
  for (const scope of [null, "", "admin", "all"]) {
    assert.equal(
      reason(() => validateRideHistoryPayload({
        scope,
        pageSize: 20,
        cursor: null,
      })),
      "invalid_ride_history_payload",
    );
  }

  for (const pageSize of [0, 21, 1.5, "10"]) {
    assert.equal(
      reason(() => validateRideHistoryPayload({
        scope: "passenger",
        pageSize,
        cursor: null,
      })),
      "invalid_ride_history_payload",
    );
  }
});

test("ride history payload rejects malformed cursor", () => {
  for (const cursor of [
    {},
    {updatedAtMillis: -1, rideId: "ride-1"},
    {updatedAtMillis: 1.5, rideId: "ride-1"},
    {updatedAtMillis: 1, rideId: ""},
    {updatedAtMillis: 1, rideId: "bad/id"},
    {updatedAtMillis: 1, rideId: "ride-1", uid: "injected"},
  ]) {
    assert.equal(
      reason(() => validateRideHistoryPayload({
        scope: "passenger",
        pageSize: 20,
        cursor,
      })),
      "invalid_ride_history_payload",
    );
  }
});
