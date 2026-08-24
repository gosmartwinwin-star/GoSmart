import assert from "node:assert/strict";
import test from "node:test";

const projectId = "demo-gosmart";
const region = "europe-west1";

const authHost = "127.0.0.1:9099";
const functionsHost = "127.0.0.1:5001";

const sessionToken =
  "123e4567-e89b-42d3-a456-426614174000";

const isRecord = (
  value: unknown,
): value is Record<string, unknown> =>
  typeof value === "object" &&
  value !== null &&
  !Array.isArray(value);

const createAnonymousIdToken =
  async (): Promise<string> => {
    const url =
      `http://${authHost}` +
      "/identitytoolkit.googleapis.com/v1/" +
      "accounts:signUp?key=local-test-key";

    const response = await fetch(
      url,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          returnSecureToken: true,
        }),
      },
    );

    assert.equal(
      response.ok,
      true,
      "Auth emulator sign-up failed.",
    );

    const body: unknown =
      await response.json();

    assert.ok(
      isRecord(body),
      "Auth emulator response must be an object.",
    );

    const idToken = body.idToken;

    if (
      typeof idToken !== "string" ||
      idToken.length === 0
    ) {
      assert.fail(
        "Auth emulator did not return an ID token.",
      );
    }

    return idToken;
  };

const invokeCallable = async (
  name: "searchPlaces" | "resolvePlace",
  data: Record<string, unknown>,
  idToken?: string,
): Promise<Record<string, unknown>> => {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };

  if (idToken !== undefined) {
    headers.Authorization =
      `Bearer ${idToken}`;
  }

  const url =
    `http://${functionsHost}/` +
    `${projectId}/${region}/${name}`;

  const response = await fetch(
    url,
    {
      method: "POST",
      headers,
      body: JSON.stringify({data}),
    },
  );

  const body: unknown =
    await response.json();

  assert.ok(
    isRecord(body),
    "Callable response must be an object.",
  );

  return body;
};

const assertCallableError = (
  body: Record<string, unknown>,
  expectedStatus: string,
  expectedReason?: string,
): void => {
  const error = body.error;

  assert.ok(
    isRecord(error),
    "Callable must return an error envelope.",
  );

  assert.equal(
    error.status,
    expectedStatus,
  );

  if (expectedReason !== undefined) {
    const details = error.details;

    assert.ok(
      isRecord(details),
      "Callable error details must be an object.",
    );

    assert.equal(
      details.reason,
      expectedReason,
    );
  }

  const serialized =
    JSON.stringify(body);

  assert.doesNotMatch(
    serialized,
    /LOCAL_ONLY_SYNTHETIC/i,
  );

  assert.doesNotMatch(
    serialized,
    /X-Goog-Api-Key/i,
  );
};

test(
  "Places callable emulator enforces auth and validation",
  async () => {
    const runtimeProject =
      process.env.GCLOUD_PROJECT ??
      process.env.GOOGLE_CLOUD_PROJECT;

    assert.equal(
      runtimeProject,
      projectId,
      "E2E must run only against demo-gosmart.",
    );

    const unauthenticatedSearch =
      await invokeCallable(
        "searchPlaces",
        {
          input: "Taksim",
          sessionToken,
        },
      );

    assertCallableError(
      unauthenticatedSearch,
      "UNAUTHENTICATED",
    );

    const unauthenticatedDetails =
      await invokeCallable(
        "resolvePlace",
        {
          placeId: "place-1",
          sessionToken,
        },
      );

    assertCallableError(
      unauthenticatedDetails,
      "UNAUTHENTICATED",
    );

    const idToken =
      await createAnonymousIdToken();

    const invalidSearch =
      await invokeCallable(
        "searchPlaces",
        {
          input: "Ta",
          sessionToken,
        },
        idToken,
      );

    assertCallableError(
      invalidSearch,
      "INVALID_ARGUMENT",
      "invalid_place_autocomplete_payload",
    );

    const invalidDetails =
      await invokeCallable(
        "resolvePlace",
        {
          placeId: "   ",
          sessionToken,
        },
        idToken,
      );

    assertCallableError(
      invalidDetails,
      "INVALID_ARGUMENT",
      "invalid_place_details_payload",
    );
  },
);
