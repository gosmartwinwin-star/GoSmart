import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {join} from "node:path";
import test from "node:test";

test(
  "production index exposes authenticated account deletion request callable",
  () => {
    const source = readFileSync(
      join(process.cwd(), "src", "index.ts"),
      "utf8",
    );

    assert.match(
      source,
      new RegExp(
        String.raw`import\s*\{\s*requestAccountDeletionForUser,?\s*\}` +
          String.raw`\s*from\s*` +
          String.raw`"\.\/account-deletion-request-authority\.js";`,
        "u",
      ),
    );

    assert.match(
      source,
      /export const requestAccountDeletion = onCall\(/u,
    );

    assert.match(
      source,
      /if \(!request\.auth\?\.uid\)/u,
    );

    assert.match(
      source,
      new RegExp(
        String.raw`requestAccountDeletionForUser\(` +
          String.raw`\s*\{firestore\},\s*request\.auth\.uid,` +
          String.raw`\s*request\.data,\s*\)`,
        "u",
      ),
    );
  },
);
