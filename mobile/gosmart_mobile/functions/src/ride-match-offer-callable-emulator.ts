/* eslint-disable max-len */
import assert from "node:assert/strict";
import test from "node:test";

type JsonRecord = Record<string, unknown>;

type AuthSession = {
  uid: string;
  idToken: string;
};

/** Sanitized callable failure returned by emulator boundary tests. */
class CallableFailure extends Error {
  /** Creates a sanitized callable failure. */
  constructor(
    readonly httpStatus: number,
    readonly status: string,
    readonly reason: string | null,
  ) {
    super(
      `Callable failed: http=${httpStatus} status=${status}`,
    );
  }
}

const projectId = "demo-gosmart";
const region = "europe-west1";
const callableName = "getMyRideMatchOffers";

let sequence = 0;

const requiredEnvironment = (
  name: string,
): string => {
  const value =
    process.env[name]?.trim();

  if (!value) {
    throw new Error(
      `${name} must be provided by Firebase emulators.`,
    );
  }

  return value;
};

const assertLoopbackHost = (
  name: string,
  value: string,
): void => {
  const normalized =
    value.trim().toLowerCase();

  const accepted =
    normalized === "localhost" ||
    normalized.startsWith("localhost:") ||
    normalized === "127.0.0.1" ||
    normalized.startsWith("127.0.0.1:") ||
    normalized === "::1" ||
    normalized.startsWith("[::1]:");

  if (!accepted) {
    throw new Error(
      `${name} must use a loopback host.`,
    );
  }
};

const authHost =
  requiredEnvironment(
    "FIREBASE_AUTH_EMULATOR_HOST",
  );

const firestoreHost =
  requiredEnvironment(
    "FIRESTORE_EMULATOR_HOST",
  );

const functionsHost =
  process.env
    .FUNCTIONS_EMULATOR_HOST
    ?.trim() ||
  "127.0.0.1:5001";

assertLoopbackHost(
  "FIREBASE_AUTH_EMULATOR_HOST",
  authHost,
);

assertLoopbackHost(
  "FIRESTORE_EMULATOR_HOST",
  firestoreHost,
);

assertLoopbackHost(
  "FUNCTIONS_EMULATOR_HOST",
  functionsHost,
);

for (const key of [
  "GCLOUD_PROJECT",
  "GOOGLE_CLOUD_PROJECT",
  "FIREBASE_PROJECT_ID",
]) {
  const value =
    process.env[key]?.trim();

  if (
    value &&
    value !== projectId
  ) {
    throw new Error(
      `${key} must be ${projectId}.`,
    );
  }
}

const unique = (
  label: string,
): string => {
  sequence += 1;

  return [
    label,
    process.pid,
    Date.now(),
    sequence,
  ].join("_");
};

const asRecord = (
  value: unknown,
  label: string,
): JsonRecord => {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value)
  ) {
    throw new Error(
      `${label} must be a JSON object.`,
    );
  }

  return value as JsonRecord;
};

const requireString = (
  record: JsonRecord,
  key: string,
  label: string,
): string => {
  const value =
    record[key];

  if (
    typeof value !== "string" ||
    value.length === 0
  ) {
    throw new Error(
      `${label}.${key} must be a non-empty string.`,
    );
  }

  return value;
};

const signUp = async (): Promise<AuthSession> => {
  const syntheticApiKey =
    "AIza00000000000000000000000000000000000";

  const response =
    await fetch(
      `http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=${syntheticApiKey}`,
      {
        method: "POST",
        headers: {
          "Content-Type":
            "application/json",
        },
        body: JSON.stringify({
          email:
            `${unique("match_offer_driver")}@example.test`,
          password:
            `GoSmart_${unique("password")}_A1`,
          returnSecureToken: true,
        }),
      },
    );

  const envelope =
    asRecord(
      await response.json(),
      "Auth response",
    );

  if (!response.ok) {
    const error =
      typeof envelope.error === "object" &&
      envelope.error !== null ?
        envelope.error as JsonRecord :
        {};

    const message =
      typeof error.message === "string" ?
        error.message :
        "unknown";

    throw new Error(
      `Auth emulator sign-up failed: ${message}`,
    );
  }

  return {
    uid:
      requireString(
        envelope,
        "localId",
        "Auth response",
      ),
    idToken:
      requireString(
        envelope,
        "idToken",
        "Auth response",
      ),
  };
};

const invokeCallable = async (
  data: JsonRecord,
  idToken?: string,
): Promise<JsonRecord> => {
  const headers:
    Record<string, string> = {
      "Content-Type":
        "application/json",
    };

  if (idToken) {
    headers.Authorization =
      `Bearer ${idToken}`;
  }

  const response =
    await fetch(
      `http://${functionsHost}/${projectId}/${region}/${callableName}`,
      {
        method: "POST",
        headers,
        body: JSON.stringify({
          data,
        }),
      },
    );

  const envelope =
    asRecord(
      await response.json(),
      "Callable response",
    );

  if (
    !response.ok ||
    envelope.error !== undefined
  ) {
    const error =
      typeof envelope.error === "object" &&
      envelope.error !== null ?
        envelope.error as JsonRecord :
        {};

    const status =
      typeof error.status === "string" ?
        error.status :
        "UNKNOWN";

    const details =
      typeof error.details === "object" &&
      error.details !== null &&
      !Array.isArray(error.details) ?
        error.details as JsonRecord :
        {};

    const reason =
      typeof details.reason === "string" ?
        details.reason :
        null;

    throw new CallableFailure(
      response.status,
      status,
      reason,
    );
  }

  const value =
    Object.prototype.hasOwnProperty.call(
      envelope,
      "result",
    ) ?
      envelope.result :
      envelope.data;

  return asRecord(
    value,
    "Callable result",
  );
};

const expectCallableFailure = async (
  operation: Promise<unknown>,
  expectedStatus: string,
  expectedReason: string | null,
): Promise<void> => {
  try {
    await operation;

    assert.fail(
      `Expected callable failure ${expectedStatus}.`,
    );
  } catch (error: unknown) {
    assert.ok(
      error instanceof CallableFailure,
    );

    assert.equal(
      error.status,
      expectedStatus,
    );

    assert.equal(
      error.reason,
      expectedReason,
    );
  }
};

test(
  "unauthenticated discovery is rejected before service access",
  async () => {
    await expectCallableFailure(
      invokeCallable({}),
      "UNAUTHENTICATED",
      null,
    );
  },
);

test(
  "authenticated injected payload is rejected before discovery service",
  async () => {
    const session =
      await signUp();

    assert.ok(
      session.uid.length > 0,
    );

    await expectCallableFailure(
      invokeCallable(
        {
          driverId:
            "client_must_not_supply_driver",
        },
        session.idToken,
      ),
      "INVALID_ARGUMENT",
      "invalid_ride_match_offer_payload",
    );
  },
);

test(
  "authenticated user without driver profile fails before route measurement",
  async () => {
    const session =
      await signUp();

    await expectCallableFailure(
      invokeCallable(
        {},
        session.idToken,
      ),
      "PERMISSION_DENIED",
      "driver_profile_required",
    );
  },
);
/* eslint-enable max-len */
