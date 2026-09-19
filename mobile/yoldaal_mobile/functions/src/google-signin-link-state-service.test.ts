import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";

import {
  parseAllowedGoogleAudiences,
  resolveGoogleSignInLinkStateForToken,
} from "./google-signin-link-state-service.js";
import type {
  GoogleSignInLinkStateDependencies,
} from "./google-signin-link-state-service.js";

const validToken =
  "header.payload.signature-token-value";

const validAudience =
  "1234567890-test.apps.googleusercontent.com";

const expectHttpsCode = async (
  operation: () => Promise<unknown>,
  code: string,
): Promise<void> => {
  await assert.rejects(
    operation,
    (error: unknown) => {
      assert.ok(error instanceof HttpsError);
      assert.equal(error.code, code);
      return true;
    },
  );
};

test(
  "empty audience config fails closed",
  () => {
    assert.throws(
      () => parseAllowedGoogleAudiences(""),
      (error: unknown) => {
        assert.ok(error instanceof HttpsError);
        assert.equal(
          error.code,
          "failed-precondition",
        );
        return true;
      },
    );
  },
);

test(
  "audiences are trimmed and deduplicated",
  () => {
    assert.deepEqual(
      parseAllowedGoogleAudiences(
        ` ${validAudience},${validAudience} `,
      ),
      [validAudience],
    );
  },
);

test(
  "extra client authority is rejected",
  async () => {
    const dependencies:
      GoogleSignInLinkStateDependencies = {
        verifyGoogleIdToken:
          async () => "provider-uid",
        providerUidIsLinked:
          async () => false,
      };

    await expectHttpsCode(
      () =>
        resolveGoogleSignInLinkStateForToken(
          {
            idToken: validToken,
            uid: "client-supplied-uid",
          },
          validAudience,
          dependencies,
        ),
      "invalid-argument",
    );
  },
);

test(
  "unlinked provider returns only linked false",
  async () => {
    const dependencies:
      GoogleSignInLinkStateDependencies = {
        verifyGoogleIdToken:
          async (idToken, audiences) => {
            assert.equal(
              idToken,
              validToken,
            );

            assert.deepEqual(
              audiences,
              [validAudience],
            );

            return "provider-uid";
          },
        providerUidIsLinked:
          async (providerUid) => {
            assert.equal(
              providerUid,
              "provider-uid",
            );

            return false;
          },
      };

    const result =
      await resolveGoogleSignInLinkStateForToken(
        {idToken: validToken},
        validAudience,
        dependencies,
      );

    assert.deepEqual(
      result,
      {linked: false},
    );

    assert.deepEqual(
      Object.keys(result),
      ["linked"],
    );
  },
);

test(
  "linked provider returns only linked true",
  async () => {
    const dependencies:
      GoogleSignInLinkStateDependencies = {
        verifyGoogleIdToken:
          async () => "provider-uid",
        providerUidIsLinked:
          async () => true,
      };

    const result =
      await resolveGoogleSignInLinkStateForToken(
        {idToken: validToken},
        validAudience,
        dependencies,
      );

    assert.deepEqual(
      result,
      {linked: true},
    );

    assert.deepEqual(
      Object.keys(result),
      ["linked"],
    );
  },
);

test(
  "token verifier failures are sanitized",
  async () => {
    const dependencies:
      GoogleSignInLinkStateDependencies = {
        verifyGoogleIdToken:
          async () => {
            throw new Error(
              "raw verifier detail",
            );
          },
        providerUidIsLinked:
          async () => true,
      };

    await expectHttpsCode(
      () =>
        resolveGoogleSignInLinkStateForToken(
          {idToken: validToken},
          validAudience,
          dependencies,
        ),
      "invalid-argument",
    );
  },
);

test(
  "provider lookup failures are sanitized",
  async () => {
    const dependencies:
      GoogleSignInLinkStateDependencies = {
        verifyGoogleIdToken:
          async () => "provider-uid",
        providerUidIsLinked:
          async () => {
            throw new Error(
              "raw provider detail",
            );
          },
      };

    await expectHttpsCode(
      () =>
        resolveGoogleSignInLinkStateForToken(
          {idToken: validToken},
          validAudience,
          dependencies,
        ),
      "internal",
    );
  },
);
