import assert from "node:assert/strict";
import test from "node:test";
import {
  isAccountDeletionExecutionLeaseActive,
  isBlockingAccountDeletionRideStatus,
  validateAccountDeletionExecutionPayload,
} from "./account-deletion-execution-authority.js";

const reason = (callback: () => unknown): string | null => {
  try {
    callback();
    return null;
  } catch (error) {
    const details =
      typeof error === "object" && error !== null &&
      "details" in error ?
        (error as {details?: unknown}).details :
        null;
    if (typeof details === "object" && details !== null &&
        "reason" in details) {
      return String((details as {reason?: unknown}).reason);
    }
    return null;
  }
};

test("execution payload is exact empty object", () => {
  assert.doesNotThrow(() => validateAccountDeletionExecutionPayload({}));
  for (const value of [null, undefined, [], {uid: "x"}, {requestId: "x"}]) {
    assert.equal(
      reason(() => validateAccountDeletionExecutionPayload(value)),
      "invalid_account_deletion_execution_payload",
    );
  }
});

test("execution lease is active only strictly before expiry", () => {
  assert.equal(
    isAccountDeletionExecutionLeaseActive(1300, 1000),
    true,
  );
  assert.equal(
    isAccountDeletionExecutionLeaseActive(1000, 1000),
    false,
  );
  assert.equal(
    isAccountDeletionExecutionLeaseActive(999, 1000),
    false,
  );
  assert.equal(
    isAccountDeletionExecutionLeaseActive(null, 1000),
    false,
  );
});

test("active ride guard uses frozen lifecycle states", () => {
  for (const status of [
    "matching",
    "driverEnRoute",
    "driverArrived",
    "inProgress",
  ]) {
    assert.equal(isBlockingAccountDeletionRideStatus(status), true);
  }
  for (const status of [
    "completed",
    "cancelled",
    "expired",
    null,
    "",
  ]) {
    assert.equal(isBlockingAccountDeletionRideStatus(status), false);
  }
});
