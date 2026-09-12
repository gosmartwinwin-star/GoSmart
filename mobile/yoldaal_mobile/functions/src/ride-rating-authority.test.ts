/* eslint-disable max-len */
import assert from "node:assert/strict";
import test from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  deriveRideRatingParticipant,
  serializeOwnRideRatingStatus,
  validateRideRatingPayload,
  validateRideRatingStatusPayload,
} from "./ride-rating-authority.js";

const requestId = "rating_request_1234567890";

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

    const details = error.details;

    if (
      typeof details === "object" &&
      details !== null &&
      !Array.isArray(details) &&
      typeof (
        details as Record<string, unknown>
      ).reason === "string"
    ) {
      return (
        details as Record<string, unknown>
      ).reason as string;
    }

    return null;
  }
};

test("ride rating payload accepts exact 1 to 5 input", () => {
  assert.deepEqual(
    validateRideRatingPayload({
      rideId: "ride_1",
      rating: 5,
      requestId,
    }),
    {
      rideId: "ride_1",
      rating: 5,
      requestId,
    },
  );
});

test("ride rating payload rejects extra or missing authority fields", () => {
  assert.equal(
    reasonOf(() =>
      validateRideRatingPayload({
        rideId: "ride_1",
        rating: 5,
        requestId,
        rateeId: "attacker-selected",
      }),
    ),
    "invalid_ride_rating_payload",
  );

  assert.equal(
    reasonOf(() =>
      validateRideRatingPayload({
        rideId: "ride_1",
        rating: 5,
        requestId,
        raterRole: "driver",
      }),
    ),
    "invalid_ride_rating_payload",
  );

  assert.equal(
    reasonOf(() =>
      validateRideRatingPayload({
        rideId: "ride_1",
        rating: 5,
      }),
    ),
    "invalid_ride_rating_payload",
  );
});

test("ride rating payload enforces integer range 1 through 5", () => {
  for (const rating of [0, 6, 1.5, -1]) {
    assert.equal(
      reasonOf(() =>
        validateRideRatingPayload({
          rideId: "ride_1",
          rating,
          requestId,
        }),
      ),
      "invalid_ride_rating",
    );
  }

  assert.equal(
    reasonOf(() =>
      validateRideRatingPayload({
        rideId: "ride_1",
        rating: "5",
        requestId,
      }),
    ),
    "invalid_ride_rating",
  );
});

test("ride rating payload reuses canonical ride and request id validation", () => {
  assert.equal(
    reasonOf(() =>
      validateRideRatingPayload({
        rideId: "ride/invalid",
        rating: 4,
        requestId,
      }),
    ),
    "invalid_ride_id",
  );

  assert.equal(
    reasonOf(() =>
      validateRideRatingPayload({
        rideId: "ride_1",
        rating: 4,
        requestId: "short",
      }),
    ),
    "invalid_request_id",
  );
});

test("passenger rating direction is server derived", () => {
  assert.deepEqual(
    deriveRideRatingParticipant(
      "passenger-1",
      "passenger-1",
      "driver-1",
      null,
    ),
    {
      role: "passenger",
      raterId: "passenger-1",
      rateeId: "driver-1",
    },
  );
});

test("driver rating direction requires matching approved driver identity", () => {
  assert.deepEqual(
    deriveRideRatingParticipant(
      "driver-auth-1",
      "passenger-1",
      "driver-1",
      "driver-1",
    ),
    {
      role: "driver",
      raterId: "driver-1",
      rateeId: "passenger-1",
    },
  );

  assert.equal(
    reasonOf(() =>
      deriveRideRatingParticipant(
        "other-auth",
        "passenger-1",
        "driver-1",
        "driver-other",
      ),
    ),
    "ride_rating_participant_required",
  );
});
test("ride rating status payload accepts only rideId", () => {
  assert.deepEqual(
    validateRideRatingStatusPayload({
      rideId: "ride_1",
    }),
    {
      rideId: "ride_1",
    },
  );

  assert.equal(
    reasonOf(() =>
      validateRideRatingStatusPayload({
        rideId: "ride_1",
        requestId: requestId,
      }),
    ),
    "invalid_ride_rating_payload",
  );

  assert.equal(
    reasonOf(() =>
      validateRideRatingStatusPayload({
        rideId: "ride/invalid",
      }),
    ),
    "invalid_ride_id",
  );
});

test("own ride rating status hides all participant identity when absent", () => {
  const result = serializeOwnRideRatingStatus(
    "ride_1",
    "passenger",
    "passenger-1",
    "driver-1",
    null,
  );

  assert.deepEqual(
    result,
    {
      rideId: "ride_1",
      hasSubmitted: false,
    },
  );
});

test("own ride rating status returns only own submitted score and time", () => {
  const result = serializeOwnRideRatingStatus(
    "ride_1",
    "driver",
    "driver-1",
    "passenger-1",
    {
      raterRole: "driver",
      raterId: "driver-1",
      rateeId: "passenger-1",
      rating: 4,
      createdAt: Timestamp.fromMillis(123456),
      privateServerField: "must-not-leak",
    },
  );

  assert.deepEqual(
    result,
    {
      rideId: "ride_1",
      hasSubmitted: true,
      rating: 4,
      submittedAtMillis: 123456,
    },
  );

  assert.deepEqual(
    Object.keys(result).sort(),
    [
      "hasSubmitted",
      "rating",
      "rideId",
      "submittedAtMillis",
    ],
  );
});

test("own ride rating status fails closed on inconsistent private document", () => {
  assert.equal(
    reasonOf(() =>
      serializeOwnRideRatingStatus(
        "ride_1",
        "passenger",
        "passenger-1",
        "driver-1",
        {
          raterRole: "driver",
          raterId: "driver-1",
          rateeId: "passenger-1",
          rating: 5,
          createdAt: Timestamp.fromMillis(123456),
        },
      ),
    ),
    "ride_rating_data_invalid",
  );

  assert.equal(
    reasonOf(() =>
      serializeOwnRideRatingStatus(
        "ride_1",
        "passenger",
        "passenger-1",
        "driver-1",
        {
          raterRole: "passenger",
          raterId: "passenger-1",
          rateeId: "driver-1",
          rating: 6,
          createdAt: Timestamp.fromMillis(123456),
        },
      ),
    ),
    "ride_rating_data_invalid",
  );
});
