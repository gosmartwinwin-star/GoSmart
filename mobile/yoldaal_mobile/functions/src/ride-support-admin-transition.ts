import {Timestamp, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {requireYoldaAlAdmin} from "./admin-authorization-helpers.js";

type SupportStatus = "new" | "inReview" | "resolved";

type AdminTransitionInput = {
  rideId: string;
  caseId: string;
  targetStatus: "inReview" | "resolved";
  expectedUpdatedAtMillis: number;
  requestId: string;
};

const STORED_STATUSES = new Set<SupportStatus>([
  "new",
  "inReview",
  "resolved",
]);

const invalidPayload = (): never => {
  throw new HttpsError(
    "invalid-argument",
    "Ride support admin transition failed.",
    {reason: "invalid_ride_support_admin_transition_payload"},
  );
};

const invalidData = (): never => {
  throw new HttpsError(
    "internal",
    "Ride support admin transition failed.",
    {reason: "ride_support_case_data_invalid"},
  );
};

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const safeId = (value: unknown): string => {
  if (
    typeof value !== "string" ||
    value.trim().length === 0 ||
    value.trim().length > 128 ||
    value.includes("/")
  ) {
    return invalidPayload();
  }
  return value.trim();
};

const requestId = (value: unknown): string => {
  const id = safeId(value);
  if (!/^[A-Za-z0-9_-]+$/.test(id)) return invalidPayload();
  return id;
};

const parseStoredStatus = (value: unknown): SupportStatus => {
  if (
    typeof value !== "string" ||
    !STORED_STATUSES.has(value as SupportStatus)
  ) {
    return invalidData();
  }
  return value as SupportStatus;
};

export const parseRideSupportAdminTransitionInput = (
  raw: unknown,
): AdminTransitionInput => {
  if (!isRecord(raw)) return invalidPayload();
  const keys = Object.keys(raw);
  const expectedKeys = new Set([
    "rideId",
    "caseId",
    "targetStatus",
    "expectedUpdatedAtMillis",
    "requestId",
  ]);
  if (
    keys.length !== expectedKeys.size ||
    keys.some((key) => !expectedKeys.has(key))
  ) {
    return invalidPayload();
  }

  const targetStatus = raw.targetStatus;
  const expectedUpdatedAtMillis = raw.expectedUpdatedAtMillis;
  if (
    (targetStatus !== "inReview" && targetStatus !== "resolved") ||
    typeof expectedUpdatedAtMillis !== "number" ||
    !Number.isSafeInteger(expectedUpdatedAtMillis) ||
    expectedUpdatedAtMillis < 0
  ) {
    return invalidPayload();
  }

  return {
    rideId: safeId(raw.rideId),
    caseId: safeId(raw.caseId),
    targetStatus,
    expectedUpdatedAtMillis,
    requestId: requestId(raw.requestId),
  };
};

export const determineRideSupportAdminTransition = (
  currentStatus: SupportStatus,
  targetStatus: AdminTransitionInput["targetStatus"],
): {
  fromStatus: SupportStatus;
  toStatus: AdminTransitionInput["targetStatus"];
} => {
  if (
    (currentStatus === "new" && targetStatus === "inReview") ||
    (currentStatus === "inReview" && targetStatus === "resolved")
  ) {
    return {fromStatus: currentStatus, toStatus: targetStatus};
  }
  throw new HttpsError(
    "failed-precondition",
    "Ride support admin transition failed.",
    {reason: "invalid_ride_support_case_transition"},
  );
};

export const buildRideSupportAdminEvent = (
  input: AdminTransitionInput,
  fromStatus: SupportStatus,
  adminUid: string,
  actedAt: Timestamp,
) => ({
  eventType: "statusTransition",
  requestId: input.requestId,
  expectedUpdatedAtMillis: input.expectedUpdatedAtMillis,
  fromStatus,
  toStatus: input.targetStatus,
  adminUid,
  actedAt,
});

export const transitionRideSupportCaseForAdmin = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 15,
    memory: "256MiB",
    maxInstances: 3,
  },
  async (request) => {
    const adminUid = requireYoldaAlAdmin(request.auth);
    const input = parseRideSupportAdminTransitionInput(request.data);
    const firestore = getFirestore();
    const caseRef = firestore
      .collection("rides")
      .doc(input.rideId)
      .collection("supportCases")
      .doc(input.caseId);
    const eventRef = caseRef.collection("adminEvents").doc(input.requestId);

    try {
      return await firestore.runTransaction(async (transaction) => {
        const [caseSnapshot, eventSnapshot] = await Promise.all([
          transaction.get(caseRef),
          transaction.get(eventRef),
        ]);

        if (eventSnapshot.exists) {
          const event = eventSnapshot.data();
          if (
            event === undefined ||
            event.requestId !== input.requestId ||
            event.toStatus !== input.targetStatus ||
            event.expectedUpdatedAtMillis !== input.expectedUpdatedAtMillis ||
            !(event.actedAt instanceof Timestamp)
          ) {
            throw new HttpsError(
              "failed-precondition",
              "Ride support admin transition failed.",
              {reason: "ride_support_admin_request_id_conflict"},
            );
          }
          return {
            status: input.targetStatus,
            updatedAtMillis: event.actedAt.toMillis(),
            idempotent: true,
          };
        }

        if (!caseSnapshot.exists) {
          throw new HttpsError(
            "not-found",
            "Ride support case was not found.",
            {reason: "ride_support_case_not_found"},
          );
        }

        const data = caseSnapshot.data();
        if (data === undefined || !(data.updatedAt instanceof Timestamp)) {
          return invalidData();
        }
        const currentStatus = parseStoredStatus(data.status);
        if (data.updatedAt.toMillis() !== input.expectedUpdatedAtMillis) {
          throw new HttpsError(
            "failed-precondition",
            "Ride support case changed.",
            {reason: "stale_ride_support_case"},
          );
        }

        const transition = determineRideSupportAdminTransition(
          currentStatus,
          input.targetStatus,
        );
        const now = Timestamp.now();
        transaction.update(caseRef, {
          status: transition.toStatus,
          updatedAt: now,
        });
        transaction.set(
          eventRef,
          buildRideSupportAdminEvent(
            input,
            transition.fromStatus,
            adminUid,
            now,
          ),
        );

        return {
          status: transition.toStatus,
          updatedAtMillis: now.toMillis(),
          idempotent: false,
        };
      });
    } catch (error: unknown) {
      if (error instanceof HttpsError) throw error;
      throw new HttpsError(
        "unavailable",
        "Ride support admin transition failed.",
        {reason: "ride_support_admin_transition_failed"},
      );
    }
  },
);
