/* eslint-disable max-len */
import {createHash} from "node:crypto";
import {
  FieldPath,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
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
import type {
  RideStatus,
} from "./ride-lifecycle-helpers.js";

export const SEND_RIDE_CHAT_MESSAGE_CALLABLE =
  "sendRideChatMessage";

export const LIST_RIDE_CHAT_MESSAGES_CALLABLE =
  "listRideChatMessages";

export const RIDE_CHAT_TEXT_MAX_CHARACTERS = 1000;
export const RIDE_CHAT_RETENTION_MILLIS =
  30 * 24 * 60 * 60 * 1000;
export const RIDE_CHAT_TERMINAL_READ_MILLIS =
  24 * 60 * 60 * 1000;

export const RIDE_CHAT_RATE_CAPACITY = 10;
export const RIDE_CHAT_RATE_REFILL_MILLIS = 2000;

export const RIDE_CHAT_PAGE_SIZE_DEFAULT = 50;
export const RIDE_CHAT_PAGE_SIZE_MAX = 50;

export const RIDE_CHAT_SEND_STATUSES:
readonly RideStatus[] = [
  "driverEnRoute",
  "driverArrived",
  "inProgress",
];

export const RIDE_CHAT_TERMINAL_STATUSES:
readonly RideStatus[] = [
  "completed",
  "cancelled",
  "expired",
];

export type RideChatSenderRole =
  | "passenger"
  | "driver";

export type RideChatSendInput = {
  rideId: string;
  requestId: string;
  text: string;
};

export type RideChatCursor = {
  expiresAtMillis: number;
  createdAtMillis: number;
  messageId: string;
};

export type RideChatListInput = {
  rideId: string;
  pageSize: number;
  cursor: RideChatCursor | null;
};

export type RideChatParticipant = {
  role: RideChatSenderRole;
};

export type RideChatRateLimitState = {
  tokens: number;
  lastRefillAt: Timestamp;
  expiresAt: Timestamp;
};

export type RideChatMessageResult = {
  messageId: string;
  kind: "text";
  senderRole: RideChatSenderRole;
  assignmentRound: number;
  text: string;
  createdAtMillis: number;
  expiresAtMillis: number;
};

type RideChatDependencies = {
  firestore: Firestore;
  now?: () => Timestamp;
};

const failure = (
  code:
    | "invalid-argument"
    | "permission-denied"
    | "failed-precondition"
    | "resource-exhausted"
    | "internal"
    | "aborted"
    | "unavailable",
  reason: string,
): HttpsError =>
  new HttpsError(
    code,
    "Ride chat operation failed.",
    {reason},
  );

const exactObject = (
  value: unknown,
  requiredKeys: readonly string[],
  optionalKeys: readonly string[],
  reason: string,
): Record<string, unknown> => {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value) ||
    Object.getPrototypeOf(value) !== Object.prototype
  ) {
    throw failure("invalid-argument", reason);
  }

  const input = value as Record<string, unknown>;
  const actualKeys = Object.keys(input);
  const allowedKeys = [
    ...requiredKeys,
    ...optionalKeys,
  ];

  if (
    requiredKeys.some(
      (key) => !actualKeys.includes(key),
    ) ||
    actualKeys.some(
      (key) => !allowedKeys.includes(key),
    )
  ) {
    throw failure("invalid-argument", reason);
  }

  return input;
};

const validateRideId = (
  value: unknown,
): string => {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > 128 ||
    !/^[A-Za-z0-9_-]+$/u.test(value)
  ) {
    throw failure(
      "invalid-argument",
      "invalid_ride_id",
    );
  }

  return value;
};

const validateMessageId = (
  value: unknown,
): string => {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > 128 ||
    !/^[A-Za-z0-9_-]+$/u.test(value)
  ) {
    throw failure(
      "invalid-argument",
      "invalid_ride_chat_cursor",
    );
  }

  return value;
};

const validateCursorMillis = (
  value: unknown,
): number => {
  if (
    typeof value !== "number" ||
    !Number.isFinite(value) ||
    !Number.isInteger(value) ||
    value < 0
  ) {
    throw failure(
      "invalid-argument",
      "invalid_ride_chat_cursor",
    );
  }

  return value;
};

const requirePositiveInteger = (
  value: unknown,
  reason: string,
): number => {
  if (
    typeof value !== "number" ||
    !Number.isInteger(value) ||
    value < 1
  ) {
    throw failure(
      "internal",
      reason,
    );
  }

  return value;
};

const requireNonEmptyString = (
  value: unknown,
  reason: string,
): string => {
  if (
    typeof value !== "string" ||
    value.length === 0
  ) {
    throw failure(
      "internal",
      reason,
    );
  }

  return value;
};

export const validateRideChatSendPayload = (
  value: unknown,
): RideChatSendInput => {
  const input = exactObject(
    value,
    ["rideId", "requestId", "text"],
    [],
    "invalid_ride_chat_send_payload",
  );

  if (typeof input.text !== "string") {
    throw failure(
      "invalid-argument",
      "invalid_ride_chat_text",
    );
  }

  const text = input.text.trim();

  if (
    text.length === 0 ||
    [...text].length >
      RIDE_CHAT_TEXT_MAX_CHARACTERS
  ) {
    throw failure(
      "invalid-argument",
      "invalid_ride_chat_text",
    );
  }

  return {
    rideId: validateRideId(input.rideId),
    requestId:
      validateRequestId(input.requestId),
    text,
  };
};

export const validateRideChatListPayload = (
  value: unknown,
): RideChatListInput => {
  const input = exactObject(
    value,
    ["rideId"],
    ["pageSize", "cursor"],
    "invalid_ride_chat_list_payload",
  );

  let pageSize =
    RIDE_CHAT_PAGE_SIZE_DEFAULT;

  if (input.pageSize !== undefined) {
    if (
      typeof input.pageSize !== "number" ||
      !Number.isInteger(input.pageSize) ||
      input.pageSize < 1 ||
      input.pageSize >
        RIDE_CHAT_PAGE_SIZE_MAX
    ) {
      throw failure(
        "invalid-argument",
        "invalid_ride_chat_page_size",
      );
    }

    pageSize = input.pageSize;
  }

  let cursor: RideChatCursor | null = null;

  if (input.cursor !== undefined) {
    const rawCursor = exactObject(
      input.cursor,
      [
        "expiresAtMillis",
        "createdAtMillis",
        "messageId",
      ],
      [],
      "invalid_ride_chat_cursor",
    );

    cursor = {
      expiresAtMillis:
        validateCursorMillis(
          rawCursor.expiresAtMillis,
        ),
      createdAtMillis:
        validateCursorMillis(
          rawCursor.createdAtMillis,
        ),
      messageId:
        validateMessageId(
          rawCursor.messageId,
        ),
    };
  }

  return {
    rideId: validateRideId(input.rideId),
    pageSize,
    cursor,
  };
};

export const deriveRideChatParticipant = (
  actorUid: string,
  passengerId: string,
  currentDriverId: string | null,
  approvedDriverId: string | null,
): RideChatParticipant => {
  if (actorUid === passengerId) {
    return {role: "passenger"};
  }

  if (
    currentDriverId !== null &&
    approvedDriverId !== null &&
    approvedDriverId === currentDriverId
  ) {
    return {role: "driver"};
  }

  throw failure(
    "permission-denied",
    "ride_chat_participant_required",
  );
};

export const requireRideChatSendStatus = (
  value: unknown,
): RideStatus => {
  const status = parseRideStatus(value);

  if (!RIDE_CHAT_SEND_STATUSES.includes(status)) {
    throw failure(
      "failed-precondition",
      "ride_chat_send_unavailable",
    );
  }

  return status;
};

const terminalTimestamp = (
  status: RideStatus,
  data: Record<string, unknown>,
): Timestamp => {
  let value: unknown;

  if (status === "completed") {
    value = data.completedAt;
  } else if (status === "cancelled") {
    value = data.cancelledAt;
  } else if (status === "expired") {
    value = data.expiredAt;
  } else {
    throw failure(
      "internal",
      "ride_chat_terminal_data_invalid",
    );
  }

  if (!(value instanceof Timestamp)) {
    throw failure(
      "internal",
      "ride_chat_terminal_data_invalid",
    );
  }

  return value;
};

export const requireRideChatReadWindow = (
  data: Record<string, unknown>,
  now: Timestamp,
): RideStatus => {
  const status = parseRideStatus(data.status);

  if (RIDE_CHAT_SEND_STATUSES.includes(status)) {
    return status;
  }

  if (!RIDE_CHAT_TERMINAL_STATUSES.includes(status)) {
    throw failure(
      "failed-precondition",
      "ride_chat_read_unavailable",
    );
  }

  const endedAt =
    terminalTimestamp(status, data);

  if (
    now.toMillis() >=
    endedAt.toMillis() +
      RIDE_CHAT_TERMINAL_READ_MILLIS
  ) {
    throw failure(
      "failed-precondition",
      "ride_chat_terminal_read_window_closed",
    );
  }

  return status;
};

export const rideChatRateLimitId = (
  rideId: string,
  actorUid: string,
): string =>
  createHash("sha256")
    .update(
      `ride-chat-rate:${rideId}:${actorUid}`,
    )
    .digest("hex");

export const consumeRideChatRateLimit = (
  data: Record<string, unknown> | null,
  now: Timestamp,
): RideChatRateLimitState => {
  let tokens = RIDE_CHAT_RATE_CAPACITY;
  let lastRefillAt = now;

  if (data !== null) {
    const rawTokens = data.tokens;
    const rawLastRefillAt = data.lastRefillAt;
    const rawExpiresAt = data.expiresAt;

    if (
      typeof rawTokens !== "number" ||
      !Number.isInteger(rawTokens) ||
      rawTokens < 0 ||
      rawTokens > RIDE_CHAT_RATE_CAPACITY ||
      !(rawLastRefillAt instanceof Timestamp) ||
      !(rawExpiresAt instanceof Timestamp)
    ) {
      throw failure(
        "internal",
        "ride_chat_rate_state_invalid",
      );
    }

    if (
      rawExpiresAt.toMillis() >
      now.toMillis()
    ) {
      tokens = rawTokens;
      lastRefillAt = rawLastRefillAt;

      const elapsedMillis = Math.max(
        0,
        now.toMillis() -
          rawLastRefillAt.toMillis(),
      );

      const refillSteps = Math.floor(
        elapsedMillis /
          RIDE_CHAT_RATE_REFILL_MILLIS,
      );

      if (refillSteps > 0) {
        const refilledTokens = Math.min(
          RIDE_CHAT_RATE_CAPACITY,
          tokens + refillSteps,
        );

        if (
          refilledTokens ===
          RIDE_CHAT_RATE_CAPACITY
        ) {
          lastRefillAt = now;
        } else {
          lastRefillAt =
            Timestamp.fromMillis(
              rawLastRefillAt.toMillis() +
                refillSteps *
                  RIDE_CHAT_RATE_REFILL_MILLIS,
            );
        }

        tokens = refilledTokens;
      } else if (
        tokens === RIDE_CHAT_RATE_CAPACITY
      ) {
        lastRefillAt = now;
      }
    }
  }

  if (tokens < 1) {
    throw failure(
      "resource-exhausted",
      "ride_chat_rate_limited",
    );
  }

  return {
    tokens: tokens - 1,
    lastRefillAt,
    expiresAt: Timestamp.fromMillis(
      now.toMillis() +
        RIDE_CHAT_RETENTION_MILLIS,
    ),
  };
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
    return data.result as
      Record<string, unknown>;
  }

  throw failure(
    "aborted",
    "ride_operation_in_progress",
  );
};

const loadReadParticipant = async (
  firestore: Firestore,
  actorUid: string,
  passengerId: string,
  currentDriverId: string | null,
): Promise<RideChatParticipant> => {
  if (actorUid === passengerId) {
    return {role: "passenger"};
  }

  if (currentDriverId === null) {
    throw failure(
      "permission-denied",
      "ride_chat_participant_required",
    );
  }

  let approvedDriverId: string;

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
        "ride_chat_participant_required",
      );
    }

    throw error;
  }

  return deriveRideChatParticipant(
    actorUid,
    passengerId,
    currentDriverId,
    approvedDriverId,
  );
};

const serializeMessage = (
  messageId: string,
  data: Record<string, unknown>,
): RideChatMessageResult => {
  const kind = data.kind;
  const senderRole = data.senderRole;
  const assignmentRound =
    data.assignmentRound;
  const text = data.text;
  const createdAt = data.createdAt;
  const expiresAt = data.expiresAt;

  if (
    kind !== "text" ||
    (
      senderRole !== "passenger" &&
      senderRole !== "driver"
    ) ||
    typeof assignmentRound !== "number" ||
    !Number.isInteger(assignmentRound) ||
    assignmentRound < 1 ||
    typeof text !== "string" ||
    !(createdAt instanceof Timestamp) ||
    !(expiresAt instanceof Timestamp)
  ) {
    throw failure(
      "internal",
      "ride_chat_message_data_invalid",
    );
  }

  return {
    messageId,
    kind,
    senderRole,
    assignmentRound,
    text,
    createdAtMillis: createdAt.toMillis(),
    expiresAtMillis: expiresAt.toMillis(),
  };
};

export const sendRideChatMessageForActor =
async (
  dependencies: RideChatDependencies,
  actorUid: string,
  rawInput: unknown,
): Promise<Record<string, unknown>> => {
  const input =
    validateRideChatSendPayload(rawInput);

  const {firestore} = dependencies;

  const operationId =
    rideOperationId(
      actorUid,
      SEND_RIDE_CHAT_MESSAGE_CALLABLE,
      input.requestId,
    );

  const operationRef =
    firestore
      .collection("rideOperations")
      .doc(operationId);

  const digest =
    rideRequestDigest(
      SEND_RIDE_CHAT_MESSAGE_CALLABLE,
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

  const messageRef =
    rideRef
      .collection("messages")
      .doc(operationId);

  const rateRef =
    firestore
      .collection("rideChatRateLimits")
      .doc(
        rideChatRateLimitId(
          input.rideId,
          actorUid,
        ),
      );

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

        requireRideChatSendStatus(
          data.status,
        );

        const passengerId =
          requireNonEmptyString(
            data.passengerId,
            "ride_data_invalid",
          );

        const currentDriverId =
          requireNonEmptyString(
            data.driverId,
            "ride_data_invalid",
          );

        const assignmentRound =
          requirePositiveInteger(
            data.matchRound,
            "ride_data_invalid",
          );

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
              error.code ===
                "permission-denied"
            ) {
              throw failure(
                "permission-denied",
                "ride_chat_participant_required",
              );
            }

            throw error;
          }
        }

        const participant =
          deriveRideChatParticipant(
            actorUid,
            passengerId,
            currentDriverId,
            approvedDriverId,
          );

        const rateSnapshot =
          await transaction.get(rateRef);

        const nextRateState =
          consumeRideChatRateLimit(
            rateSnapshot.exists ?
              (rateSnapshot.data() ?? {}) :
              null,
            now,
          );

        const expiresAt =
          Timestamp.fromMillis(
            now.toMillis() +
              RIDE_CHAT_RETENTION_MILLIS,
          );

        const result = {
          rideId: input.rideId,
          messageId: messageRef.id,
          kind: "text" as const,
          senderRole: participant.role,
          assignmentRound,
          text: input.text,
          createdAtMillis: now.toMillis(),
          expiresAtMillis:
            expiresAt.toMillis(),
        };

        transaction.create(
          messageRef,
          {
            kind: "text",
            senderRole: participant.role,
            assignmentRound,
            text: input.text,
            createdAt: now,
            expiresAt,
          },
        );

        transaction.set(
          rateRef,
          nextRateState,
        );

        transaction.create(
          operationRef,
          {
            actorUid,
            callableName:
              SEND_RIDE_CHAT_MESSAGE_CALLABLE,
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
      "ride_chat_send_persistence_failed",
    );
  }
};

export const listRideChatMessagesForActor =
async (
  dependencies: RideChatDependencies,
  actorUid: string,
  rawInput: unknown,
): Promise<Record<string, unknown>> => {
  const input =
    validateRideChatListPayload(rawInput);

  const {firestore} = dependencies;

  const rideRef =
    firestore
      .collection("rides")
      .doc(input.rideId);

  const ride = await rideRef.get();

  if (!ride.exists) {
    throw new HttpsError(
      "not-found",
      "Ride was not found.",
      {reason: "ride_not_found"},
    );
  }

  const data = ride.data() ?? {};

  const passengerId =
    requireNonEmptyString(
      data.passengerId,
      "ride_data_invalid",
    );

  const currentDriverId =
    typeof data.driverId === "string" &&
    data.driverId.length > 0 ?
      data.driverId :
      null;

  const matchRound =
    requirePositiveInteger(
      data.matchRound,
      "ride_data_invalid",
    );

  const participant =
    await loadReadParticipant(
      firestore,
      actorUid,
      passengerId,
      currentDriverId,
    );

  const now =
    dependencies.now?.() ?? Timestamp.now();

  requireRideChatReadWindow(
    data,
    now,
  );

  const messagesRef =
    rideRef.collection("messages");

  let messagesQuery =
    messagesRef
      .where("expiresAt", ">", now)
      .orderBy("expiresAt", "asc")
      .orderBy("createdAt", "asc")
      .orderBy(
        FieldPath.documentId(),
        "asc",
      );

  if (participant.role === "driver") {
    messagesQuery =
      messagesRef
        .where(
          "assignmentRound",
          "==",
          matchRound,
        )
        .where("expiresAt", ">", now)
        .orderBy("expiresAt", "asc")
        .orderBy("createdAt", "asc")
        .orderBy(
          FieldPath.documentId(),
          "asc",
        );
  }

  if (input.cursor !== null) {
    messagesQuery =
      messagesQuery.startAfter(
        Timestamp.fromMillis(
          input.cursor.expiresAtMillis,
        ),
        Timestamp.fromMillis(
          input.cursor.createdAtMillis,
        ),
        input.cursor.messageId,
      );
  }

  const snapshot =
    await messagesQuery
      .limit(input.pageSize + 1)
      .get();

  const hasMore =
    snapshot.docs.length >
      input.pageSize;

  const pageDocs =
    snapshot.docs.slice(
      0,
      input.pageSize,
    );

  const messages =
    pageDocs.map(
      (document) =>
        serializeMessage(
          document.id,
          document.data(),
        ),
    );

  let nextCursor:
    RideChatCursor | null = null;

  if (
    hasMore &&
    messages.length > 0
  ) {
    const last =
      messages[messages.length - 1];

    nextCursor = {
      expiresAtMillis:
        last.expiresAtMillis,
      createdAtMillis:
        last.createdAtMillis,
      messageId:
        last.messageId,
    };
  }

  return {
    rideId: input.rideId,
    messages,
    nextCursor,
  };
};
/* eslint-enable max-len */
