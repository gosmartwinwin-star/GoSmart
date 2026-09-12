/* eslint-disable max-len */
import {Firestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  loadApprovedDriverId,
  loadApprovedDriverIdInTransaction,
} from "./ride-driver-identity.js";
import {
  parseRideStatus,
  rideOperationId,
  rideRequestDigest,
  validateRequestId,
} from "./ride-lifecycle-helpers.js";

export type RideRatingRole = "passenger" | "driver";

export type RideRatingInput = {
  rideId: string;
  rating: number;
  requestId: string;
};

type RideRatingDependencies = {
  firestore: Firestore;
  now?: () => Timestamp;
};

type RideRatingParticipant = {
  role: RideRatingRole;
  raterId: string;
  rateeId: string;
};

const failure = (
  code:
    | "invalid-argument"
    | "failed-precondition"
    | "permission-denied"
    | "internal"
    | "aborted"
    | "unavailable",
  reason: string,
): HttpsError =>
  new HttpsError(code, "Ride rating operation failed.", {reason});

const exactObject = (
  value: unknown,
  keys: readonly string[],
): Record<string, unknown> => {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value) ||
    Object.getPrototypeOf(value) !== Object.prototype
  ) {
    throw failure("invalid-argument", "invalid_ride_rating_payload");
  }

  const input = value as Record<string, unknown>;
  const actualKeys = Object.keys(input);

  if (
    actualKeys.length !== keys.length ||
    keys.some((key) => !actualKeys.includes(key))
  ) {
    throw failure("invalid-argument", "invalid_ride_rating_payload");
  }

  return input;
};

export const validateRideRatingPayload = (
  value: unknown,
): RideRatingInput => {
  const input = exactObject(
    value,
    ["rideId", "rating", "requestId"],
  );

  if (
    typeof input.rideId !== "string" ||
    input.rideId.length === 0 ||
    input.rideId.length > 128 ||
    !/^[A-Za-z0-9_-]+$/u.test(input.rideId)
  ) {
    throw failure("invalid-argument", "invalid_ride_id");
  }

  if (
    typeof input.rating !== "number" ||
    !Number.isInteger(input.rating) ||
    input.rating < 1 ||
    input.rating > 5
  ) {
    throw failure("invalid-argument", "invalid_ride_rating");
  }

  return {
    rideId: input.rideId,
    rating: input.rating,
    requestId: validateRequestId(input.requestId),
  };
};

export const deriveRideRatingParticipant = (
  actorUid: string,
  passengerId: string,
  driverId: string,
  approvedDriverId: string | null,
): RideRatingParticipant => {
  if (actorUid === passengerId) {
    return {
      role: "passenger",
      raterId: passengerId,
      rateeId: driverId,
    };
  }

  if (
    approvedDriverId !== null &&
    approvedDriverId === driverId
  ) {
    return {
      role: "driver",
      raterId: driverId,
      rateeId: passengerId,
    };
  }

  throw failure(
    "permission-denied",
    "ride_rating_participant_required",
  );
};

const replayOperation = (
  data: Record<string, unknown>,
  digest: string,
): Record<string, unknown> => {
  if (data.requestDigest !== digest) {
    throw failure(
      "failed-precondition",
      "idempotency_payload_mismatch",
    );
  }

  if (
    data.status === "completed" &&
    typeof data.result === "object" &&
    data.result !== null &&
    !Array.isArray(data.result)
  ) {
    return data.result as Record<string, unknown>;
  }

  throw failure(
    "aborted",
    "ride_operation_in_progress",
  );
};

export type RideRatingStatusInput = {
  rideId: string;
};

export const validateRideRatingStatusPayload = (
  value: unknown,
): RideRatingStatusInput => {
  const input = exactObject(value, ["rideId"]);

  if (
    typeof input.rideId !== "string" ||
    input.rideId.length === 0 ||
    input.rideId.length > 128 ||
    !/^[A-Za-z0-9_-]+$/u.test(input.rideId)
  ) {
    throw failure("invalid-argument", "invalid_ride_id");
  }

  return {rideId: input.rideId};
};

export const serializeOwnRideRatingStatus = (
  rideId: string,
  role: RideRatingRole,
  raterId: string,
  rateeId: string,
  data: Record<string, unknown> | null,
): Record<string, unknown> => {
  if (data === null) {
    return {
      rideId,
      hasSubmitted: false,
    };
  }

  const rating = data.rating;
  const createdAt = data.createdAt;

  if (
    data.raterRole !== role ||
    data.raterId !== raterId ||
    data.rateeId !== rateeId ||
    typeof rating !== "number" ||
    !Number.isInteger(rating) ||
    rating < 1 ||
    rating > 5 ||
    !(createdAt instanceof Timestamp)
  ) {
    throw failure(
      "internal",
      "ride_rating_data_invalid",
    );
  }

  return {
    rideId,
    hasSubmitted: true,
    rating,
    submittedAtMillis: createdAt.toMillis(),
  };
};

export const getRideRatingStatusForActor = async (
  dependencies: RideRatingDependencies,
  actorUid: string,
  rawInput: unknown,
): Promise<Record<string, unknown>> => {
  const input =
    validateRideRatingStatusPayload(rawInput);

  const {firestore} = dependencies;

  const rideRef =
    firestore.collection("rides").doc(input.rideId);

  const ride = await rideRef.get();

  if (!ride.exists) {
    throw new HttpsError(
      "not-found",
      "Ride was not found.",
      {reason: "ride_not_found"},
    );
  }

  const data = ride.data() ?? {};
  const passengerId = data.passengerId;
  const driverId = data.driverId;

  if (
    typeof passengerId !== "string" ||
    passengerId.length === 0 ||
    typeof driverId !== "string" ||
    driverId.length === 0
  ) {
    throw failure(
      "internal",
      "ride_data_invalid",
    );
  }

  let approvedDriverId: string | null = null;

  if (actorUid !== passengerId) {
    try {
      approvedDriverId =
        await loadApprovedDriverId(
          firestore,
          actorUid,
        );
    } catch (error: unknown) {
      if (
        error instanceof HttpsError &&
        error.code === "permission-denied"
      ) {
        throw failure(
          "permission-denied",
          "ride_rating_participant_required",
        );
      }

      throw error;
    }
  }

  const participant =
    deriveRideRatingParticipant(
      actorUid,
      passengerId,
      driverId,
      approvedDriverId,
    );

  if (
    parseRideStatus(data.status) !==
    "completed"
  ) {
    throw failure(
      "failed-precondition",
      "ride_rating_requires_completed_ride",
    );
  }

  const rating = await rideRef
    .collection("ratings")
    .doc(participant.role)
    .get();

  return serializeOwnRideRatingStatus(
    ride.id,
    participant.role,
    participant.raterId,
    participant.rateeId,
    rating.exists ? (rating.data() ?? {}) : null,
  );
};
export const submitRideRatingForActor = async (
  dependencies: RideRatingDependencies,
  actorUid: string,
  rawInput: unknown,
): Promise<Record<string, unknown>> => {
  const input = validateRideRatingPayload(rawInput);
  const {firestore} = dependencies;

  const operationRef = firestore
    .collection("rideOperations")
    .doc(
      rideOperationId(
        actorUid,
        "submitRideRating",
        input.requestId,
      ),
    );

  const digest =
    rideRequestDigest("submitRideRating", input);

  const existingOperation = await operationRef.get();

  if (existingOperation.exists) {
    return replayOperation(
      existingOperation.data() ?? {},
      digest,
    );
  }

  const rideRef =
    firestore.collection("rides").doc(input.rideId);

  const now =
    dependencies.now?.() ?? Timestamp.now();

  try {
    return await firestore.runTransaction(
      async (transaction) => {
        const operation =
          await transaction.get(operationRef);

        if (operation.exists) {
          return replayOperation(
            operation.data() ?? {},
            digest,
          );
        }

        const ride =
          await transaction.get(rideRef);

        if (!ride.exists) {
          throw new HttpsError(
            "not-found",
            "Ride was not found.",
            {reason: "ride_not_found"},
          );
        }

        const data = ride.data() ?? {};

        if (
          parseRideStatus(data.status) !==
          "completed"
        ) {
          throw failure(
            "failed-precondition",
            "ride_rating_requires_completed_ride",
          );
        }

        const passengerId = data.passengerId;
        const driverId = data.driverId;

        if (
          typeof passengerId !== "string" ||
          passengerId.length === 0 ||
          typeof driverId !== "string" ||
          driverId.length === 0
        ) {
          throw failure(
            "internal",
            "ride_data_invalid",
          );
        }

        let approvedDriverId: string | null = null;

        if (actorUid !== passengerId) {
          try {
            approvedDriverId =
              await loadApprovedDriverIdInTransaction(
                firestore,
                actorUid,
                transaction,
              );
          } catch (error: unknown) {
            if (
              error instanceof HttpsError &&
              error.code === "permission-denied"
            ) {
              throw failure(
                "permission-denied",
                "ride_rating_participant_required",
              );
            }

            throw error;
          }
        }

        const participant =
          deriveRideRatingParticipant(
            actorUid,
            passengerId,
            driverId,
            approvedDriverId,
          );

        const ratingRef =
          rideRef
            .collection("ratings")
            .doc(participant.role);

        const existingRating =
          await transaction.get(ratingRef);

        if (existingRating.exists) {
          throw failure(
            "failed-precondition",
            "rating_already_submitted",
          );
        }

        const result = {
          rideId: ride.id,
          rating: input.rating,
          raterRole: participant.role,
          submittedAtMillis: now.toMillis(),
        };

        transaction.create(
          ratingRef,
          {
            raterRole: participant.role,
            raterId: participant.raterId,
            rateeId: participant.rateeId,
            rating: input.rating,
            createdAt: now,
          },
        );

        transaction.create(
          operationRef,
          {
            actorUid,
            callableName: "submitRideRating",
            requestDigest: digest,
            status: "completed",
            result,
            createdAt: now,
            updatedAt: now,
          },
        );

        return result;
      },
    );
  } catch (error: unknown) {
    if (error instanceof HttpsError) {
      throw error;
    }

    try {
      const committedOperation =
        await operationRef.get();

      if (committedOperation.exists) {
        return replayOperation(
          committedOperation.data() ?? {},
          digest,
        );
      }
    } catch (recoveryError: unknown) {
      if (recoveryError instanceof HttpsError) {
        throw recoveryError;
      }
    }

    throw failure(
      "unavailable",
      "ride_rating_persistence_failed",
    );
  }
};
