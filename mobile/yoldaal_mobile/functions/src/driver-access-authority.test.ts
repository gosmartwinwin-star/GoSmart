import assert from "node:assert/strict";
import test from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {
  driverAccessModeFromData,
  hasDriverAccess,
} from "./driver-access-authority.js";

test("launchFree is enabled only by explicit config", () => {
  assert.equal(
    driverAccessModeFromData({mode: "launchFree"}),
    "launchFree",
  );
});

test("paid config keeps paid semantics", () => {
  assert.equal(
    driverAccessModeFromData({mode: "paid"}),
    "paid",
  );
});

test("missing config fails closed to paid", () => {
  assert.equal(
    driverAccessModeFromData(undefined),
    "paid",
  );
});

test("malformed config fails closed to paid", () => {
  assert.equal(driverAccessModeFromData(null), "paid");
  assert.equal(driverAccessModeFromData({}), "paid");
  assert.equal(
    driverAccessModeFromData({mode: "other"}),
    "paid",
  );
});

test("launchFree allows access without a pass", () => {
  assert.equal(
    hasDriverAccess(
      "launchFree",
      null,
      Timestamp.fromMillis(2_000),
    ),
    true,
  );
});

test("paid requires an active pass", () => {
  const now = Timestamp.fromMillis(2_000);

  assert.equal(
    hasDriverAccess(
      "paid",
      {
        status: "active",
        activatedAt: Timestamp.fromMillis(1_000),
        expiresAt: Timestamp.fromMillis(3_000),
      },
      now,
    ),
    true,
  );

  assert.equal(
    hasDriverAccess(
      "paid",
      null,
      now,
    ),
    false,
  );
});

test("paid rejects a pass exactly at expiry", () => {
  const expiresAt = Timestamp.fromMillis(3_000);

  assert.equal(
    hasDriverAccess(
      "paid",
      {
        status: "active",
        activatedAt: Timestamp.fromMillis(1_000),
        expiresAt,
      },
      expiresAt,
    ),
    false,
  );
});
