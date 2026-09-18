/* eslint-disable max-len */
import {
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

export type PassengerPushPlatform =
  "android" |
  "ios";

export type PersistedPassengerPushTarget = {
  passengerId: string;
  fid: string;
  platform: PassengerPushPlatform;
  updatedAt: Timestamp;
};

export type PassengerPushTargetDependencies = {
  firestore: Firestore;
  now?: () => Timestamp;
};

const failure = (
  code:
    "invalid-argument" |
    "unavailable",
  reason: string,
): HttpsError =>
  new HttpsError(
    code,
    "Bildirim hedefi işlemi tamamlanamadı.",
    {reason},
  );

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

const validPassengerId = (
  value: unknown,
): value is string =>
  typeof value === "string" &&
  value.length > 0 &&
  value.length <= 128 &&
  value.trim() === value &&
  !value.includes("/");

const validFid = (
  value: unknown,
): value is string =>
  typeof value === "string" &&
  value.length >= 8 &&
  value.length <= 512 &&
  !/\s/u.test(value);

const validPlatform = (
  value: unknown,
): value is PassengerPushPlatform =>
  value === "android" ||
  value === "ios";

export const validateRegisterPassengerPushTargetPayload = (
  value: unknown,
): {
  fid: string;
  platform: PassengerPushPlatform;
} => {
  const data =
    plainRecord(value);

  if (data === null) {
    throw failure(
      "invalid-argument",
      "passenger_push_payload_invalid",
    );
  }

  const keys =
    Object.keys(data).sort();

  if (
    keys.length !== 2 ||
    keys[0] !== "fid" ||
    keys[1] !== "platform"
  ) {
    throw failure(
      "invalid-argument",
      "passenger_push_payload_invalid",
    );
  }

  if (!validFid(data.fid)) {
    throw failure(
      "invalid-argument",
      "passenger_push_fid_invalid",
    );
  }

  if (!validPlatform(data.platform)) {
    throw failure(
      "invalid-argument",
      "passenger_push_platform_invalid",
    );
  }

  return {
    fid: data.fid,
    platform: data.platform,
  };
};

export const parsePersistedPassengerPushTarget = (
  passengerIdValue: unknown,
  value: unknown,
): PersistedPassengerPushTarget | null => {
  if (!validPassengerId(passengerIdValue)) {
    return null;
  }

  const data =
    plainRecord(value);

  if (data === null) {
    return null;
  }

  const keys =
    Object.keys(data).sort();

  if (
    keys.length !== 4 ||
    keys[0] !== "fid" ||
    keys[1] !== "passengerId" ||
    keys[2] !== "platform" ||
    keys[3] !== "updatedAt" ||
    data.passengerId !== passengerIdValue ||
    !validFid(data.fid) ||
    !validPlatform(data.platform) ||
    !(data.updatedAt instanceof Timestamp)
  ) {
    return null;
  }

  return {
    passengerId: passengerIdValue,
    fid: data.fid,
    platform: data.platform,
    updatedAt: data.updatedAt,
  };
};

export const registerPassengerPushTarget = async (
  dependencies: PassengerPushTargetDependencies,
  authenticatedUid: string,
  rawInput: unknown,
): Promise<{updatedAtMillis: number}> => {
  if (!validPassengerId(authenticatedUid)) {
    throw failure(
      "invalid-argument",
      "passenger_push_actor_invalid",
    );
  }

  const input =
    validateRegisterPassengerPushTargetPayload(
      rawInput,
    );

  const now =
    dependencies.now?.() ??
    Timestamp.now();

  const reference =
    dependencies.firestore
      .collection(
        "passengerPushTargets",
      )
      .doc(authenticatedUid);

  try {
    await reference.set({
      passengerId:
        authenticatedUid,
      fid:
        input.fid,
      platform:
        input.platform,
      updatedAt:
        now,
    });

    return {
      updatedAtMillis:
        now.toMillis(),
    };
  } catch (error: unknown) {
    if (error instanceof HttpsError) {
      throw error;
    }

    throw failure(
      "unavailable",
      "passenger_push_target_persistence_failed",
    );
  }
};
