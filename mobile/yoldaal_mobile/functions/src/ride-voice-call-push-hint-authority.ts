import type {
  DocumentReference,
  Firestore,
} from "firebase-admin/firestore";
import {Timestamp} from "firebase-admin/firestore";
import {
  isRideVoiceOpaqueCallId,
} from "./ride-voice-call-authority.js";
import {
  parsePersistedDriverPushTarget,
} from "./driver-push-target-authority.js";
import {
  parsePersistedPassengerPushTarget,
} from "./passenger-push-target-authority.js";

export const RIDE_VOICE_CALL_AVAILABLE_PUSH_HINT_TYPE =
  "ride_voice_call_available";

const ELIGIBLE_RIDE_STATUSES =
  new Set<string>([
    "driverEnRoute",
    "driverArrived",
    "inProgress",
  ]);

const UNREGISTERED_FID_CODES =
  new Set<string>([
    "messaging/installation-id-not-registered",
    "messaging/registration-token-not-registered",
  ]);

type PlainRecord =
  Record<string, unknown>;

type VoiceRole =
  "driver" |
  "passenger";

type StoredParticipant = Readonly<{
  uid: string;
  role: VoiceRole;
}>;

type WakeInput = Readonly<{
  rideId: string;
  callId: string;
}>;

type Recipient = Readonly<{
  reference: DocumentReference;
  identity: string;
  fid: string;
  role: VoiceRole;
}>;

export type RideVoiceCallPushHintMessage = Readonly<{
  fids: string[];
  data: Readonly<{
    type:
      typeof RIDE_VOICE_CALL_AVAILABLE_PUSH_HINT_TYPE;
  }>;
}>;

export type RideVoiceCallPushHintBatchResponse =
  Readonly<{
    successCount: number;
    failureCount: number;
    responses: ReadonlyArray<
      Readonly<{
        success?: boolean;
        error?: Readonly<{
          code?: unknown;
        }>;
      }>
    >;
  }>;

export type RideVoiceCallPushHintMessaging =
  Readonly<{
    sendEachForMulticast: (
      message: RideVoiceCallPushHintMessage,
    ) => Promise<RideVoiceCallPushHintBatchResponse>;
  }>;

export type RideVoiceCallPushHintDependencies =
  Readonly<{
    firestore: Firestore;
    getMessaging: () =>
      RideVoiceCallPushHintMessaging;
    warn?: (message: string) => void;
  }>;

export type RideVoiceCallPushHintDispatchResult =
  "sent" |
  "skipped" |
  "failed";

const plainRecord = (
  value: unknown,
): PlainRecord | null =>
  typeof value === "object" &&
  value !== null &&
  !Array.isArray(value) ?
    value as PlainRecord :
    null;

const validId = (
  value: unknown,
): value is string =>
  typeof value === "string" &&
  value.length > 0 &&
  value.length <= 512 &&
  value.trim() === value &&
  !/\s/u.test(value);

const exactKeys = (
  value: PlainRecord,
  expected: readonly string[],
): boolean => {
  const actual =
    Object.keys(value).sort();
  const wanted =
    [...expected].sort();

  if (actual.length !== wanted.length) {
    return false;
  }

  return actual.every(
    (key, index) =>
      key === wanted[index],
  );
};

const parseInput = (
  value: unknown,
): WakeInput | null => {
  const data =
    plainRecord(value);

  if (
    data === null ||
    !exactKeys(
      data,
      ["callId", "rideId"],
    ) ||
    !validId(data.rideId) ||
    !isRideVoiceOpaqueCallId(
      data.callId,
    )
  ) {
    return null;
  }

  return {
    rideId: data.rideId,
    callId: data.callId,
  };
};

const parseParticipant = (
  value: unknown,
): StoredParticipant | null => {
  const data =
    plainRecord(value);

  if (
    data === null ||
    !exactKeys(
      data,
      ["role", "uid"],
    ) ||
    !validId(data.uid) ||
    (
      data.role !== "driver" &&
      data.role !== "passenger"
    )
  ) {
    return null;
  }

  return {
    uid: data.uid,
    role: data.role,
  };
};

const safeWarn = (
  dependencies:
    RideVoiceCallPushHintDependencies,
  message: string,
): void => {
  try {
    dependencies.warn?.(message);
  } catch {
    // Logging must never change delivery authority.
  }
};

const isUnregisteredFidCode = (
  value: unknown,
): boolean =>
  typeof value === "string" &&
  UNREGISTERED_FID_CODES.has(value);

const loadRecipient = async (
  dependencies:
    RideVoiceCallPushHintDependencies,
  role: VoiceRole,
  identity: string,
): Promise<Recipient | null> => {
  const reference =
    dependencies.firestore
      .collection(
        role === "driver" ?
          "driverPushTargets" :
          "passengerPushTargets",
      )
      .doc(identity);

  const snapshot =
    await reference.get();

  if (!snapshot.exists) {
    return null;
  }

  const target =
    role === "driver" ?
      parsePersistedDriverPushTarget(
        identity,
        snapshot.data(),
      ) :
      parsePersistedPassengerPushTarget(
        identity,
        snapshot.data(),
      );

  if (target === null) {
    return null;
  }

  return {
    reference,
    identity,
    fid: target.fid,
    role,
  };
};

const deleteOnlyStillCurrentFailedFid =
  async (
    dependencies:
      RideVoiceCallPushHintDependencies,
    recipient: Recipient,
  ): Promise<void> => {
    try {
      await dependencies.firestore
        .runTransaction(
          async (transaction) => {
            const snapshot =
              await transaction.get(
                recipient.reference,
              );

            if (!snapshot.exists) {
              return;
            }

            const current =
              recipient.role === "driver" ?
                parsePersistedDriverPushTarget(
                  recipient.identity,
                  snapshot.data(),
                ) :
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

            transaction.delete(
              recipient.reference,
            );
          },
        );
    } catch {
      safeWarn(
        dependencies,
        "ride_voice_call_push_hint_target_cleanup_failed",
      );
    }
  };

const resolveRecipient = async (
  dependencies:
    RideVoiceCallPushHintDependencies,
  input: WakeInput,
): Promise<Recipient | null> => {
  const rideReference =
    dependencies.firestore
      .collection("rides")
      .doc(input.rideId);

  const rideSnapshot =
    await rideReference.get();

  if (!rideSnapshot.exists) {
    return null;
  }

  const ride =
    plainRecord(
      rideSnapshot.data(),
    );

  if (
    ride === null ||
    !validId(ride.passengerId) ||
    !validId(ride.driverId) ||
    typeof ride.status !== "string" ||
    !ELIGIBLE_RIDE_STATUSES.has(
      ride.status,
    )
  ) {
    return null;
  }

  const profileReference =
    dependencies.firestore
      .collection("driverProfiles")
      .doc(ride.driverId);

  const profileSnapshot =
    await profileReference.get();

  if (!profileSnapshot.exists) {
    return null;
  }

  const profile =
    plainRecord(
      profileSnapshot.data(),
    );

  if (
    profile === null ||
    !validId(profile.authUserId)
  ) {
    return null;
  }

  const activeReference =
    dependencies.firestore
      .collection(
        "rideVoiceActiveCalls",
      )
      .doc(input.rideId);

  const activeSnapshot =
    await activeReference.get();

  if (!activeSnapshot.exists) {
    return null;
  }

  const active =
    plainRecord(
      activeSnapshot.data(),
    );

  if (
    active === null ||
    !exactKeys(
      active,
      [
        "callId",
        "rideId",
        "state",
        "updatedAt",
      ],
    ) ||
    active.callId !== input.callId ||
    active.rideId !== input.rideId ||
    active.state !== "ringing" ||
    !(
      active.updatedAt instanceof
      Timestamp
    )
  ) {
    return null;
  }

  const callReference =
    rideReference
      .collection("voiceCalls")
      .doc(input.callId);

  const callSnapshot =
    await callReference.get();

  if (!callSnapshot.exists) {
    return null;
  }

  const call =
    plainRecord(
      callSnapshot.data(),
    );

  if (
    call === null ||
    !exactKeys(
      call,
      [
        "callId",
        "callee",
        "caller",
        "createdAt",
        "rideId",
        "rideVersion",
        "state",
        "updatedAt",
      ],
    ) ||
    call.callId !== input.callId ||
    call.rideId !== input.rideId ||
    call.state !== "ringing" ||
    !Number.isInteger(
      call.rideVersion,
    ) ||
    !(
      call.createdAt instanceof
      Timestamp
    ) ||
    !(
      call.updatedAt instanceof
      Timestamp
    )
  ) {
    return null;
  }

  const caller =
    parseParticipant(
      call.caller,
    );
  const callee =
    parseParticipant(
      call.callee,
    );

  if (
    caller === null ||
    callee === null
  ) {
    return null;
  }

  const passengerUid =
    ride.passengerId;
  const driverUid =
    profile.authUserId;

  if (
    callee.role === "driver" &&
    callee.uid === driverUid &&
    caller.role === "passenger" &&
    caller.uid === passengerUid
  ) {
    return loadRecipient(
      dependencies,
      "driver",
      ride.driverId,
    );
  }

  if (
    callee.role === "passenger" &&
    callee.uid === passengerUid &&
    caller.role === "driver" &&
    caller.uid === driverUid
  ) {
    return loadRecipient(
      dependencies,
      "passenger",
      ride.passengerId,
    );
  }

  return null;
};

/**
 * Revalidates a ringing Voice call and sends a data-only FCM wake hint.
 *
 * The hint contains no ride, call, user, phone, or profile identity.
 *
 * @param {RideVoiceCallPushHintDependencies} dependencies Server dependencies.
 * @param {unknown} input Server-derived ride and opaque call identifiers.
 * @return {Promise<RideVoiceCallPushHintDispatchResult>} Delivery result.
 */
export const dispatchRideVoiceCallPushHint =
  async (
    dependencies:
      RideVoiceCallPushHintDependencies,
    input: unknown,
  ): Promise<
    RideVoiceCallPushHintDispatchResult
  > => {
    const parsed =
      parseInput(input);

    if (parsed === null) {
      safeWarn(
        dependencies,
        "ride_voice_call_push_hint_input_invalid",
      );
      return "skipped";
    }

    let recipient:
      Recipient | null;

    try {
      recipient =
        await resolveRecipient(
          dependencies,
          parsed,
        );
    } catch {
      safeWarn(
        dependencies,
        "ride_voice_call_push_hint_authority_read_failed",
      );
      return "failed";
    }

    if (recipient === null) {
      return "skipped";
    }

    let response:
      RideVoiceCallPushHintBatchResponse;

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
                RIDE_VOICE_CALL_AVAILABLE_PUSH_HINT_TYPE,
            },
          });
    } catch {
      safeWarn(
        dependencies,
        "ride_voice_call_push_hint_send_failed",
      );
      return "failed";
    }

    const item =
      response.responses[0];

    if (
      response.successCount === 1 &&
      response.failureCount === 0 &&
      item?.success !== false
    ) {
      return "sent";
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
      "ride_voice_call_push_hint_delivery_failed",
    );

    return "failed";
  };
