/* eslint-disable max-len */
import {
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {
  loadApprovedDriverIdInTransaction,
} from "./ride-driver-identity.js";
import {
  parseRideStatus,
  rideOperationId,
  rideRequestDigest,
  TERMINAL_RIDE_STATUSES,
  validateRequestId,
} from "./ride-lifecycle-helpers.js";

export const RIDE_SUPPORT_CATEGORIES = [
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
] as const;

export type RideSupportCategory =
  typeof RIDE_SUPPORT_CATEGORIES[number];

export type RideSupportRole =
  "passenger" | "driver";

export type RideSupportInput = {
  rideId: string;
  category: RideSupportCategory;
  requestId: string;
};

export type RideSupportParticipant = {
  role: RideSupportRole;
  reporterId: string;
  counterpartyId: string | null;
};

type RideSupportDependencies = {
  firestore: Firestore;
  now?: () => Timestamp;
};

const failure = (
  code:
    | "invalid-argument"
    | "permission-denied"
    | "failed-precondition"
    | "aborted"
    | "unavailable"
    | "internal",
  reason: string,
): HttpsError =>
  new HttpsError(
    code,
    "Ride support request failed.",
    {reason},
  );

const exactObject = (
  value: unknown,
  keys: readonly string[],
): Record<string, unknown> => {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value)
  ) {
    throw failure(
      "invalid-argument",
      "invalid_ride_support_payload",
    );
  }

  const record =
    value as Record<string, unknown>;

  const actualKeys =
    Object.keys(record).sort();

  const expectedKeys =
    [...keys].sort();

  if (
    actualKeys.length !== expectedKeys.length ||
    actualKeys.some(
      (key, index) => key !== expectedKeys[index],
    )
  ) {
    throw failure(
      "invalid-argument",
      "invalid_ride_support_payload",
    );
  }

  return record;
};

export const validateRideSupportPayload = (
  value: unknown,
): RideSupportInput => {
  const input = exactObject(
    value,
    ["rideId", "category", "requestId"],
  );

  if (
    typeof input.rideId !== "string" ||
    input.rideId.length === 0 ||
    input.rideId.length > 128 ||
    !/^[A-Za-z0-9_-]+$/u.test(input.rideId)
  ) {
    throw failure(
      "invalid-argument",
      "invalid_ride_id",
    );
  }

  if (
    typeof input.category !== "string" ||
    !RIDE_SUPPORT_CATEGORIES.includes(
      input.category as RideSupportCategory,
    )
  ) {
    throw failure(
      "invalid-argument",
      "invalid_ride_support_category",
    );
  }

  return {
    rideId: input.rideId,
    category:
      input.category as RideSupportCategory,
    requestId:
      validateRequestId(input.requestId),
  };
};

export const deriveRideSupportParticipant = (
  actorUid: string,
  passengerId: string,
  driverId: string | null,
  approvedDriverId: string | null,
): RideSupportParticipant => {
  if (actorUid === passengerId) {
    return {
      role: "passenger",
      reporterId: passengerId,
      counterpartyId: driverId,
    };
  }

  if (
    driverId !== null &&
    approvedDriverId !== null &&
    approvedDriverId === driverId
  ) {
    return {
      role: "driver",
      reporterId: driverId,
      counterpartyId: passengerId,
    };
  }

  throw failure(
    "permission-denied",
    "ride_support_participant_required",
  );
};

export const rideSupportCaseId = (
  actorUid: string,
  requestId: string,
): string =>
  rideOperationId(
    actorUid,
    "createRideSupportCase",
    requestId,
  );

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

export const createRideSupportCaseForActor = async (
  dependencies: RideSupportDependencies,
  actorUid: string,
  rawInput: unknown,
): Promise<Record<string, unknown>> => {
  const input =
    validateRideSupportPayload(rawInput);

  const {firestore} = dependencies;

  const caseId =
    rideSupportCaseId(
      actorUid,
      input.requestId,
    );

  const operationRef =
    firestore
      .collection("rideOperations")
      .doc(caseId);

  const digest =
    rideRequestDigest(
      "createRideSupportCase",
      input,
    );

  const existingOperation =
    await operationRef.get();

  if (existingOperation.exists) {
    return replayOperation(
      existingOperation.data() ?? {},
      digest,
    );
  }

  const rideRef =
    firestore
      .collection("rides")
      .doc(input.rideId);

  const caseRef =
    rideRef
      .collection("supportCases")
      .doc(caseId);

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

        const passengerId =
          data.passengerId;

        const rawDriverId =
          data.driverId;

        if (
          typeof passengerId !== "string" ||
          passengerId.length === 0 ||
          !(
            rawDriverId === null ||
            (
              typeof rawDriverId === "string" &&
              rawDriverId.length > 0
            )
          )
        ) {
          throw failure(
            "internal",
            "ride_data_invalid",
          );
        }

        const driverId =
          rawDriverId as string | null;

        let approvedDriverId:
          string | null = null;

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
                "ride_support_participant_required",
              );
            }

            throw error;
          }
        }

        const participant =
          deriveRideSupportParticipant(
            actorUid,
            passengerId,
            driverId,
            approvedDriverId,
          );

        const rideStatus =
          parseRideStatus(data.status);

        if (
          !TERMINAL_RIDE_STATUSES.includes(
            rideStatus,
          )
        ) {
          throw failure(
            "failed-precondition",
            "ride_support_requires_terminal_ride",
          );
        }

        const result = {
          rideId: input.rideId,
          caseId,
          category: input.category,
          createdAtMillis: now.toMillis(),
        };

        transaction.create(
          caseRef,
          {
            reporterRole: participant.role,
            reporterId: participant.reporterId,
            counterpartyId:
              participant.counterpartyId,
            category: input.category,
            createdAt: now,
          },
        );

        transaction.create(
          operationRef,
          {
            actorUid,
            callableName:
              "createRideSupportCase",
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
      if (
        recoveryError instanceof HttpsError
      ) {
        throw recoveryError;
      }
    }

    throw failure(
      "unavailable",
      "ride_support_unavailable",
    );
  }
};
