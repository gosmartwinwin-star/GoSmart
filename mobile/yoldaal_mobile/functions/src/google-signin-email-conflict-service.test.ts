import {strict as assert} from "node:assert";
import {readFileSync} from "node:fs";
import {test} from "node:test";

import {
  resolveGoogleEmailConflictForToken,
} from "./google-signin-email-conflict-service.js";
import type {
  GoogleEmailConflictDependencies,
} from "./google-signin-email-conflict-service.js";

const audiences = [
  "1234567890-test.apps.googleusercontent.com",
];

test("verified Google email with owner is a bounded conflict", async () => {
  let lookupCount = 0;

  const dependencies: GoogleEmailConflictDependencies = {
    verifyEmailIdentity: async () => ({
      email: "fixture@example.invalid",
      emailVerified: true,
    }),
    hasEmailOwner: async () => {
      lookupCount += 1;
      return true;
    },
  };

  const result = await resolveGoogleEmailConflictForToken(
    "opaque-token",
    audiences,
    dependencies,
  );

  assert.equal(result, true);
  assert.equal(lookupCount, 1);
});

test("verified Google email without owner is not a conflict", async () => {
  const dependencies: GoogleEmailConflictDependencies = {
    verifyEmailIdentity: async () => ({
      email: "fixture@example.invalid",
      emailVerified: true,
    }),
    hasEmailOwner: async () => false,
  };

  assert.equal(
    await resolveGoogleEmailConflictForToken(
      "opaque-token",
      audiences,
      dependencies,
    ),
    false,
  );
});

test("unverified email cannot become account authority", async () => {
  let lookupCount = 0;

  const dependencies: GoogleEmailConflictDependencies = {
    verifyEmailIdentity: async () => ({
      email: "fixture@example.invalid",
      emailVerified: false,
    }),
    hasEmailOwner: async () => {
      lookupCount += 1;
      return true;
    },
  };

  assert.equal(
    await resolveGoogleEmailConflictForToken(
      "opaque-token",
      audiences,
      dependencies,
    ),
    false,
  );

  assert.equal(lookupCount, 0);
});

test("missing email cannot become account authority", async () => {
  let lookupCount = 0;

  const dependencies: GoogleEmailConflictDependencies = {
    verifyEmailIdentity: async () => ({
      email: null,
      emailVerified: true,
    }),
    hasEmailOwner: async () => {
      lookupCount += 1;
      return true;
    },
  };

  assert.equal(
    await resolveGoogleEmailConflictForToken(
      "opaque-token",
      audiences,
      dependencies,
    ),
    false,
  );

  assert.equal(lookupCount, 0);
});

test("resolver wire contract exposes no identity PII", () => {
  const source = readFileSync(
    "src/google-signin-link-state-service.ts",
    "utf8",
  );

  assert.match(source, /resolveEmailOwnerConflict\?:/u);
  assert.match(
    source,
    /resolveEmailOwnerConflict:\s*resolveGoogleEmailConflictForToken/u,
  );
  assert.match(
    source,
    /return \{linked: false, accountConflict: true\};/u,
  );
  assert.equal(/['"]email['"]\s*:/u.test(source), false);
  assert.equal(/['"]uid['"]\s*:/u.test(source), false);
});

test("conflict helper has no destructive account operation", () => {
  const source = readFileSync(
    "src/google-signin-email-conflict-service.ts",
    "utf8",
  );

  assert.equal(source.includes("deleteUser("), false);
  assert.equal(source.includes("updateUser("), false);
  assert.equal(source.includes("linkWithCredential"), false);
  assert.equal(source.includes("console."), false);
  assert.equal(source.includes("logger."), false);
});
