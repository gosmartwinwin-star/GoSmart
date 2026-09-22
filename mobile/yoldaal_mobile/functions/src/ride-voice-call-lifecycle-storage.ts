import {
  Timestamp,
  type Firestore,
  type Transaction,
} from "firebase-admin/firestore";

import {
  RideVoiceCallAuthorityError,
  isRideVoiceAuthorityTransitionAllowed,
  isRideVoiceOpaqueCallId,
  type RideVoiceCallActorSide,
} from "./ride-voice-call-authority.js";

import {
  isRideVoiceCallState,
  isRideVoiceParticipantRole,
  type RideVoiceCallState,
  type RideVoiceParticipantRole,
} from "./ride-voice-call-policy.js";

const MAX_RIDE_ID_LENGTH = 256;
const MAX_UID_LENGTH = 128;

export type RideVoiceCallLifecycleDependencies = Readonly<{
  firestore: Firestore;
  nowMillis?: () => number;
}>;

export type RideVoiceCallTransitionResult = Readonly<{
  rideId: string;
  callId: string;
  state: RideVoiceCallState;
  updatedAtMillis: number;
}>;

type TransitionInput = Readonly<{
  rideId: string;
  callId: string;
  toState: RideVoiceCallState;
}>;

type RideParticipants = Readonly<{
  passengerUid: string;
  driverUid: string;
}>;

type StoredParticipant = Readonly<{
  uid: string;
  role: RideVoiceParticipantRole;
}>;

type StoredCall = Readonly<{
  state: RideVoiceCallState;
  caller: StoredParticipant;
  callee: StoredParticipant;
  updatedAtMillis: number;
}>;

const isRecord = (
  value: unknown,
): value is Record<string, unknown> =>
  typeof value === "object" &&
  value !== null &&
  !Array.isArray(value);

const hasExactKeys = (
  value: Record<string, unknown>,
  expected: readonly string[],
): boolean => {
  const keys = Object.keys(value).sort();
  const target = [...expected].sort();

  return (
    keys.length === target.length &&
    keys.every(
      (key, index) =>
        key === target[index],
    )
  );
};

const requireBoundedText = (
  value: unknown,
  maxLength: number,
  message: string,
): string => {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > maxLength
  ) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      message,
    );
  }

  return value;
};

const requireActorUid = (
  value: unknown,
): string => {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > MAX_UID_LENGTH
  ) {
    throw new RideVoiceCallAuthorityError(
      "invalid-argument",
      "Voice actor identity is invalid.",
    );
  }

  return value;
};

const parseInput = (
  input: unknown,
): TransitionInput => {
  if (
    !isRecord(input) ||
    !hasExactKeys(
      input,
      [
        "rideId",
        "callId",
        "toState",
      ],
    )
  ) {
    throw new RideVoiceCallAuthorityError(
      "invalid-argument",
      "Voice transition payload is invalid.",
    );
  }

  if (
    typeof input.rideId !== "string" ||
    input.rideId.length === 0 ||
    input.rideId.length > MAX_RIDE_ID_LENGTH ||
    !isRideVoiceOpaqueCallId(input.callId) ||
    !isRideVoiceCallState(input.toState)
  ) {
    throw new RideVoiceCallAuthorityError(
      "invalid-argument",
      "Voice transition payload is invalid.",
    );
  }

  return {
    rideId: input.rideId,
    callId: input.callId,
    toState: input.toState,
  };
};

const timestampMillis = (
  value: unknown,
  message: string,
): number => {
  if (!(value instanceof Timestamp)) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      message,
    );
  }

  const millis = value.toMillis();

  if (
    !Number.isSafeInteger(millis) ||
    millis < 0
  ) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      message,
    );
  }

  return millis;
};

const loadRideParticipants = async (
  dependencies: RideVoiceCallLifecycleDependencies,
  transaction: Transaction,
  rideId: string,
): Promise<RideParticipants> => {
  const rideRef =
    dependencies.firestore
      .collection("rides")
      .doc(rideId);

  const rideSnapshot =
    await transaction.get(rideRef);

  if (!rideSnapshot.exists) {
    throw new RideVoiceCallAuthorityError(
      "not-found",
      "Active ride is unavailable.",
    );
  }

  const rideData =
    rideSnapshot.data() ?? {};

  if (
    !Number.isSafeInteger(rideData.version) ||
    rideData.version < 1
  ) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      "Ride voice authority data is invalid.",
    );
  }

  const driverId =
    requireBoundedText(
      rideData.driverId,
      MAX_RIDE_ID_LENGTH,
      "Ride driver identity is invalid.",
    );

  const driverRef =
    dependencies.firestore
      .collection("driverProfiles")
      .doc(driverId);

  const driverSnapshot =
    await transaction.get(driverRef);

  if (!driverSnapshot.exists) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      "Ride driver identity is invalid.",
    );
  }

  const driverData =
    driverSnapshot.data() ?? {};

  const passengerUid =
    requireBoundedText(
      rideData.passengerId,
      MAX_UID_LENGTH,
      "Ride participant identity is invalid.",
    );

  const driverUid =
    requireBoundedText(
      driverData.authUserId,
      MAX_UID_LENGTH,
      "Ride participant identity is invalid.",
    );

  if (passengerUid === driverUid) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      "Ride participant identity is invalid.",
    );
  }

  return {
    passengerUid,
    driverUid,
  };
};

const requireActorParticipant = (
  actorUid: string,
  participants: RideParticipants,
): void => {
  if (
    actorUid !== participants.passengerUid &&
    actorUid !== participants.driverUid
  ) {
    throw new RideVoiceCallAuthorityError(
      "permission-denied",
      "Voice participant is unavailable.",
    );
  }
};

const readActivePointer = async (
  dependencies: RideVoiceCallLifecycleDependencies,
  transaction: Transaction,
  input: TransitionInput,
): Promise<Readonly<{
  state: RideVoiceCallState;
  updatedAtMillis: number;
}>> => {
  const activeRef =
    dependencies.firestore
      .collection("rideVoiceActiveCalls")
      .doc(input.rideId);

  const snapshot =
    await transaction.get(activeRef);

  if (!snapshot.exists) {
    throw new RideVoiceCallAuthorityError(
      "not-found",
      "Active voice call is unavailable.",
    );
  }

  const data =
    snapshot.data() ?? {};

  if (
    !hasExactKeys(
      data,
      [
        "callId",
        "rideId",
        "state",
        "updatedAt",
      ],
    ) ||
    data.callId !== input.callId ||
    data.rideId !== input.rideId ||
    !isRideVoiceCallState(data.state)
  ) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      "Active voice call pointer is invalid.",
    );
  }

  return {
    state: data.state,
    updatedAtMillis:
      timestampMillis(
        data.updatedAt,
        "Active voice call pointer is invalid.",
      ),
  };
};

const parseStoredParticipant = (
  value: unknown,
): StoredParticipant => {
  if (
    !isRecord(value) ||
    !hasExactKeys(
      value,
      [
        "uid",
        "role",
      ],
    ) ||
    typeof value.uid !== "string" ||
    value.uid.length === 0 ||
    value.uid.length > MAX_UID_LENGTH ||
    !isRideVoiceParticipantRole(value.role)
  ) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      "Stored voice participant is invalid.",
    );
  }

  return {
    uid: value.uid,
    role: value.role,
  };
};

const readStoredCall = async (
  dependencies: RideVoiceCallLifecycleDependencies,
  transaction: Transaction,
  input: TransitionInput,
): Promise<StoredCall> => {
  const callRef =
    dependencies.firestore
      .collection("rides")
      .doc(input.rideId)
      .collection("voiceCalls")
      .doc(input.callId);

  const snapshot =
    await transaction.get(callRef);

  if (!snapshot.exists) {
    throw new RideVoiceCallAuthorityError(
      "not-found",
      "Voice call is unavailable.",
    );
  }

  const data =
    snapshot.data() ?? {};

  if (
    !hasExactKeys(
      data,
      [
        "callId",
        "rideId",
        "rideVersion",
        "state",
        "caller",
        "callee",
        "createdAt",
        "updatedAt",
      ],
    ) ||
    data.callId !== input.callId ||
    data.rideId !== input.rideId ||
    !Number.isSafeInteger(data.rideVersion) ||
    data.rideVersion < 1 ||
    !isRideVoiceCallState(data.state)
  ) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      "Stored voice call is invalid.",
    );
  }

  const createdAtMillis =
    timestampMillis(
      data.createdAt,
      "Stored voice call is invalid.",
    );

  const updatedAtMillis =
    timestampMillis(
      data.updatedAt,
      "Stored voice call is invalid.",
    );

  if (updatedAtMillis < createdAtMillis) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      "Stored voice call is invalid.",
    );
  }

  return {
    state: data.state,
    caller:
      parseStoredParticipant(
        data.caller,
      ),
    callee:
      parseStoredParticipant(
        data.callee,
      ),
    updatedAtMillis,
  };
};

const requireParticipantPair = (
  call: StoredCall,
  participants: RideParticipants,
): void => {
  const passengerFirst =
    call.caller.uid === participants.passengerUid &&
    call.caller.role === "passenger" &&
    call.callee.uid === participants.driverUid &&
    call.callee.role === "driver";

  const driverFirst =
    call.caller.uid === participants.driverUid &&
    call.caller.role === "driver" &&
    call.callee.uid === participants.passengerUid &&
    call.callee.role === "passenger";

  if (!passengerFirst && !driverFirst) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      "Stored voice participant authority is invalid.",
    );
  }
};

const resolveActorSide = (
  actorUid: string,
  call: StoredCall,
): RideVoiceCallActorSide => {
  if (actorUid === call.caller.uid) {
    return "caller";
  }

  if (actorUid === call.callee.uid) {
    return "callee";
  }

  throw new RideVoiceCallAuthorityError(
    "data-invalid",
    "Stored voice participant authority is invalid.",
  );
};

const requireNowMillis = (
  dependencies: RideVoiceCallLifecycleDependencies,
): number => {
  const millis =
    (
      dependencies.nowMillis ??
      Date.now
    )();

  if (
    !Number.isSafeInteger(millis) ||
    millis < 0
  ) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      "Voice transition timestamp is invalid.",
    );
  }

  return millis;
};

const persistTransition = async (
  dependencies: RideVoiceCallLifecycleDependencies,
  input: TransitionInput,
  actorUid: string | null,
  system: boolean,
): Promise<RideVoiceCallTransitionResult> =>
  dependencies.firestore.runTransaction(
    async (transaction) => {
      const participants =
        await loadRideParticipants(
          dependencies,
          transaction,
          input.rideId,
        );

      if (actorUid !== null) {
        requireActorParticipant(
          actorUid,
          participants,
        );
      }

      const pointer =
        await readActivePointer(
          dependencies,
          transaction,
          input,
        );

      const call =
        await readStoredCall(
          dependencies,
          transaction,
          input,
        );

      if (
        pointer.state !== call.state ||
        pointer.updatedAtMillis !==
          call.updatedAtMillis
      ) {
        throw new RideVoiceCallAuthorityError(
          "data-invalid",
          "Voice call state authority is invalid.",
        );
      }

      requireParticipantPair(
        call,
        participants,
      );

      const actorSide:
        RideVoiceCallActorSide =
        system ?
          "system" :
          resolveActorSide(
            actorUid as string,
            call,
          );

      if (
        !isRideVoiceAuthorityTransitionAllowed(
          actorSide,
          call.state,
          input.toState,
        )
      ) {
        throw new RideVoiceCallAuthorityError(
          "failed-precondition",
          "Voice call transition is not allowed.",
        );
      }

      const updatedAtMillis =
        requireNowMillis(
          dependencies,
        );

      const updatedAt =
        Timestamp.fromMillis(
          updatedAtMillis,
        );

      const callRef =
        dependencies.firestore
          .collection("rides")
          .doc(input.rideId)
          .collection("voiceCalls")
          .doc(input.callId);

      const activeRef =
        dependencies.firestore
          .collection("rideVoiceActiveCalls")
          .doc(input.rideId);

      transaction.update(
        callRef,
        {
          state: input.toState,
          updatedAt,
        },
      );

      transaction.update(
        activeRef,
        {
          state: input.toState,
          updatedAt,
        },
      );

      return {
        rideId: input.rideId,
        callId: input.callId,
        state: input.toState,
        updatedAtMillis,
      };
    },
  );

/**
 * Persists one participant-authorized voice-call transition.
 * @param {RideVoiceCallLifecycleDependencies} dependencies Dependencies.
 * @param {unknown} actorUid Authenticated Firebase actor UID.
 * @param {unknown} input Exact client transition payload.
 * @return {Promise} Authoritative transition result.
 */
export const transitionStoredRideVoiceCallForActor = async (
  dependencies: RideVoiceCallLifecycleDependencies,
  actorUid: unknown,
  input: unknown,
): Promise<RideVoiceCallTransitionResult> => {
  const parsedInput =
    parseInput(input);

  const parsedActorUid =
    requireActorUid(actorUid);

  return persistTransition(
    dependencies,
    parsedInput,
    parsedActorUid,
    false,
  );
};

/**
 * Persists one server-only system voice-call transition.
 * @param {RideVoiceCallLifecycleDependencies} dependencies Dependencies.
 * @param {unknown} input Exact internal transition payload.
 * @return {Promise} Authoritative transition result.
 */
export const transitionStoredRideVoiceCallForSystem = async (
  dependencies: RideVoiceCallLifecycleDependencies,
  input: unknown,
): Promise<RideVoiceCallTransitionResult> =>
  persistTransition(
    dependencies,
    parseInput(input),
    null,
    true,
  );
