import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

const here = path.resolve("src");
const indexSource = fs.readFileSync(path.join(here, "index.ts"), "utf8");
const authoritySource = fs.readFileSync(
  path.join(here, "account-deletion-execution-authority.ts"),
  "utf8",
);

test("index exports the account deletion execution callable", () => {
  assert.match(
    indexSource,
    /export const executeAccountDeletion = onCall\(/u,
  );
  assert.match(
    indexSource,
    new RegExp(
      "executeAccountDeletionCallable\\(\\s*request\\.auth\\?\\.uid," +
        "\\s*request\\.data\\s*,?\\s*\\)",
      "u",
    ),
  );
});

test("execution authority keeps frozen destructive boundaries", () => {
  assert.match(authoritySource, /deleted-passenger/u);
  assert.match(authoritySource, /deleted-driver/u);
  assert.match(authoritySource, /driverApplicationUploads/u);
  assert.match(authoritySource, /driverApplicationSubmissions/u);
  assert.match(authoritySource, /collection\("rideVoiceActiveCalls"\)/u);
  assert.doesNotMatch(authoritySource, /driverActiveReturnRoutes/u);
  assert.doesNotMatch(
    authoritySource,
    /collection\("supportCases"\)/u,
  );
  assert.doesNotMatch(authoritySource, /collection\("messages"\)/u);
  assert.match(authoritySource, /getAuth\(\)\.deleteUser\(uid\)/u);
  assert.match(authoritySource, /executionLeaseId/u);
  assert.match(authoritySource, /leaseExpiresAt/u);
  assert.match(authoritySource, /randomUUID\(\)/u);
  assert.match(authoritySource, /auth\/user-not-found/u);
  assert.doesNotMatch(authoritySource, /checkpoint/u);
  assert.ok(
    authoritySource.indexOf("anonymizeDriverProfile") <
      authoritySource.indexOf("getAuth().deleteUser(uid)"),
  );
});
