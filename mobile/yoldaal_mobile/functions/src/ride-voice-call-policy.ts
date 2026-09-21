export const RIDE_VOICE_CALL_STATES = [
  "ringing",
  "accepted",
  "connecting",
  "active",
  "ended",
  "declined",
  "cancelled",
  "missed",
  "failed",
] as const;

export type RideVoiceCallState =
  typeof RIDE_VOICE_CALL_STATES[number];

export const RIDE_VOICE_PARTICIPANT_ROLES = [
  "driver",
  "passenger",
] as const;

export type RideVoiceParticipantRole =
  typeof RIDE_VOICE_PARTICIPANT_ROLES[number];

export const RIDE_VOICE_ELIGIBLE_RIDE_STATUSES = [
  "driverEnRoute",
  "driverArrived",
  "inProgress",
] as const;

export type RideVoiceEligibleRideStatus =
  typeof RIDE_VOICE_ELIGIBLE_RIDE_STATUSES[number];

export const RIDE_VOICE_TERMINAL_CALL_STATES = [
  "ended",
  "declined",
  "cancelled",
  "missed",
  "failed",
] as const;

const callStateSet =
  new Set<string>(RIDE_VOICE_CALL_STATES);

const participantRoleSet =
  new Set<string>(RIDE_VOICE_PARTICIPANT_ROLES);

const eligibleRideStatusSet =
  new Set<string>(RIDE_VOICE_ELIGIBLE_RIDE_STATUSES);

const terminalCallStateSet =
  new Set<string>(RIDE_VOICE_TERMINAL_CALL_STATES);

const transitionTargets:
  Readonly<Record<RideVoiceCallState, ReadonlySet<RideVoiceCallState>>> = {
    ringing: new Set<RideVoiceCallState>([
      "accepted",
      "declined",
      "cancelled",
      "missed",
      "failed",
    ]),
    accepted: new Set<RideVoiceCallState>([
      "connecting",
      "ended",
      "failed",
    ]),
    connecting: new Set<RideVoiceCallState>([
      "active",
      "ended",
      "failed",
    ]),
    active: new Set<RideVoiceCallState>([
      "ended",
      "failed",
    ]),
    ended: new Set<RideVoiceCallState>(),
    declined: new Set<RideVoiceCallState>(),
    cancelled: new Set<RideVoiceCallState>(),
    missed: new Set<RideVoiceCallState>(),
    failed: new Set<RideVoiceCallState>(),
  };

export const isRideVoiceCallState = (
  value: unknown,
): value is RideVoiceCallState =>
  typeof value === "string" &&
  callStateSet.has(value);

export const isRideVoiceParticipantRole = (
  value: unknown,
): value is RideVoiceParticipantRole =>
  typeof value === "string" &&
  participantRoleSet.has(value);

export const isRideVoiceEligibleRideStatus = (
  value: unknown,
): value is RideVoiceEligibleRideStatus =>
  typeof value === "string" &&
  eligibleRideStatusSet.has(value);

export const isRideVoiceTerminalCallState = (
  value: unknown,
): value is RideVoiceCallState =>
  typeof value === "string" &&
  terminalCallStateSet.has(value);

export const isRideVoiceCallTransitionAllowed = (
  from: unknown,
  to: unknown,
): boolean => {
  if (
    !isRideVoiceCallState(from) ||
    !isRideVoiceCallState(to)
  ) {
    return false;
  }

  return transitionTargets[from].has(to);
};
