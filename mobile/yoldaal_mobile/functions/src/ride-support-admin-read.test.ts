import assert from "node:assert/strict";
import test from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {
  parseRideSupportAdminListInput,
  serializeRideSupportCaseForAdmin,
} from "./ride-support-admin-read.js";

test("support admin list payload defaults and validates bounded cursor", () => {
  assert.deepEqual(parseRideSupportAdminListInput(undefined), {
    pageSize: 20,
    cursor: null,
  });
  assert.deepEqual(
    parseRideSupportAdminListInput({
      pageSize: 25,
      cursor: {
        createdAtMillis: 123,
        rideId: "ride-a",
        caseId: "case-a",
      },
    }),
    {
      pageSize: 25,
      cursor: {
        createdAtMillis: 123,
        rideId: "ride-a",
        caseId: "case-a",
      },
    },
  );

  for (const bad of [
    {pageSize: 0},
    {pageSize: 51},
    {extra: true},
    {cursor: {createdAtMillis: 1, rideId: "a/b", caseId: "c"}},
  ]) {
    assert.throws(
      () => parseRideSupportAdminListInput(bad),
      (error: unknown) =>
        typeof error === "object" &&
        error !== null &&
        "details" in error &&
        (error as {details?: {reason?: string}}).details?.reason ===
          "invalid_ride_support_admin_list_payload",
    );
  }
});

test("support admin serializer derives ride and case IDs from path", () => {
  const createdAt = Timestamp.fromMillis(1000);
  const updatedAt = Timestamp.fromMillis(2000);
  assert.deepEqual(
    serializeRideSupportCaseForAdmin(
      "rides/ride-1/supportCases/case-1",
      {
        reporterRole: "passenger",
        reporterId: "passenger-1",
        counterpartyId: "driver-1",
        category: "lost-item",
        reporterNote: "Telefon",
        status: "new",
        createdAt,
        updatedAt,
      },
    ),
    {
      rideId: "ride-1",
      caseId: "case-1",
      reporterRole: "passenger",
      reporterId: "passenger-1",
      counterpartyId: "driver-1",
      category: "lost-item",
      reporterNote: "Telefon",
      status: "new",
      createdAtMillis: 1000,
      updatedAtMillis: 2000,
    },
  );
});

test("support admin serializer fails closed on unknown category/status", () => {
  const base = {
    reporterRole: "driver",
    reporterId: "driver-1",
    counterpartyId: "passenger-1",
    reporterNote: null,
    createdAt: Timestamp.fromMillis(1),
    updatedAt: Timestamp.fromMillis(1),
  };

  assert.throws(() =>
    serializeRideSupportCaseForAdmin(
      "rides/r/supportCases/c",
      {...base, category: "unknown", status: "new"},
    ),
  );
  assert.throws(() =>
    serializeRideSupportCaseForAdmin(
      "rides/r/supportCases/c",
      {...base, category: "safety", status: "closed"},
    ),
  );
});
