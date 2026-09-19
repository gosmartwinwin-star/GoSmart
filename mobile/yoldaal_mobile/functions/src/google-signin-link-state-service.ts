import {getAuth} from "firebase-admin/auth";
import {HttpsError} from "firebase-functions/v2/https";
import {OAuth2Client} from "google-auth-library";

type JsonRecord = Record<string, unknown>;

export type GoogleSignInLinkStateDependencies = {
  verifyGoogleIdToken: (
    idToken: string,
    audiences: readonly string[],
  ) => Promise<string>;
  providerUidIsLinked: (
    providerUid: string,
  ) => Promise<boolean>;
};

export type GoogleSignInLinkStateResponse = {
  linked: boolean;
};

const googleOAuthClient = new OAuth2Client();

const invalidArgument = (): HttpsError =>
  new HttpsError(
    "invalid-argument",
    "Google oturum bilgisi doğrulanamadı.",
  );

const failedPrecondition = (): HttpsError =>
  new HttpsError(
    "failed-precondition",
    "Google ile giriş henüz yapılandırılmadı.",
  );

const internalFailure = (): HttpsError =>
  new HttpsError(
    "internal",
    "Google hesabı doğrulanamadı.",
  );

const asExactInput = (
  value: unknown,
): JsonRecord => {
  if (
    value === null ||
    typeof value !== "object" ||
    Array.isArray(value)
  ) {
    throw invalidArgument();
  }

  const record = value as JsonRecord;
  const keys = Object.keys(record);

  if (
    keys.length !== 1 ||
    keys[0] !== "idToken"
  ) {
    throw invalidArgument();
  }

  return record;
};

const parseIdToken = (
  value: unknown,
): string => {
  if (typeof value !== "string") {
    throw invalidArgument();
  }

  if (
    value !== value.trim() ||
    value.length < 20 ||
    value.length > 8192
  ) {
    throw invalidArgument();
  }

  return value;
};

export const parseAllowedGoogleAudiences = (
  value: string,
): string[] => {
  const candidates = value
    .split(",")
    .map((item) => item.trim())
    .filter((item) => item.length > 0);

  const unique = [...new Set(candidates)];

  if (
    unique.length === 0 ||
    unique.length > 8
  ) {
    throw failedPrecondition();
  }

  for (const audience of unique) {
    if (
      audience.length > 512 ||
      !/^[A-Za-z0-9._-]+\.apps\.googleusercontent\.com$/u.test(
        audience,
      )
    ) {
      throw failedPrecondition();
    }
  }

  return unique;
};

const verifyGoogleIdToken = async (
  idToken: string,
  audiences: readonly string[],
): Promise<string> => {
  try {
    const ticket =
      await googleOAuthClient.verifyIdToken({
        idToken,
        audience: [...audiences],
      });

    const providerUid =
      ticket.getPayload()?.sub?.trim();

    if (!providerUid) {
      throw invalidArgument();
    }

    return providerUid;
  } catch (error: unknown) {
    if (error instanceof HttpsError) {
      throw error;
    }

    throw invalidArgument();
  }
};

const authErrorCode = (
  error: unknown,
): string | null => {
  if (
    error === null ||
    typeof error !== "object" ||
    !("code" in error)
  ) {
    return null;
  }

  const code =
    (error as {code?: unknown}).code;

  return typeof code === "string" ?
    code :
    null;
};

const providerUidIsLinked = async (
  providerUid: string,
): Promise<boolean> => {
  try {
    await getAuth().getUserByProviderUid(
      "google.com",
      providerUid,
    );

    return true;
  } catch (error: unknown) {
    if (
      authErrorCode(error) ===
      "auth/user-not-found"
    ) {
      return false;
    }

    throw internalFailure();
  }
};

const productionDependencies:
  GoogleSignInLinkStateDependencies = {
    verifyGoogleIdToken,
    providerUidIsLinked,
  };

export const resolveGoogleSignInLinkStateForToken =
async (
  data: unknown,
  allowedAudienceValue: string,
  dependencies:
    GoogleSignInLinkStateDependencies =
  productionDependencies,
): Promise<GoogleSignInLinkStateResponse> => {
  const record =
    asExactInput(data);

  const idToken =
    parseIdToken(record.idToken);

  const audiences =
    parseAllowedGoogleAudiences(
      allowedAudienceValue,
    );

  let providerUid: string;

  try {
    providerUid =
      await dependencies.verifyGoogleIdToken(
        idToken,
        audiences,
      );
  } catch (error: unknown) {
    if (error instanceof HttpsError) {
      throw error;
    }

    throw invalidArgument();
  }

  if (
    typeof providerUid !== "string" ||
    providerUid.trim().length === 0
  ) {
    throw invalidArgument();
  }

  try {
    const linked =
      await dependencies.providerUidIsLinked(
        providerUid,
      );

    return {linked};
  } catch (error: unknown) {
    if (error instanceof HttpsError) {
      throw error;
    }

    throw internalFailure();
  }
};
