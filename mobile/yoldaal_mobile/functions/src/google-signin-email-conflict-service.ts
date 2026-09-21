import {getAuth} from "firebase-admin/auth";
import {HttpsError} from "firebase-functions/v2/https";
import {OAuth2Client} from "google-auth-library";

export type GoogleEmailConflictIdentity = {
  email: string | null;
  emailVerified: boolean;
};

export type GoogleEmailConflictDependencies = {
  verifyEmailIdentity: (
    idToken: string,
    allowedAudiences: readonly string[],
  ) => Promise<GoogleEmailConflictIdentity>;
  hasEmailOwner: (email: string) => Promise<boolean>;
};

const googleEmailOAuthClient = new OAuth2Client();

const readFirebaseAuthErrorCode = (
  error: unknown,
): string | null => {
  if (typeof error !== "object" || error === null) {
    return null;
  }

  if (!("code" in error)) {
    return null;
  }

  const code = (error as {code?: unknown}).code;

  return typeof code === "string" ? code : null;
};

const invalidGoogleToken = (): HttpsError =>
  new HttpsError(
    "unauthenticated",
    "Google oturum bilgisi doğrulanamadı.",
  );

const emailLookupUnavailable = (): HttpsError =>
  new HttpsError(
    "unavailable",
    "Google hesap bağlantı durumu doğrulanamadı.",
  );

const verifyEmailIdentity = async (
  idToken: string,
  allowedAudiences: readonly string[],
): Promise<GoogleEmailConflictIdentity> => {
  try {
    const ticket = await googleEmailOAuthClient.verifyIdToken({
      idToken,
      audience: [...allowedAudiences],
    });

    const payload = ticket.getPayload();
    const rawEmail = payload?.email;
    const email =
      typeof rawEmail === "string" ? rawEmail.trim() : "";

    return {
      email: email.length > 0 ? email : null,
      emailVerified: payload?.email_verified === true,
    };
  } catch (_) {
    throw invalidGoogleToken();
  }
};

const hasEmailOwner = async (email: string): Promise<boolean> => {
  try {
    await getAuth().getUserByEmail(email);
    return true;
  } catch (error) {
    if (readFirebaseAuthErrorCode(error) === "auth/user-not-found") {
      return false;
    }

    throw emailLookupUnavailable();
  }
};

const productionDependencies: GoogleEmailConflictDependencies = {
  verifyEmailIdentity,
  hasEmailOwner,
};

export const resolveGoogleEmailConflictForToken = async (
  idToken: string,
  allowedAudiences: readonly string[],
  dependencies: GoogleEmailConflictDependencies =
  productionDependencies,
): Promise<boolean> => {
  const identity = await dependencies.verifyEmailIdentity(
    idToken,
    allowedAudiences,
  );

  if (!identity.emailVerified || identity.email === null) {
    return false;
  }

  return dependencies.hasEmailOwner(identity.email);
};
