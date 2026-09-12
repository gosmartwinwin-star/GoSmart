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
  deriveRideSupportParticipant,
  validateRideSupportPayload,
} from "./ride-support-authority.js";
import {
  parseRideStatus,
  rideOperationId,
  rideRequestDigest,
} from "./ride-lifecycle-helpers.js";
import type {
  RideStatus,
} from "./ride-lifecycle-helpers.js";

type RideActiveSupportDependencies = {
  firestore: Firestore;
  now?: () => Timestamp;
};

const ACTIVE_RIDE_SUPPORT_CALLABLE =
  "createActiveRideSupportCase";

export const ACTIVE_RIDE_SUPPORT_STATUSES:
readonly RideStatus[] = [
  "driverEnRoute",
  "driverArrived",
  "inProgress",
];

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
    "Active ride support request failed.",
    {reason},
  );

export const requireActiveRideSupportStatus = (
  value: unknown,
): RideStatus => {
  const status = parseRideStatus(value);

  if (
    !ACTIVE_RIDE_SUPPORT_STATUSES.includes(status)
  ) {
    throw failure(
      "failed-precondition",
      "ride_active_support_requires_active_ride",
    );
  }

  return status;
};

export const rideActiveSupportCaseId = (
  actorUid: string,
  requestId: string,
): string =>
  rideOperationId(
    actorUid,
    ACTIVE_RIDE_SUPPORT_CALLABLE,
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

export const createActiveRideSupportCaseForActor =
async (
  dependencies: RideActiveSupportDependencies,
  actorUid: string,
  rawInput: unknown,
): Promise<Record<string, unknown>> => {
  const input =
    validateRideSupportPayload(rawInput);

  const {firestore} = dependencies;

  const caseId =
    rideActiveSupportCaseId(
      actorUid,
      input.requestId,
    );

  const operationRef =
    firestore
      .collection("rideOperations")
      .doc(caseId);

  const digest =
    rideRequestDigest(
      ACTIVE_RIDE_SUPPORT_CALLABLE,
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

        requireActiveRideSupportStatus(
          data.status,
        );

        const passengerId =
          data.passengerId;

        const rawDriverId =
          data.driverId;

        if (
          typeof passengerId !== "string" ||
          passengerId.length === 0 ||
          typeof rawDriverId !== "string" ||
          rawDriverId.length === 0
        ) {
          throw failure(
            "internal",
            "ride_data_invalid",
          );
        }

        const driverId =
          rawDriverId;

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
              ACTIVE_RIDE_SUPPORT_CALLABLE,
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
      "ride_active_support_unavailable",
    );
  }
};
