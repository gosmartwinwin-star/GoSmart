import {
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  requireDriverAccessInTransaction,
} from "./driver-access-authority.js";
import {
  buildDriverLivePresenceRecord,
  validateDriverLiveLocationInput,
} from "./driver-live-presence-helpers.js";
import {
  loadApprovedDriverIdInTransaction,
} from "./ride-driver-identity.js";

export type DriverLivePresenceDependencies = {
  firestore: Firestore;
  now?: () => Timestamp;
  loadApprovedDriverIdInTransaction?:
    typeof loadApprovedDriverIdInTransaction;
  requireDriverAccessInTransaction?:
    typeof requireDriverAccessInTransaction;
};

export type DriverLivePresencePublishResult = {
  updatedAtMillis: number;
};

const accessFailure = (
  reason: string,
): HttpsError =>
  new HttpsError(
    "failed-precondition",
    "Sürücü erişimi doğrulanamadı.",
    {reason},
  );

const persistenceFailure = (): HttpsError =>
  new HttpsError(
    "unavailable",
    "Sürücü konumu yayımlanamadı.",
    {
      reason:
        "driver_live_presence_persistence_failed",
    },
  );

export const publishDriverLivePresence = async (
  dependencies: DriverLivePresenceDependencies,
  authenticatedUid: string,
  rawLocationInput: unknown,
): Promise<DriverLivePresencePublishResult> => {
  const location =
    validateDriverLiveLocationInput(
      rawLocationInput,
    );

  const now =
    dependencies.now?.() ??
    Timestamp.now();

  const identityLoader =
    dependencies.loadApprovedDriverIdInTransaction ??
    loadApprovedDriverIdInTransaction;

  const accessChecker =
    dependencies.requireDriverAccessInTransaction ??
    requireDriverAccessInTransaction;

  try {
    return await dependencies.firestore.runTransaction(
      async (transaction) => {
        const driverId =
          await identityLoader(
            dependencies.firestore,
            authenticatedUid,
            transaction,
          );

        await accessChecker({
          firestore:
            dependencies.firestore,
          transaction,
          driverId,
          now,
          failure:
            accessFailure,
        });

        const presenceReference =
          dependencies.firestore
            .collection(
              "driverLivePresences",
            )
            .doc(driverId);

        const record =
          buildDriverLivePresenceRecord(
            driverId,
            location,
            now,
          );

        transaction.set(
          presenceReference,
          record,
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

    throw persistenceFailure();
  }
};
