import assert from "node:assert/strict";
/* eslint-disable max-len */
import {readFileSync} from "node:fs";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {REQUIRED_DOCUMENT_TYPES} from "./driver-application-helpers.js";
import {
  buildPublicDriverApplicationStatus,
  operationDocumentId,
  publicReviewState,
  requestDigest,
  validateCurrentDocuments,
  validateResubmissionEligibility,
  validateResubmissionPayload,
} from "./driver-application-resubmission-helpers.js";

const reason = (callback: () => unknown) => {
  try {
    callback();
    return null;
  } catch (error) {
    return (error as HttpsError).details &&
      ((error as HttpsError).details as {reason?: string}).reason;
  }
};
const application = (extra: Record<string, unknown> = {}) => ({
  status: "rejected", rejectionReasonCode: "document_reupload_required",
  submissionVersion: 2, documentSetId: "set-a", ...extra,
});
const documents = (status = "pendingReview") =>
  REQUIRED_DOCUMENT_TYPES.map((documentType, index) => ({documentType,
    reviewStatus: index === 0 ? status : "pendingReview",
    rejectionReasonCode: index === 0 && status === "reuploadRequired" ?
      "unreadable_document" : null,
    storagePath: `driverApplicationSubmissions/user-a/set-a/${documentType}`,
    storageGeneration: `${index + 1}`, contentType: "image/jpeg",
    sizeBytes: 100, uploadedAt: {}, reviewedAt: null,
    documentSetId: "set-a", submissionVersion: 2}));

test("resubmission payload is exact and validated", () => {
  assert.deepEqual(validateResubmissionPayload({expectedSubmissionVersion: 2,
    requestId: "request_123456789"}),
  {expectedSubmissionVersion: 2, requestId: "request_123456789"});
  assert.equal(reason(() => validateResubmissionPayload({
    expectedSubmissionVersion: 2, requestId: "request_123456789", uid: "x"})),
  "invalid_resubmission_payload");
  assert.equal(reason(() => validateResubmissionPayload({
    expectedSubmissionVersion: 0, requestId: "request_123456789"})),
  "invalid_submission_version");
  assert.equal(reason(() => validateResubmissionPayload({
    expectedSubmissionVersion: 2, requestId: "short"})), "invalid_request_id");
});

test("operation identifiers are deterministic hashes", () => {
  assert.match(operationDocumentId("user-a"), /^[a-f0-9]{64}$/u);
  assert.match(requestDigest("request_123456789"), /^[a-f0-9]{64}$/u);
  assert.notEqual(operationDocumentId("user-a"), operationDocumentId("user-b"));
});

test("public application states have exactly five semantics", () => {
  assert.equal(publicReviewState(application({status: "pendingReview"})),
    "pendingReview");
  assert.equal(publicReviewState(application({status: "approved"})), "approved");
  assert.equal(publicReviewState(application({status: "withdrawn"})), "withdrawn");
  assert.equal(publicReviewState(application()), "awaitingDocumentResubmission");
  assert.equal(publicReviewState(application({rejectionReasonCode:
    "duplicate_application"})), "rejected");
  assert.equal(reason(() => publicReviewState(application({
    rejectionReasonCode: "unknown"}))), "driver_application_data_invalid");
});

test("current documents require canonical seven-record context", () => {
  const values = validateCurrentDocuments("user-a", application(),
    documents("reuploadRequired"));
  assert.deepEqual(values.map((item) => item.documentType),
    [...REQUIRED_DOCUMENT_TYPES]);
  assert.equal(values[0].reuploadReasonCode, "unreadable_document");
  const invalid = documents();
  invalid[0].storagePath = "unexpected";
  assert.equal(reason(() => validateCurrentDocuments("user-a", application(),
    invalid)), "driver_application_document_data_invalid");
});

test("unknown reupload reason is data-invalid", () => {
  const invalid = documents("reuploadRequired");
  invalid[0].rejectionReasonCode = "free_text";
  assert.equal(reason(() => validateCurrentDocuments("user-a", application(),
    invalid)), "driver_application_document_data_invalid");
});

test("public response contains only minimum safe fields", () => {
  const value = buildPublicDriverApplicationStatus(application(),
    validateCurrentDocuments("user-a", application(),
      documents("reuploadRequired")));
  assert.deepEqual(Object.keys(value).sort(),
    ["documents", "reviewState", "submissionVersion"]);
  const serialized = JSON.stringify(value);
  for (const forbidden of ["storagePath", "storageGeneration", "documentSetId",
    "applicationId", "uid", "fullName", "vehiclePlate"]) {
    assert.equal(serialized.includes(forbidden), false);
  }
});

test("final rejection exposes only controlled application reason", () => {
  const app = application({rejectionReasonCode: "duplicate_application"});
  const value = buildPublicDriverApplicationStatus(app,
    validateCurrentDocuments("user-a", app, documents()));
  assert.equal(value.applicationReasonCode, "duplicate_application");
});

test("resubmission eligibility requires marker, version and required doc", () => {
  const current = validateCurrentDocuments("user-a", application(),
    documents("reuploadRequired"));
  assert.equal(validateResubmissionEligibility(application(), current, 2), 3);
  assert.equal(reason(() => validateResubmissionEligibility(application(),
    current, 1)), "stale_driver_application_submission");
  assert.equal(reason(() => validateResubmissionEligibility(application({
    status: "approved"}), current, 2)),
  "driver_application_not_awaiting_resubmission");
  const none = validateCurrentDocuments("user-a", application(), documents());
  assert.equal(reason(() => validateResubmissionEligibility(application(),
    none, 2)), "driver_application_no_documents_to_reupload");
});

test("driver callables keep auth, minimal input and read-only status semantics", () => {
  const source = readFileSync("src/index.ts", "utf8");
  const readStart = source.indexOf("export const getMyDriverApplicationStatus");
  const resubmitStart = source.indexOf("export const resubmitDriverApplicationDocuments");
  const readCallable = source.slice(readStart, resubmitStart);
  assert.match(readCallable, /if \(!request\.auth\)/u);
  assert.match(readCallable, /request\.auth\.uid/u);
  assert.doesNotMatch(readCallable, /applicationViewed|ReviewEvents/u);
  assert.doesNotMatch(readCallable, /request\.data\.(uid|applicationId|documentSetId)/u);
});

test("resubmission source pins generations and cleans only consumed staging", () => {
  const source = readFileSync("src/index.ts", "utf8");
  const start = source.indexOf("export const resubmitDriverApplicationDocuments");
  const end = source.indexOf("export const submitDriverApplication", start);
  const callable = source.slice(start, end);
  assert.match(callable, /file\(sourcePath, \{generation: sourceGeneration\}\)/u);
  assert.match(callable, /ifGenerationMatch: 0/u);
  assert.match(callable, /ifGenerationMatch: item\.generation/u);
  assert.match(callable, /document\.reviewStatus === "reuploadRequired"/u);
  assert.match(callable, /Promise\.allSettled\(destinationPaths/u);
});

test("resubmission is transactionally idempotent and emits one safe event", () => {
  const source = readFileSync("src/index.ts", "utf8");
  const start = source.indexOf("export const resubmitDriverApplicationDocuments");
  const end = source.indexOf("export const submitDriverApplication", start);
  const callable = source.slice(start, end);
  assert.match(callable, /driverApplicationResubmissionOperations/u);
  assert.match(callable, /operationData\.status === "completed"/u);
  assert.match(callable, /operationData\.status === "processing"/u);
  assert.match(callable, /transaction\.update\(operationRef, \{status: "completed"/u);
  assert.match(callable, /eventType: "applicationResubmitted"/u);
  assert.doesNotMatch(callable, /logger\.(info|warn|error).*request/u);
});
