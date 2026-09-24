import {RtcTokenBuilder} from "agora-token";

import {
  RideVoiceCallAuthorityError,
} from "./ride-voice-call-authority.js";
import type {
  RideVoiceCallRecoveryResult,
} from "./ride-voice-call-recovery-authority.js";

const RTC_TOKEN_TTL_SECONDS = 900;
const RTC_TOKEN_TTL_MILLIS =
  RTC_TOKEN_TTL_SECONDS * 1000;
const RTC_CALLER_UID = 1;
const RTC_CALLEE_UID = 2;
const AGORA_CREDENTIAL_PATTERN =
  /^[0-9a-f]{32}$/iu;
const MAX_TOKEN_LENGTH = 4096;

type PlainRecord =
  Record<string, unknown>;

export type RideVoiceRtcTokenBuilder = (
  appId: string,
  appCertificate: string,
  channelName: string,
  uid: number,
  tokenExpireSeconds: number,
  joinPrivilegeExpireSeconds: number,
  audioPrivilegeExpireSeconds: number,
  videoPrivilegeExpireSeconds: number,
  dataPrivilegeExpireSeconds: number,
) => string;

export type RideVoiceRtcSessionDependencies =
  Readonly<{
    recoverActiveCall: (
      actorUid: unknown,
      input: unknown,
    ) => Promise<RideVoiceCallRecoveryResult>;
    appId: string;
    appCertificate: string;
    nowMillis?: () => number;
    buildToken?: RideVoiceRtcTokenBuilder;
  }>;

export type RideVoiceRtcSession =
  Readonly<{
    appId: string;
    channelName: string;
    token: string;
    rtcUid: number;
    expiresAtMillis: number;
  }>;

const plainRecord = (
  value: unknown,
): PlainRecord | null =>
  typeof value === "object" &&
  value !== null &&
  !Array.isArray(value) ?
    value as PlainRecord :
    null;

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
      "Voice RTC session payload is invalid.",
    );
  }
};

const requireAgoraCredential = (
  value: unknown,
): string => {
  if (
    typeof value !== "string" ||
    !AGORA_CREDENTIAL_PATTERN.test(value)
  ) {
    throw new RideVoiceCallAuthorityError(
      "failed-precondition",
      "Voice RTC configuration is unavailable.",
    );
  }

  return value;
};

const requireNowMillis = (
  value: number,
): number => {
  if (
    !Number.isSafeInteger(value) ||
    value < 0 ||
    !Number.isSafeInteger(
      value + RTC_TOKEN_TTL_MILLIS,
    )
  ) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      "Voice RTC clock is invalid.",
    );
  }

  return value;
};

const requireToken = (
  value: unknown,
): string => {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > MAX_TOKEN_LENGTH ||
    value.trim() !== value
  ) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      "Voice RTC token is invalid.",
    );
  }

  return value;
};

const defaultBuildToken:
  RideVoiceRtcTokenBuilder =
  (
    appId,
    appCertificate,
    channelName,
    uid,
    tokenExpireSeconds,
    joinPrivilegeExpireSeconds,
    audioPrivilegeExpireSeconds,
    videoPrivilegeExpireSeconds,
    dataPrivilegeExpireSeconds,
  ) =>
    RtcTokenBuilder
      .buildTokenWithUidAndPrivilege(
        appId,
        appCertificate,
        channelName,
        uid,
        tokenExpireSeconds,
        joinPrivilegeExpireSeconds,
        audioPrivilegeExpireSeconds,
        videoPrivilegeExpireSeconds,
        dataPrivilegeExpireSeconds,
      );

/**
 * Creates the authenticated actor's short-lived audio-only RTC join session.
 *
 * Active call identity and actor side come only from authoritative Voice
 * recovery. The client cannot select a ride, call, participant, channel,
 * or Agora RTC UID.
 *
 * @param {RideVoiceRtcSessionDependencies} dependencies Server dependencies.
 * @param {unknown} actorUid Authenticated Firebase actor UID.
 * @param {unknown} input Exact empty callable payload.
 * @return {Promise<RideVoiceRtcSession>} Privacy-bounded RTC join projection.
 */
export const getRideVoiceRtcSessionForActor =
  async (
    dependencies:
      RideVoiceRtcSessionDependencies,
    actorUid: unknown,
    input: unknown,
  ): Promise<RideVoiceRtcSession> => {
    requireEmptyInput(input);

    const recovery =
      await dependencies.recoverActiveCall(
        actorUid,
        input,
      );
    const call =
      recovery.activeCall;

    if (
      call === null ||
      (
        call.state !== "accepted" &&
        call.state !== "connecting" &&
        call.state !== "active"
      )
    ) {
      throw new RideVoiceCallAuthorityError(
        "failed-precondition",
        "Voice RTC session is unavailable.",
      );
    }

    const appId =
      requireAgoraCredential(
        dependencies.appId,
      );
    const appCertificate =
      requireAgoraCredential(
        dependencies.appCertificate,
      );

    const rtcUid =
      call.side === "caller" ?
        RTC_CALLER_UID :
        RTC_CALLEE_UID;

    const nowMillis =
      requireNowMillis(
        (dependencies.nowMillis ?? Date.now)(),
      );

    const token =
      requireToken(
        (
          dependencies.buildToken ??
          defaultBuildToken
        )(
          appId,
          appCertificate,
          call.callId,
          rtcUid,
          RTC_TOKEN_TTL_SECONDS,
          RTC_TOKEN_TTL_SECONDS,
          RTC_TOKEN_TTL_SECONDS,
          0,
          0,
        ),
      );

    return {
      appId,
      channelName: call.callId,
      token,
      rtcUid,
      expiresAtMillis:
        nowMillis + RTC_TOKEN_TTL_MILLIS,
    };
  };
