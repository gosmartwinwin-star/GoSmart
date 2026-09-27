import assert from "node:assert/strict";
import test from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {
  buildRideSupportAdminEvent,
  determineRideSupportAdminTransition,
  parseRideSupportAdminTransitionInput,
} from "./ride-support-admin-transition.js";
import {
  serializeRideSupportCaseForAdmin,
} from "./ride-support-admin-read.js";

const reason = (callback: () => unknown): string | undefined => {
  try {
    callback();
  } catch (error: unknown) {
    if (typeof error === "object" && error !== null && "details" in error) {
      return (error as {details?: {reason?: string}}).details?.reason;
    }
  }
  return undefined;
};

test("support admin transition payload is exact and bounded", () => {
  assert.deepEqual(
    parseRideSupportAdminTransitionInput({
      rideId: "ride-1",
      caseId: "case-1",
      targetStatus: "inReview",
      expectedUpdatedAtMillis: 123,
      requestId: "request_1",
    }),
    {
      rideId: "ride-1",
      caseId: "case-1",
      targetStatus: "inReview",
      expectedUpdatedAtMillis: 123,
      requestId: "request_1",
    },
  );

  for (const bad of [
    null,
    {
      rideId: "ride-1",
      caseId: "case-1",
      targetStatus: "new",
      expectedUpdatedAtMillis: 123,
      requestId: "request_1",
    },
    {
      rideId: "ride/1",
      caseId: "case-1",
      targetStatus: "resolved",
      expectedUpdatedAtMillis: 123,
      requestId: "request_1",
    },
    {
      rideId: "ride-1",
      caseId: "case-1",
      targetStatus: "resolved",
      expectedUpdatedAtMillis: -1,
      requestId: "request_1",
    },
    {
      rideId: "ride-1",
      caseId: "case-1",
      targetStatus: "resolved",
      expectedUpdatedAtMillis: 123,
      requestId: "bad request",
    },
    {
      rideId: "ride-1",
      caseId: "case-1",
      targetStatus: "resolved",
      expectedUpdatedAtMillis: 123,
      requestId: "request_1",
      extra: true,
    },
  ]) {
    assert.equal(
      reason(() => parseRideSupportAdminTransitionInput(bad)),
      "invalid_ride_support_admin_transition_payload",
    );
  }
});

test("support admin transition state machine is forward only", () => {
  assert.deepEqual(
    determineRideSupportAdminTransition("new", "inReview"),
    {fromStatus: "new", toStatus: "inReview"},
  );
  assert.deepEqual(
    determineRideSupportAdminTransition("inReview", "resolved"),
    {fromStatus: "inReview", toStatus: "resolved"},
  );
  assert.equal(
    reason(() => determineRideSupportAdminTransition("new", "resolved")),
    "invalid_ride_support_case_transition",
  );
  assert.equal(
    reason(() => determineRideSupportAdminTransition("resolved", "resolved")),
    "invalid_ride_support_case_transition",
  );
});

test("support admin audit event is bounded and backend-derived", () => {
  const input = parseRideSupportAdminTransitionInput({
    rideId: "ride-1",
    caseId: "case-1",
    targetStatus: "inReview",
    expectedUpdatedAtMillis: 123,
    requestId: "request_1",
  });
  const actedAt = Timestamp.fromMillis(456);
  assert.deepEqual(
    buildRideSupportAdminEvent(input, "new", "admin-uid", actedAt),
    {
      eventType: "statusTransition",
      requestId: "request_1",
      expectedUpdatedAtMillis: 123,
      fromStatus: "new",
      toStatus: "inReview",
      adminUid: "admin-uid",
      actedAt,
    },
  );
});

test("support admin list serializer accepts only Phase3 statuses", () => {
  const base = {
    reporterRole: "passenger",
    reporterId: "passenger-1",
    counterpartyId: "driver-1",
    category: "lost-item",
    reporterNote: null,
    createdAt: Timestamp.fromMillis(1),
    updatedAt: Timestamp.fromMillis(2),
  };
  for (const status of ["new", "inReview", "resolved"]) {
    assert.equal(
      serializeRideSupportCaseForAdmin(
        "rides/ride-1/supportCases/case-1",
        {...base, status},
      ).status,
      status,
    );
  }
  assert.throws(() =>
    serializeRideSupportCaseForAdmin(
      "rides/ride-1/supportCases/case-1",
      {...base, status: "closed"},
    ),
  );
});
