import assert from "node:assert/strict";
import test from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  isActivePass,
  validateProfileStatus,
  validateRouteValidity,
} from "./driver-access-helpers.js";

const reasonOf = (operation: () => unknown): string | undefined => {
  try {
    operation();
    return undefined;
  } catch (error: unknown) {
    assert.ok(error instanceof HttpsError);
    return (error.details as {reason?: string} | undefined)?.reason;
  }
};

test("approved profile is accepted", () => {
  assert.doesNotThrow(() => validateProfileStatus("approved"));
});
test("pending profile has safe reason", () => {
  assert.equal(
    reasonOf(() => validateProfileStatus("pendingReview")),
    "driver_approval_required",
  );
});
test("suspended profile has safe reason", () => {
  assert.equal(
    reasonOf(() => validateProfileStatus("suspended")),
    "driver_suspended",
  );
});
test("active pass is accepted in its half-open interval", () => {
  const now = Timestamp.fromMillis(2_000);
  assert.equal(isActivePass({
    status: "active",
    activatedAt: Timestamp.fromMillis(1_000),
    expiresAt: Timestamp.fromMillis(3_000),
  }, now), true);
});
test("pass is rejected exactly at expiresAt", () => {
  const expiresAt = Timestamp.fromMillis(3_000);
  assert.equal(isActivePass({
    status: "active",
    activatedAt: Timestamp.fromMillis(1_000),
    expiresAt,
  }, expiresAt), false);
});
test("future activation is rejected", () => {
  assert.equal(isActivePass({
    status: "active",
    activatedAt: Timestamp.fromMillis(3_000),
    expiresAt: Timestamp.fromMillis(4_000),
  }, Timestamp.fromMillis(2_000)), false);
});
test("invalid timestamp is rejected", () => {
  assert.equal(isActivePass({
    status: "active", activatedAt: 1_000,
    expiresAt: Timestamp.fromMillis(4_000),
  }, Timestamp.fromMillis(2_000)), false);
});
test("validForSeconds accepts exact lower bound", () => {
  assert.equal(validateRouteValidity(900), 900);
});
test("validForSeconds accepts exact upper bound", () => {
  assert.equal(validateRouteValidity(14_400), 14_400);
});
test("validForSeconds rejects below lower bound", () => {
  assert.equal(
    reasonOf(() => validateRouteValidity(899)),
    "invalid_route_validity",
  );
});
test("validForSeconds rejects above upper bound", () => {
  assert.equal(
    reasonOf(() => validateRouteValidity(14_401)),
    "invalid_route_validity",
  );
});
