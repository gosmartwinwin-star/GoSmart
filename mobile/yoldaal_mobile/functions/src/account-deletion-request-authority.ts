import {FieldValue, type Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

const ACCOUNT_DELETION_REQUEST_COLLECTION = "accountDeletionRequests";

export type AccountDeletionRequestResult = {
  status: "requested";
  alreadyRequested: boolean;
};

export const validateAccountDeletionRequestPayload = (
  rawInput: unknown,
): void => {
  if (rawInput === null || rawInput === undefined) {
    return;
  }

  if (
    typeof rawInput !== "object" ||
    Array.isArray(rawInput)
  ) {
    throw new HttpsError(
      "invalid-argument",
      "Hesap silme talebi geçersiz.",
    );
  }

  const keys = Object.keys(
    rawInput as Record<string, unknown>,
  );

  if (keys.length !== 0) {
    throw new HttpsError(
      "invalid-argument",
      "Hesap silme talebi kullanıcı kimliği veya ek alan içeremez.",
    );
  }
};

export const requestAccountDeletionForUser = async (
  dependencies: {
    firestore: Firestore;
  },
  authUid: string,
  rawInput: unknown,
): Promise<AccountDeletionRequestResult> => {
  validateAccountDeletionRequestPayload(rawInput);

  if (authUid.trim().length === 0) {
    throw new HttpsError(
      "unauthenticated",
      "Hesap silme talebi için oturum açmanız gereklidir.",
    );
  }

  const requestRef = dependencies.firestore
    .collection(ACCOUNT_DELETION_REQUEST_COLLECTION)
    .doc(authUid);

  return dependencies.firestore.runTransaction(
    async (transaction) => {
      const snapshot = await transaction.get(requestRef);

      if (snapshot.exists) {
        const data = snapshot.data();

        if (
          data?.authUid !== authUid ||
          data?.status !== "requested" ||
          data?.source !== "in_app"
        ) {
          throw new HttpsError(
            "failed-precondition",
            "Mevcut hesap silme talebi doğrulanamadı.",
          );
        }

        return {
          status: "requested",
          alreadyRequested: true,
        };
      }

      const serverTimestamp =
        FieldValue.serverTimestamp();

      transaction.set(
        requestRef,
        {
          authUid,
          status: "requested",
          source: "in_app",
          requestedAt: serverTimestamp,
          updatedAt: serverTimestamp,
        },
      );

      return {
        status: "requested",
        alreadyRequested: false,
      };
    },
  );
};
