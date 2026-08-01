import {HttpsError} from "firebase-functions/v2/https";
/* eslint-disable max-len */

type AuthContext = {uid: string; token: Record<string, unknown>} | null | undefined;

export const requireGoSmartAdmin = (auth: AuthContext): string => {
  if (!auth) {
    throw new HttpsError("unauthenticated", "Kimlik doğrulaması gereklidir.",
      {reason: "authentication_required"});
  }
  if (auth.token.gosmartAdmin !== true) {
    throw new HttpsError("permission-denied", "Yönetici erişimi gereklidir.",
      {reason: "admin_access_required"});
  }
  return auth.uid;
};
