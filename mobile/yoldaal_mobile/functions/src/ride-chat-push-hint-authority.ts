/* eslint-disable max-len */
import {
  DocumentReference,
  Firestore,
} from "firebase-admin/firestore";

import {
  parsePersistedDriverPushTarget,
} from "./driver-push-target-authority.js";
import {
  parsePersistedPassengerPushTarget,
} from "./passenger-push-target-authority.js";

export const RIDE_CHAT_MESSAGE_AVAILABLE_PUSH_HINT_TYPE =
  "ride_chat_message_available";

const UNREGISTERED_FID_CODES =
  new Set<string>([
    "messaging/installation-id-not-registered",
    "messaging/registration-token-not-registered",
  ]);

type SenderRole =
  "passenger" |
  "driver";

export type RideChatPushHintMessage = Readonly<{
  fids: string[];
  data: Readonly<{
    type:
      typeof RIDE_CHAT_MESSAGE_AVAILABLE_PUSH_HINT_TYPE;
  }>;
}>;

export type RideChatPushHintBatchResponse = Readonly<{
  successCount: number;
  failureCount: number;
  responses: ReadonlyArray<
    Readonly<{
      success: boolean;
      error?: Readonly<{
        code?: unknown;
      }>;
    }>
  >;
}>;

export type RideChatPushHintMessaging = Readonly<{
  sendEachForMulticast: (
    message: RideChatPushHintMessage,
  ) => Promise<RideChatPushHintBatchResponse>;
}>;

export type RideChatPushHintDependencies = Readonly<{
  firestore: Firestore;
  getMessaging: () => RideChatPushHintMessaging;
  warn?: (message: string) => void;
}>;

export type RideChatPushHintInput = Readonly<{
  rideId: string;
  messageId: string;
  messageData: unknown;
}>;

export type RideChatPushHintResult = Readonly<{
  outcome:
    "sent" |
    "ignored" |
    "failed";
}>;

type Recipient = Readonly<{
  reference: DocumentReference;
  identity: string;
  fid: string;
  role:
    "passenger" |
    "driver";
}>;

const plainRecord = (
  value: unknown,
): Record<string, unknown> | null => {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value)
  ) {
    return null;
  }

  return value as Record<string, unknown>;
};

const validId = (
  value: unknown,
): value is string =>
  typeof value === "string" &&
  value.length > 0 &&
  value.length <= 256 &&
  value.trim() === value &&
  !value.includes("/");

const positiveRound = (
  value: unknown,
): value is number =>
  typeof value === "number" &&
  Number.isSafeInteger(value) &&
  value > 0;

const activeChatStatus = (
  value: unknown,
): boolean =>
  value === "driverEnRoute" ||
  value === "driverArrived" ||
  value === "inProgress";

const parseSenderRole = (
  value: unknown,
): SenderRole | null => {
  if (
    value === "passenger" ||
    value === "driver"
  ) {
    return value;
  }

  return null;
};

const isUnregisteredFidCode = (
  value: unknown,
): boolean =>
  typeof value === "string" &&
  UNREGISTERED_FID_CODES.has(value);

const safeWarn = (
  dependencies: RideChatPushHintDependencies,
  message: string,
): void => {
  try {
    dependencies.warn?.(message);
  } catch {
    // Logging must never become ride/chat authority.
  }
};

const loadRecipient = async (
  dependencies: RideChatPushHintDependencies,
  senderRole: SenderRole,
  ride: Record<string, unknown>,
): Promise<Recipient | null> => {
  if (senderRole === "passenger") {
    const driverId =
      ride.driverId;

    if (!validId(driverId)) {
      return null;
    }

    const reference =
      dependencies.firestore
        .collection("driverPushTargets")
        .doc(driverId);

    const snapshot =
      await reference.get();

    if (!snapshot.exists) {
      return null;
    }

    const target =
      parsePersistedDriverPushTarget(
        driverId,
        snapshot.data(),
      );

    if (
      target === null ||
      target.platform !== "android"
    ) {
      return null;
    }

    return {
      reference,
      identity: driverId,
      fid: target.fid,
      role: "driver",
    };
  }

  const passengerId =
    ride.passengerId;

  if (!validId(passengerId)) {
    return null;
  }

  const reference =
    dependencies.firestore
      .collection("passengerPushTargets")
      .doc(passengerId);

  const snapshot =
    await reference.get();

  if (!snapshot.exists) {
    return null;
  }

  const target =
    parsePersistedPassengerPushTarget(
      passengerId,
      snapshot.data(),
    );

  if (
    target === null ||
    target.platform !== "android"
  ) {
    return null;
  }

  return {
    reference,
    identity: passengerId,
    fid: target.fid,
    role: "passenger",
  };
};

const deleteOnlyStillCurrentFailedFid = async (
  dependencies: RideChatPushHintDependencies,
  recipient: Recipient,
): Promise<void> => {
  try {
    await dependencies.firestore.runTransaction(
      async (transaction) => {
        const snapshot =
          await transaction.get(
            recipient.reference,
          );

        if (!snapshot.exists) {
          return;
        }

        if (recipient.role === "driver") {
          const current =
            parsePersistedDriverPushTarget(
              recipient.identity,
              snapshot.data(),
            );

          if (
            current === null ||
            current.fid !== recipient.fid
          ) {
            return;
          }
        } else {
          const current =
            parsePersistedPassengerPushTarget(
              recipient.identity,
              snapshot.data(),
            );

          if (
            current === null ||
            current.fid !== recipient.fid
          ) {
            return;
          }
        }

        transaction.delete(
          recipient.reference,
        );
      },
    );
  } catch {
    safeWarn(
      dependencies,
      "ride_chat_push_hint_target_cleanup_failed",
    );
  }
};

const dispatchInternal = async (
  dependencies: RideChatPushHintDependencies,
  input: RideChatPushHintInput,
): Promise<RideChatPushHintResult> => {
  if (
    !validId(input.rideId) ||
    !validId(input.messageId)
  ) {
    return {outcome: "ignored"};
  }

  const message =
    plainRecord(input.messageData);

  if (
    message === null ||
    message.kind !== "text"
  ) {
    return {outcome: "ignored"};
  }

  const senderRole =
    parseSenderRole(
      message.senderRole,
    );

  if (
    senderRole === null ||
    !positiveRound(
      message.assignmentRound,
    )
  ) {
    return {outcome: "ignored"};
  }

  const rideSnapshot =
    await dependencies.firestore
      .collection("rides")
      .doc(input.rideId)
      .get();

  if (!rideSnapshot.exists) {
    return {outcome: "ignored"};
  }

  const ride =
    plainRecord(
      rideSnapshot.data(),
    );

  if (
    ride === null ||
    !activeChatStatus(ride.status) ||
    !positiveRound(ride.matchRound) ||
    ride.matchRound !==
      message.assignmentRound
  ) {
    return {outcome: "ignored"};
  }

  const recipient =
    await loadRecipient(
      dependencies,
      senderRole,
      ride,
    );

  if (recipient === null) {
    return {outcome: "ignored"};
  }

  let response:
    RideChatPushHintBatchResponse;

  try {
    response =
      await dependencies
        .getMessaging()
        .sendEachForMulticast({
          fids: [
            recipient.fid,
          ],
          data: {
            type:
              RIDE_CHAT_MESSAGE_AVAILABLE_PUSH_HINT_TYPE,
          },
        });
  } catch {
    safeWarn(
      dependencies,
      "ride_chat_push_hint_send_failed",
    );

    return {outcome: "failed"};
  }

  const item =
    response.responses[0];

  if (
    response.responses.length === 1 &&
    item !== undefined &&
    item.success === true
  ) {
    return {outcome: "sent"};
  }

  const errorCode =
    item?.error?.code;

  if (
    isUnregisteredFidCode(
      errorCode,
    )
  ) {
    await deleteOnlyStillCurrentFailedFid(
      dependencies,
      recipient,
    );
  }

  safeWarn(
    dependencies,
    "ride_chat_push_hint_delivery_failed",
  );

  return {outcome: "failed"};
};

export const dispatchRideChatPushHint = async (
  dependencies: RideChatPushHintDependencies,
  input: RideChatPushHintInput,
): Promise<RideChatPushHintResult> => {
  try {
    return await dispatchInternal(
      dependencies,
      input,
    );
  } catch {
    safeWarn(
      dependencies,
      "ride_chat_push_hint_processing_failed",
    );

    return {outcome: "failed"};
  }
};
