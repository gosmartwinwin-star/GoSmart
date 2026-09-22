import {randomBytes} from "node:crypto";
import {
  isRideVoiceCallState,
  isRideVoiceCallTransitionAllowed,
  isRideVoiceEligibleRideStatus,
  isRideVoiceTerminalCallState,
  type RideVoiceCallState,
  type RideVoiceParticipantRole,
} from "./ride-voice-call-policy.js";

const RIDE_VOICE_CALL_ID_PATTERN =
  /^rvc_[0-9a-f]{32}$/u;

const MAX_RIDE_ID_LENGTH = 256;
const MAX_UID_LENGTH = 128;

export type RideVoiceCallAuthorityErrorCode =
  | "invalid-argument"
  | "not-found"
  | "permission-denied"
  | "failed-precondition"
  | "already-exists"
  | "data-invalid";

/** Public-safe failure from the ride voice-call authority layer. */
export class RideVoiceCallAuthorityError extends Error {
  readonly code: RideVoiceCallAuthorityErrorCode;

  /**
   * Creates an authority failure with its bounded public-safe code.
   * @param {RideVoiceCallAuthorityErrorCode} code Authority error code.
   * @param {string} message Public-safe authority error message.
   */
  constructor(
    code: RideVoiceCallAuthorityErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "RideVoiceCallAuthorityError";
    this.code = code;
  }
}

export type RideVoiceAuthoritativeRide = Readonly<{
  id: string;
  version: number;
  status: unknown;
  passengerUid: string;
  driverUid: string;
}>;

export type RideVoiceExistingCall = Readonly<{
  callId: string;
  rideId: string;
  state: unknown;
}>;

export type RideVoiceCallAuthorityDependencies = Readonly<{
  loadRide: (
    rideId: string,
  ) => Promise<RideVoiceAuthoritativeRide | null>;
  loadActiveCall: (
    rideId: string,
  ) => Promise<RideVoiceExistingCall | null>;
  newOpaqueCallId?: () => string;
  nowMillis?: () => number;
}>;

export type RideVoiceCallParticipant = Readonly<{
  uid: string;
  role: RideVoiceParticipantRole;
}>;

export type RideVoiceCallCreation = Readonly<{
  callId: string;
  rideId: string;
  rideVersion: number;
  state: "ringing";
  caller: RideVoiceCallParticipant;
  callee: RideVoiceCallParticipant;
  createdAtMillis: number;
}>;

export type RideVoiceCallActorSide =
  | "caller"
  | "callee"
  | "system";

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

  return keys.length === target.length &&
    keys.every((key, index) => key === target[index]);
};

const hasControlCharacter = (
  value: string,
): boolean =>
  [...value].some((character) => {
    const codePoint = character.codePointAt(0);

    return codePoint !== undefined &&
      (codePoint <= 0x1f || codePoint === 0x7f);
  });

const isBoundedOpaqueText = (
  value: unknown,
  maxLength: number,
): value is string =>
  typeof value === "string" &&
  value.length > 0 &&
  value.length <= maxLength &&
  value.trim() === value &&
  !value.includes("/") &&
  !hasControlCharacter(value);

const requireActorUid = (
  actorUid: unknown,
): string => {
  if (!isBoundedOpaqueText(actorUid, MAX_UID_LENGTH)) {
    throw new RideVoiceCallAuthorityError(
      "permission-denied",
      "Voice actor is unavailable.",
    );
  }

  return actorUid;
};

const parseCreateInput = (
  input: unknown,
): string => {
  if (
    !isRecord(input) ||
    !hasExactKeys(input, ["rideId"]) ||
    !isBoundedOpaqueText(
      input.rideId,
      MAX_RIDE_ID_LENGTH,
    )
  ) {
    throw new RideVoiceCallAuthorityError(
      "invalid-argument",
      "Voice call request is invalid.",
    );
  }

  return input.rideId;
};

const requireAuthoritativeRide = (
  rideId: string,
  ride: RideVoiceAuthoritativeRide | null,
): RideVoiceAuthoritativeRide => {
  if (ride === null) {
    throw new RideVoiceCallAuthorityError(
      "not-found",
      "Active ride is unavailable.",
    );
  }

  if (
    ride.id !== rideId ||
    !Number.isSafeInteger(ride.version) ||
    ride.version < 1 ||
    !isBoundedOpaqueText(
      ride.passengerUid,
      MAX_UID_LENGTH,
    ) ||
    !isBoundedOpaqueText(
      ride.driverUid,
      MAX_UID_LENGTH,
    ) ||
    ride.passengerUid === ride.driverUid
  ) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      "Voice ride authority is invalid.",
    );
  }

  if (!isRideVoiceEligibleRideStatus(ride.status)) {
    throw new RideVoiceCallAuthorityError(
      "failed-precondition",
      "Ride is not voice eligible.",
    );
  }

  return ride;
};

const resolveActorParticipants = (
  actorUid: string,
  ride: RideVoiceAuthoritativeRide,
): Readonly<{
  caller: RideVoiceCallParticipant;
  callee: RideVoiceCallParticipant;
}> => {
  if (actorUid === ride.passengerUid) {
    return {
      caller: {
        uid: ride.passengerUid,
        role: "passenger",
      },
      callee: {
        uid: ride.driverUid,
        role: "driver",
      },
    };
  }

  if (actorUid === ride.driverUid) {
    return {
      caller: {
        uid: ride.driverUid,
        role: "driver",
      },
      callee: {
        uid: ride.passengerUid,
        role: "passenger",
      },
    };
  }

  throw new RideVoiceCallAuthorityError(
    "permission-denied",
    "Voice participant is unavailable.",
  );
};

export const isRideVoiceOpaqueCallId = (
  value: unknown,
): value is string =>
  typeof value === "string" &&
  RIDE_VOICE_CALL_ID_PATTERN.test(value);

export const createRideVoiceOpaqueCallId = (): string =>
  `rvc_${randomBytes(16).toString("hex")}`;

const requireExistingCall = (
  rideId: string,
  existing: RideVoiceExistingCall,
): RideVoiceCallState => {
  if (
    !isRideVoiceOpaqueCallId(existing.callId) ||
    existing.rideId !== rideId ||
    !isRideVoiceCallState(existing.state)
  ) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      "Voice call authority is invalid.",
    );
  }

  return existing.state;
};

const requireTimestampMillis = (
  value: number,
): number => {
  if (
    !Number.isSafeInteger(value) ||
    value < 0
  ) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      "Voice clock is invalid.",
    );
  }

  return value;
};

export const createRideVoiceCallForActor = async (
  dependencies: RideVoiceCallAuthorityDependencies,
  actorUidValue: unknown,
  input: unknown,
): Promise<RideVoiceCallCreation> => {
  const actorUid =
    requireActorUid(actorUidValue);

  const rideId =
    parseCreateInput(input);

  const ride =
    requireAuthoritativeRide(
      rideId,
      await dependencies.loadRide(rideId),
    );

  const participants =
    resolveActorParticipants(
      actorUid,
      ride,
    );

  const existing =
    await dependencies.loadActiveCall(rideId);

  if (existing !== null) {
    const state =
      requireExistingCall(
        rideId,
        existing,
      );

    if (!isRideVoiceTerminalCallState(state)) {
      throw new RideVoiceCallAuthorityError(
        "already-exists",
        "An active voice call already exists.",
      );
    }
  }

  const callId =
    (
      dependencies.newOpaqueCallId ??
      createRideVoiceOpaqueCallId
    )();

  if (!isRideVoiceOpaqueCallId(callId)) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      "Voice call identifier is invalid.",
    );
  }

  const createdAtMillis =
    requireTimestampMillis(
      (dependencies.nowMillis ?? Date.now)(),
    );

  return {
    callId,
    rideId: ride.id,
    rideVersion: ride.version,
    state: "ringing",
    caller: participants.caller,
    callee: participants.callee,
    createdAtMillis,
  };
};

export const isRideVoiceAuthorityTransitionAllowed = (
  actorSide: RideVoiceCallActorSide,
  from: unknown,
  to: unknown,
): boolean => {
  if (
    !isRideVoiceCallState(from) ||
    !isRideVoiceCallState(to) ||
    !isRideVoiceCallTransitionAllowed(from, to)
  ) {
    return false;
  }

  if (
    to === "missed" ||
    to === "failed"
  ) {
    return actorSide === "system";
  }

  if (
    from === "ringing" &&
    (
      to === "accepted" ||
      to === "declined"
    )
  ) {
    return actorSide === "callee";
  }

  if (
    from === "ringing" &&
    to === "cancelled"
  ) {
    return actorSide === "caller";
  }

  if (
    (
      to === "connecting" ||
      to === "active" ||
      to === "ended"
    ) &&
    (
      actorSide === "caller" ||
      actorSide === "callee"
    )
  ) {
    return true;
  }

  return false;
};
