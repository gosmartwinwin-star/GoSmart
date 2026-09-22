import type {Firestore} from "firebase-admin/firestore";
import {Timestamp} from "firebase-admin/firestore";

import {
  isRideVoiceOpaqueCallId,
  RideVoiceCallAuthorityError,
} from "./ride-voice-call-authority.js";
import {
  isRideVoiceCallState,
  isRideVoiceEligibleRideStatus,
  isRideVoiceParticipantRole,
  type RideVoiceCallState,
  type RideVoiceParticipantRole,
} from "./ride-voice-call-policy.js";

const MAX_RIDE_ID_LENGTH = 256;
const MAX_UID_LENGTH = 128;
const MAX_DRIVER_ID_LENGTH = 256;

const TERMINAL_CALL_STATES =
  new Set<RideVoiceCallState>([
    "ended",
    "declined",
    "cancelled",
    "missed",
    "failed",
  ]);

type PlainRecord =
  Record<string, unknown>;

type ActiveRidePointer =
  Readonly<{
    rideId: string;
    status: unknown;
  }>;

type RideParticipants =
  Readonly<{
    rideId: string;
    rideStatus: unknown;
    passengerUid: string;
    driverId: string;
    driverUid: string;
  }>;

type StoredParticipant =
  Readonly<{
    uid: string;
    role: RideVoiceParticipantRole;
  }>;

type StoredCall =
  Readonly<{
    callId: string;
    rideId: string;
    rideVersion: number;
    state: RideVoiceCallState;
    caller: StoredParticipant;
    callee: StoredParticipant;
    createdAtMillis: number;
    updatedAtMillis: number;
  }>;

type ActiveCallPointer =
  Readonly<{
    callId: string;
    rideId: string;
    state: RideVoiceCallState;
    updatedAtMillis: number;
  }>;

export type RideVoiceCallRecoveryActorRole =
  "driver" |
  "passenger";

export type RideVoiceCallRecoveryActorSide =
  "caller" |
  "callee";

export type RideVoiceCallRecoveryProjection =
  Readonly<{
    rideId: string;
    callId: string;
    state: RideVoiceCallState;
    role: RideVoiceCallRecoveryActorRole;
    side: RideVoiceCallRecoveryActorSide;
  }>;

export type RideVoiceCallRecoveryResult =
  Readonly<{
    activeCall:
      RideVoiceCallRecoveryProjection | null;
  }>;

export type RideVoiceCallRecoveryDependencies =
  Readonly<{
    firestore: Firestore;
    resolveDriverIdForActor: (
      actorUid: string,
    ) => Promise<string | null>;
  }>;

const plainRecord = (
  value: unknown,
): PlainRecord | null =>
  typeof value === "object" &&
  value !== null &&
  !Array.isArray(value) ?
    value as PlainRecord :
    null;

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

const validBoundedId = (
  value: unknown,
  maxLength: number,
): value is string =>
  typeof value === "string" &&
  value.length > 0 &&
  value.length <= maxLength &&
  value.trim() === value &&
  !/\s/u.test(value);

const validRideId = (
  value: unknown,
): value is string =>
  validBoundedId(
    value,
    MAX_RIDE_ID_LENGTH,
  );

const validUid = (
  value: unknown,
): value is string =>
  validBoundedId(
    value,
    MAX_UID_LENGTH,
  );

const validDriverId = (
  value: unknown,
): value is string =>
  validBoundedId(
    value,
    MAX_DRIVER_ID_LENGTH,
  );

const timestampMillis = (
  value: unknown,
): number | null => {
  if (!(value instanceof Timestamp)) {
    return null;
  }

  const millis =
    value.toMillis();

  return Number.isSafeInteger(millis) ?
    millis :
    null;
};

const requireEmptyInput = (
  input: unknown,
): void => {
  const data =
    plainRecord(input);

  if (
    data === null ||
    Object.keys(data).length !== 0
  ) {
    throw new RideVoiceCallAuthorityError(
      "invalid-argument",
      "Voice recovery payload is invalid.",
    );
  }
};

const requireActorUid = (
  actorUid: unknown,
): string => {
  if (!validUid(actorUid)) {
    throw new RideVoiceCallAuthorityError(
      "permission-denied",
      "Voice recovery actor is invalid.",
    );
  }

  return actorUid;
};

const parseActiveRidePointer = (
  data: unknown,
): ActiveRidePointer => {
  const record =
    plainRecord(data);

  if (
    record === null ||
    !validRideId(record.rideId)
  ) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      "Active ride pointer is invalid.",
    );
  }

  return {
    rideId: record.rideId,
    status: record.status,
  };
};

const readOptionalActiveRidePointer =
  async (
    dependencies:
      RideVoiceCallRecoveryDependencies,
    collection: string,
    documentId: string,
  ): Promise<ActiveRidePointer | null> => {
    const snapshot =
      await dependencies.firestore
        .collection(collection)
        .doc(documentId)
        .get();

    if (!snapshot.exists) {
      return null;
    }

    return parseActiveRidePointer(
      snapshot.data(),
    );
  };

const loadRideParticipants =
  async (
    dependencies:
      RideVoiceCallRecoveryDependencies,
    rideId: string,
  ): Promise<RideParticipants> => {
    const rideReference =
      dependencies.firestore
        .collection("rides")
        .doc(rideId);

    const rideSnapshot =
      await rideReference.get();

    if (!rideSnapshot.exists) {
      throw new RideVoiceCallAuthorityError(
        "data-invalid",
        "Active ride is unavailable.",
      );
    }

    const ride =
      plainRecord(
        rideSnapshot.data(),
      );

    if (
      ride === null ||
      !validUid(ride.passengerId) ||
      !validDriverId(ride.driverId)
    ) {
      throw new RideVoiceCallAuthorityError(
        "data-invalid",
        "Active ride authority is invalid.",
      );
    }

    const profileSnapshot =
      await dependencies.firestore
        .collection("driverProfiles")
        .doc(ride.driverId)
        .get();

    if (!profileSnapshot.exists) {
      throw new RideVoiceCallAuthorityError(
        "data-invalid",
        "Driver profile authority is invalid.",
      );
    }

    const profile =
      plainRecord(
        profileSnapshot.data(),
      );

    if (
      profile === null ||
      !validUid(profile.authUserId) ||
      profile.authUserId ===
        ride.passengerId
    ) {
      throw new RideVoiceCallAuthorityError(
        "data-invalid",
        "Ride participant authority is invalid.",
      );
    }

    return {
      rideId,
      rideStatus: ride.status,
      passengerUid: ride.passengerId,
      driverId: ride.driverId,
      driverUid: profile.authUserId,
    };
  };

const requirePointerRideConsistency = (
  pointer: ActiveRidePointer | null,
  rideId: string,
  rideStatus: unknown,
): void => {
  if (pointer === null) {
    return;
  }

  if (
    pointer.rideId !== rideId ||
    pointer.status !== rideStatus
  ) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      "Active ride pointer is inconsistent.",
    );
  }
};

const resolveActorRole = (
  actorUid: string,
  driverIdForActor: string | null,
  passengerPointer: ActiveRidePointer | null,
  driverPointer: ActiveRidePointer | null,
  participants: RideParticipants,
): RideVoiceCallRecoveryActorRole => {
  const passengerMatch =
    passengerPointer !== null &&
    actorUid === participants.passengerUid;

  const driverMatch =
    driverPointer !== null &&
    driverIdForActor !== null &&
    driverIdForActor === participants.driverId &&
    actorUid === participants.driverUid;

  if (passengerMatch === driverMatch) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      "Active ride actor authority is ambiguous.",
    );
  }

  if (
    passengerPointer !== null &&
    !passengerMatch
  ) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      "Passenger active ride authority is invalid.",
    );
  }

  if (
    driverPointer !== null &&
    !driverMatch
  ) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      "Driver active ride authority is invalid.",
    );
  }

  return passengerMatch ?
    "passenger" :
    "driver";
};

const parseStoredParticipant = (
  value: unknown,
): StoredParticipant => {
  const data =
    plainRecord(value);

  if (
    data === null ||
    !exactKeys(
      data,
      ["role", "uid"],
    ) ||
    !validUid(data.uid) ||
    !isRideVoiceParticipantRole(
      data.role,
    )
  ) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      "Stored voice participant is invalid.",
    );
  }

  return {
    uid: data.uid,
    role: data.role,
  };
};

const parseActiveCallPointer = (
  data: unknown,
): ActiveCallPointer => {
  const record =
    plainRecord(data);
  const updatedAtMillis =
    record === null ?
      null :
      timestampMillis(
        record.updatedAt,
      );

  if (
    record === null ||
    !exactKeys(
      record,
      [
        "callId",
        "rideId",
        "state",
        "updatedAt",
      ],
    ) ||
    !isRideVoiceOpaqueCallId(
      record.callId,
    ) ||
    !validRideId(record.rideId) ||
    !isRideVoiceCallState(
      record.state,
    ) ||
    updatedAtMillis === null
  ) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      "Active voice call pointer is invalid.",
    );
  }

  return {
    callId: record.callId,
    rideId: record.rideId,
    state: record.state,
    updatedAtMillis,
  };
};

const parseStoredCall = (
  data: unknown,
): StoredCall => {
  const record =
    plainRecord(data);
  const createdAtMillis =
    record === null ?
      null :
      timestampMillis(
        record.createdAt,
      );
  const updatedAtMillis =
    record === null ?
      null :
      timestampMillis(
        record.updatedAt,
      );

  if (
    record === null ||
    !exactKeys(
      record,
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
    !isRideVoiceOpaqueCallId(
      record.callId,
    ) ||
    !validRideId(record.rideId) ||
    !Number.isSafeInteger(
      record.rideVersion,
    ) ||
    !isRideVoiceCallState(
      record.state,
    ) ||
    createdAtMillis === null ||
    updatedAtMillis === null
  ) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      "Stored voice call is invalid.",
    );
  }

  return {
    callId: record.callId,
    rideId: record.rideId,
    rideVersion:
      record.rideVersion as number,
    state: record.state,
    caller:
      parseStoredParticipant(
        record.caller,
      ),
    callee:
      parseStoredParticipant(
        record.callee,
      ),
    createdAtMillis,
    updatedAtMillis,
  };
};

const requireParticipantPair = (
  call: StoredCall,
  participants: RideParticipants,
): void => {
  const passengerFirst =
    call.caller.uid ===
      participants.passengerUid &&
    call.caller.role === "passenger" &&
    call.callee.uid ===
      participants.driverUid &&
    call.callee.role === "driver";

  const driverFirst =
    call.caller.uid ===
      participants.driverUid &&
    call.caller.role === "driver" &&
    call.callee.uid ===
      participants.passengerUid &&
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
  role: RideVoiceCallRecoveryActorRole,
  call: StoredCall,
): RideVoiceCallRecoveryActorSide => {
  if (
    call.caller.uid === actorUid &&
    call.caller.role === role
  ) {
    return "caller";
  }

  if (
    call.callee.uid === actorUid &&
    call.callee.role === role
  ) {
    return "callee";
  }

  throw new RideVoiceCallAuthorityError(
    "data-invalid",
    "Stored voice actor authority is invalid.",
  );
};

const selectUniqueRideId = (
  passengerPointer: ActiveRidePointer | null,
  driverPointer: ActiveRidePointer | null,
): string | null => {
  if (
    passengerPointer === null &&
    driverPointer === null
  ) {
    return null;
  }

  if (
    passengerPointer !== null &&
    driverPointer !== null &&
    passengerPointer.rideId !==
      driverPointer.rideId
  ) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      "Active ride authority is ambiguous.",
    );
  }

  return (
    passengerPointer ??
    driverPointer
  )?.rideId ?? null;
};

/**
 * Recovers the authenticated actor's authoritative active Voice call.
 *
 * No counterparty identity or push target is returned.
 *
 * @param {RideVoiceCallRecoveryDependencies} dependencies Server dependencies.
 * @param {unknown} actorUid Authenticated Firebase actor UID.
 * @param {unknown} input Exact empty recovery payload.
 * @return {Promise<RideVoiceCallRecoveryResult>} Privacy-bounded projection.
 */
export const recoverActiveRideVoiceCallForActor =
  async (
    dependencies:
      RideVoiceCallRecoveryDependencies,
    actorUid: unknown,
    input: unknown,
  ): Promise<RideVoiceCallRecoveryResult> => {
    requireEmptyInput(input);

    const uid =
      requireActorUid(actorUid);

    const passengerPointer =
      await readOptionalActiveRidePointer(
        dependencies,
        "passengerActiveRides",
        uid,
      );

    const driverIdForActor =
      await dependencies
        .resolveDriverIdForActor(uid);

    if (
      driverIdForActor !== null &&
      !validDriverId(
        driverIdForActor,
      )
    ) {
      throw new RideVoiceCallAuthorityError(
        "data-invalid",
        "Driver identity authority is invalid.",
      );
    }

    const driverPointer =
      driverIdForActor === null ?
        null :
        await readOptionalActiveRidePointer(
          dependencies,
          "driverActiveRides",
          driverIdForActor,
        );

    const rideId =
      selectUniqueRideId(
        passengerPointer,
        driverPointer,
      );

    if (rideId === null) {
      return {
        activeCall: null,
      };
    }

    const participants =
      await loadRideParticipants(
        dependencies,
        rideId,
      );

    requirePointerRideConsistency(
      passengerPointer,
      rideId,
      participants.rideStatus,
    );
    requirePointerRideConsistency(
      driverPointer,
      rideId,
      participants.rideStatus,
    );

    const role =
      resolveActorRole(
        uid,
        driverIdForActor,
        passengerPointer,
        driverPointer,
        participants,
      );

    const activeSnapshot =
      await dependencies.firestore
        .collection(
          "rideVoiceActiveCalls",
        )
        .doc(rideId)
        .get();

    if (!activeSnapshot.exists) {
      return {
        activeCall: null,
      };
    }

    const pointer =
      parseActiveCallPointer(
        activeSnapshot.data(),
      );

    if (pointer.rideId !== rideId) {
      throw new RideVoiceCallAuthorityError(
        "data-invalid",
        "Active voice call ride is inconsistent.",
      );
    }

    const callSnapshot =
      await dependencies.firestore
        .collection("rides")
        .doc(rideId)
        .collection("voiceCalls")
        .doc(pointer.callId)
        .get();

    if (!callSnapshot.exists) {
      throw new RideVoiceCallAuthorityError(
        "data-invalid",
        "Stored voice call is unavailable.",
      );
    }

    const call =
      parseStoredCall(
        callSnapshot.data(),
      );

    if (
      call.callId !== pointer.callId ||
      call.rideId !== rideId ||
      call.state !== pointer.state ||
      call.updatedAtMillis !==
        pointer.updatedAtMillis
    ) {
      throw new RideVoiceCallAuthorityError(
        "data-invalid",
        "Voice call state authority is inconsistent.",
      );
    }

    requireParticipantPair(
      call,
      participants,
    );

    const side =
      resolveActorSide(
        uid,
        role,
        call,
      );

    if (
      TERMINAL_CALL_STATES.has(
        call.state,
      )
    ) {
      return {
        activeCall: null,
      };
    }

    if (
      call.state === "ringing" &&
      !isRideVoiceEligibleRideStatus(
        participants.rideStatus,
      )
    ) {
      return {
        activeCall: null,
      };
    }

    return {
      activeCall: {
        rideId,
        callId: call.callId,
        state: call.state,
        role,
        side,
      },
    };
  };
