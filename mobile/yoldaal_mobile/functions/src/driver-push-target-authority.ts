import {
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  requireDriverAccessInTransaction,
} from "./driver-access-authority.js";
import {
  loadApprovedDriverIdInTransaction,
} from "./ride-driver-identity.js";

export type DriverPushPlatform =
  "android" |
  "ios";

export type PersistedDriverPushTarget = {
  driverId: string;
  fid: string;
  platform: DriverPushPlatform;
  updatedAt: Timestamp;
};

export type DriverPushTargetDependencies = {
  firestore: Firestore;
  now?: () => Timestamp;
  loadApprovedDriverIdInTransaction?:
    typeof loadApprovedDriverIdInTransaction;
  requireDriverAccessInTransaction?:
    typeof requireDriverAccessInTransaction;
};

const failure = (
  code:
    "invalid-argument" |
    "failed-precondition" |
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
    Array.isArray(value) ||
    Object.getPrototypeOf(value) !==
      Object.prototype
  ) {
    return null;
  }

  return value as Record<string, unknown>;
};

const validFid = (
  value: unknown,
): value is string =>
  typeof value === "string" &&
  value.length >= 8 &&
  value.length <= 512 &&
  value.trim() === value &&
  !/\s/u.test(value);

const validDriverId = (
  value: unknown,
): value is string =>
  typeof value === "string" &&
  value.length > 0 &&
  value.trim() === value &&
  !/\s/u.test(value);

const validPlatform = (
  value: unknown,
): value is DriverPushPlatform =>
  value === "android" ||
  value === "ios";

export const validateRegisterDriverPushTargetPayload = (
  value: unknown,
): {
  fid: string;
  platform: DriverPushPlatform;
} => {
  const data =
    plainRecord(value);

  if (data === null) {
    throw failure(
      "invalid-argument",
      "driver_push_payload_invalid",
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
      "driver_push_payload_invalid",
    );
  }

  if (!validFid(data.fid)) {
    throw failure(
      "invalid-argument",
      "driver_push_fid_invalid",
    );
  }

  if (!validPlatform(data.platform)) {
    throw failure(
      "invalid-argument",
      "driver_push_platform_invalid",
    );
  }

  return {
    fid: data.fid,
    platform: data.platform,
  };
};

export const parsePersistedDriverPushTarget = (
  driverIdValue: unknown,
  value: unknown,
): PersistedDriverPushTarget | null => {
  if (!validDriverId(driverIdValue)) {
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
    keys[0] !== "driverId" ||
    keys[1] !== "fid" ||
    keys[2] !== "platform" ||
    keys[3] !== "updatedAt" ||
    data.driverId !== driverIdValue ||
    !validFid(data.fid) ||
    !validPlatform(data.platform) ||
    !(data.updatedAt instanceof Timestamp)
  ) {
    return null;
  }

  return {
    driverId: driverIdValue,
    fid: data.fid,
    platform: data.platform,
    updatedAt: data.updatedAt,
  };
};
export const registerDriverPushTarget = async (
  dependencies: DriverPushTargetDependencies,
  authenticatedUid: string,
  rawInput: unknown,
): Promise<{updatedAtMillis: number}> => {
  const input =
    validateRegisterDriverPushTargetPayload(
      rawInput,
    );

  const now =
    dependencies.now?.() ??
    Timestamp.now();

  const loadIdentity =
    dependencies
      .loadApprovedDriverIdInTransaction ??
    loadApprovedDriverIdInTransaction;

  const checkAccess =
    dependencies
      .requireDriverAccessInTransaction ??
    requireDriverAccessInTransaction;

  try {
    return await dependencies.firestore
      .runTransaction(
        async (transaction) => {
          const driverId =
            await loadIdentity(
              dependencies.firestore,
              authenticatedUid,
              transaction,
            );

          await checkAccess({
            firestore:
              dependencies.firestore,
            transaction,
            driverId,
            now,
            failure: (reason) =>
              failure(
                "failed-precondition",
                reason,
              ),
          });

          const reference =
            dependencies.firestore
              .collection(
                "driverPushTargets",
              )
              .doc(driverId);

          transaction.set(
            reference,
            {
              driverId,
              fid:
                input.fid,
              platform:
                input.platform,
              updatedAt:
                now,
            },
          );

          return {
            updatedAtMillis:
              now.toMillis(),
          };
        },
      );
  } catch (error: unknown) {
    if (error instanceof HttpsError) {
      throw error;
    }

    throw failure(
      "unavailable",
      "driver_push_target_persistence_failed",
    );
  }
};
