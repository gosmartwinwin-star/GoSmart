import assert from "node:assert/strict";
/* eslint-disable max-len */
import test from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {requireGoSmartAdmin} from "./admin-authorization-helpers.js";
import {
  buildReviewAuditEvent,
  determineDocumentReviewTransition,
  hasAllRequiredApprovedDocuments,
  validateApplicationReviewPayload,
  validateCurrentApplicationVersion,
  validateCurrentDocumentMetadata,
  validateDocumentReviewPayload,
} from "./driver-application-review-helpers.js";
import {REQUIRED_DOCUMENT_TYPES} from "./driver-application-helpers.js";

const reason = (operation: () => unknown, expected: string) => {
  assert.throws(operation, (error: unknown) => error instanceof HttpsError &&
    (error.details as {reason?: string}).reason === expected);
};

test("admin claim yalnız gerçek boolean true kabul eder", () => {
  reason(() => requireGoSmartAdmin(null), "authentication_required");
  assert.equal(requireGoSmartAdmin({uid: "admin", token: {gosmartAdmin: true}}), "admin");
  for (const token of [{gosmartAdmin: false}, {gosmartAdmin: "true"},
    {isAdmin: true}, {role: "admin"}]) {
    reason(() => requireGoSmartAdmin({uid: "user", token}), "admin_access_required");
  }
});

test("geçerli belge inceleme payloadları kabul edilir", () => {
  assert.equal(validateDocumentReviewPayload({applicationId: "user-a",
    submissionVersion: 1, documentSetId: "set-a",
    documentType: "driverLicenseFront", decision: "approve"}).reasonCode, null);
  assert.equal(validateDocumentReviewPayload({applicationId: "user-a",
    submissionVersion: 1, documentSetId: "set-a",
    documentType: "criminalRecord", decision: "requireReupload",
    reasonCode: "unreadable_document"}).reasonCode, "unreadable_document");
});

test("belge payload fazlalık, tip, sürüm, karar ve reason doğrular", () => {
  const base = {applicationId: "user-a", submissionVersion: 1,
    documentSetId: "set-a", documentType: "criminalRecord", decision: "approve"};
  reason(() => validateDocumentReviewPayload({...base, admin: true}), "invalid_review_payload");
  reason(() => validateDocumentReviewPayload({...base, submissionVersion: 1.2}), "invalid_submission_version");
  reason(() => validateDocumentReviewPayload({...base, documentType: "other"}), "invalid_document_type");
  reason(() => validateDocumentReviewPayload({...base, decision: "reject"}), "invalid_document_review_decision");
  reason(() => validateDocumentReviewPayload({...base, reasonCode: "free text"}), "invalid_document_rejection_reason");
});

test("belge karar geçişleri idempotent ve çakışmaya kapalıdır", () => {
  assert.deepEqual(determineDocumentReviewTransition("pendingReview", "approve"),
    {status: "approved", idempotent: false});
  assert.deepEqual(determineDocumentReviewTransition("approved", "approve"),
    {status: "approved", idempotent: true});
  reason(() => determineDocumentReviewTransition("approved", "requireReupload"),
    "driver_application_document_already_reviewed");
});

test("stale application ve metadata reddedilir", () => {
  reason(() => validateCurrentApplicationVersion({submissionVersion: 2,
    documentSetId: "set-b"}, 1, "set-a"), "stale_driver_application_review");
  reason(() => validateCurrentDocumentMetadata({submissionVersion: 2,
    documentSetId: "set-a"}, {applicationId: "user-a", submissionVersion: 1,
    documentSetId: "set-a", documentType: "criminalRecord"}),
  "stale_driver_application_review");
});

test("application payload karar ve kontrollü ret nedeni doğrular", () => {
  assert.equal(validateApplicationReviewPayload({applicationId: "user-a",
    submissionVersion: 1, documentSetId: "set-a", decision: "approve"}).decision,
  "approve");
  assert.equal(validateApplicationReviewPayload({applicationId: "user-a",
    submissionVersion: 1, documentSetId: "set-a", decision: "reject",
    rejectionReasonCode: "vehicle_information_invalid"}).decision, "reject");
  reason(() => validateApplicationReviewPayload({applicationId: "user-a",
    submissionVersion: 1, documentSetId: "set-a", decision: "reject"}),
  "invalid_application_rejection_reason");
});

test("yalnız tam ve canonical yedi approved belge seti kabul edilir", () => {
  const documents = REQUIRED_DOCUMENT_TYPES.map((type) => ({documentType: type,
    reviewStatus: "approved", submissionVersion: 1, documentSetId: "set-a",
    storagePath: `driverApplicationSubmissions/user-a/set-a/${type}`}));
  assert.equal(hasAllRequiredApprovedDocuments(documents, "user-a", 1, "set-a"), true);
  assert.equal(hasAllRequiredApprovedDocuments(documents.slice(1), "user-a", 1, "set-a"), false);
  assert.equal(hasAllRequiredApprovedDocuments(documents.map((item, index) =>
    index === 0 ? {...item, reviewStatus: "pendingReview"} : item),
  "user-a", 1, "set-a"), false);
});

test("audit event yalnız kontrollü alanları ve backend zamanını taşır", () => {
  const now = Timestamp.fromMillis(1234);
  const event = buildReviewAuditEvent({applicationId: "user-a",
    reviewerAuthUserId: "admin", eventType: "applicationApproved",
    submissionVersion: 1, documentSetId: "set-a", now});
  assert.equal(event.createdAt, now);
  assert.deepEqual(Object.keys(event).sort(), ["applicationId", "createdAt",
    "documentSetId", "documentType", "eventType", "reasonCode",
    "reviewerAuthUserId", "submissionVersion"].sort());
});
