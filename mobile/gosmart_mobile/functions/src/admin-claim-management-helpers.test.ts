import assert from "node:assert/strict";
import {describe, it} from "node:test";
import {
  buildUpdatedCustomClaims,
  GOSMART_FIREBASE_PROJECT_ID,
  maskUidForConsole,
  parseAdminClaimCommand,
  validateFirebaseProjectId,
} from "./admin-claim-management-helpers.js";

const base = [
  "--project-id", GOSMART_FIREBASE_PROJECT_ID, "--uid", "User_123",
];

describe("admin claim command", () => {
  it("parses project, UID, enable and dry-run", () => {
    const command = parseAdminClaimCommand([
      ...base, "--enable", "--dry-run",
    ]);
    assert.deepEqual(command, {
      projectId: GOSMART_FIREBASE_PROJECT_ID, uid: "User_123",
      action: "enable", dryRun: true,
    });
  });

  it("parses disable", () => {
    const command = parseAdminClaimCommand([...base, "--disable"]);
    assert.equal(command.action, "disable");
  });

  for (const args of [
    ["--uid", "User_123", "--enable"],
    ["--project-id", "--uid", "User_123", "--enable"],
    ["--project-id", "", "--uid", "User_123", "--enable"],
    ["--project-id", "other-project", "--uid", "User_123", "--enable"],
    ["--project-id", "GOSMART-FD8F6", "--uid", "User_123", "--enable"],
    ["--project", GOSMART_FIREBASE_PROJECT_ID, "--uid", "User_123", "--enable"],
    ["--firebase-project", GOSMART_FIREBASE_PROJECT_ID,
      "--uid", "User_123", "--enable"],
    ["--quota-project", GOSMART_FIREBASE_PROJECT_ID,
      "--uid", "User_123", "--enable"],
    [...base, "--project-id", GOSMART_FIREBASE_PROJECT_ID, "--enable"],
    [...base, "--unknown", "--enable"],
    [...base, "--enable", "--disable"],
    [...base],
    ["--project-id", GOSMART_FIREBASE_PROJECT_ID, "--enable"],
    ["--project-id", GOSMART_FIREBASE_PROJECT_ID, "--uid", "", "--enable"],
  ]) {
    it(`rejects invalid command: ${args.join(" ")}`, () => {
      assert.throws(() => parseAdminClaimCommand(args));
    });
  }

  it("trims the accepted project ID", () => {
    assert.equal(validateFirebaseProjectId("  gosmart-fd8f6  "),
      GOSMART_FIREBASE_PROJECT_ID);
  });
});

describe("admin claim behavior", () => {
  it("enables only gosmartAdmin and preserves other claims", () => {
    assert.deepEqual(buildUpdatedCustomClaims({role: "driver"}, true),
      {role: "driver", gosmartAdmin: true});
  });

  it("disables only gosmartAdmin and preserves other claims", () => {
    assert.deepEqual(buildUpdatedCustomClaims(
      {role: "driver", gosmartAdmin: true}, false), {role: "driver"});
  });

  it("masks the UID without profile data", () => {
    const result = maskUidForConsole("User_123");
    assert.equal(result, "Use***123");
    assert.equal("email" in buildUpdatedCustomClaims(undefined, true), false);
    assert.equal("phone" in buildUpdatedCustomClaims(undefined, true), false);
  });
});
