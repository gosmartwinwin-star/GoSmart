/* eslint-disable max-len */
import assert from "node:assert/strict";
import test from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {buildUpdatedCustomClaims, maskUidForConsole, parseAdminClaimCommand} from "./admin-claim-management-helpers.js";
import {buildNextCursor, buildReviewContext, calculateReviewUrlExpiry, mapApplicationReviewDetails,
  mapApplicationSummary, validateApplicationDetailsPayload,
  validateApplicationListPayload, validateDocumentReviewUrlPayload} from
  "./driver-application-admin-read-helpers.js";
import {REQUIRED_DOCUMENT_TYPES} from "./driver-application-helpers.js";

const reason = (operation: () => unknown, expected: string) => assert.throws(operation,
  (error: unknown) => error instanceof HttpsError &&
    (error.details as {reason?: string}).reason === expected);

test("claim komutları ve dry-run parse edilir", () => {
  assert.deepEqual(parseAdminClaimCommand(["--project-id", "gosmart-fd8f6",
    "--uid", "user-123", "--enable"]),
  {projectId: "gosmart-fd8f6", uid: "user-123", action: "enable",
    dryRun: false});
  assert.deepEqual(parseAdminClaimCommand(["--disable", "--project-id",
    "gosmart-fd8f6", "--uid", "user-123", "--dry-run"]),
  {projectId: "gosmart-fd8f6", uid: "user-123", action: "disable",
    dryRun: true});
  assert.throws(() => parseAdminClaimCommand(["--enable"]));
  assert.throws(() => parseAdminClaimCommand(["--uid", "x", "--enable", "--disable"]));
  assert.throws(() => parseAdminClaimCommand(["--uid", "x", "--unknown"]));
});

test("claim güncellemesi diğer claimleri korur ve disable alanı kaldırır", () => {
  assert.deepEqual(buildUpdatedCustomClaims({tenant: "a"}, true),
    {tenant: "a", gosmartAdmin: true});
  assert.deepEqual(buildUpdatedCustomClaims({tenant: "a", gosmartAdmin: true}, false),
    {tenant: "a"});
  assert.equal(maskUidForConsole("abcdefghi"), "abc***ghi");
});

test("liste varsayılanları, status ve pageSize sınırları doğrulanır", () => {
  assert.deepEqual(validateApplicationListPayload({}),
    {status: "pendingReview", pageSize: 20, cursor: null});
  for (const status of ["pendingReview", "approved", "rejected", "withdrawn"]) {
    assert.equal(validateApplicationListPayload({status}).status, status);
  }
  assert.equal(validateApplicationListPayload({pageSize: 1}).pageSize, 1);
  assert.equal(validateApplicationListPayload({pageSize: 50}).pageSize, 50);
  for (const pageSize of [0, 51, 1.2, true]) {
    reason(() => validateApplicationListPayload({pageSize}), "invalid_page_size");
  }
  reason(() => validateApplicationListPayload({status: "other"}), "invalid_review_status");
  reason(() => validateApplicationListPayload({admin: true}), "invalid_admin_list_payload");
});

test("cursor tam ve negatif olmayan integer olmalıdır", () => {
  assert.deepEqual(validateApplicationListPayload({cursor: {
    submittedAtMillis: 123, applicationId: "user-a"}}).cursor,
  {submittedAtMillis: 123, applicationId: "user-a"});
  reason(() => validateApplicationListPayload({cursor: {applicationId: "x"}}), "invalid_page_cursor");
  reason(() => validateApplicationListPayload({cursor: {submittedAtMillis: -1,
    applicationId: "x"}}), "invalid_page_cursor");
});

test("ayrıntı ve URL payloadları exact ve stale anahtarları taşır", () => {
  const base = {applicationId: "user-a", submissionVersion: 1, documentSetId: "set-a"};
  assert.deepEqual(validateApplicationDetailsPayload({applicationId: "user-a"}),
    {applicationId: "user-a"});
  assert.equal(validateDocumentReviewUrlPayload({...base,
    documentType: "criminalRecord"}).documentType, "criminalRecord");
  for (const extra of [{submissionVersion: 1}, {documentSetId: "set-a"},
    {admin: true}, {role: "admin"}, {extra: true}]) {
    reason(() => validateApplicationDetailsPayload({applicationId: "user-a", ...extra}),
      "invalid_review_details_payload");
  }
  reason(() => validateApplicationDetailsPayload("user-a"),
    "invalid_review_details_payload");
  reason(() => validateDocumentReviewUrlPayload({...base, documentType: "other"}),
    "invalid_document_type");
});

test("summary hassas ve storage alanlarını taşımaz", () => {
  const now = Timestamp.fromMillis(1000);
  const summary = mapApplicationSummary("user-a", {status: "pendingReview",
    submittedAt: now, updatedAt: now, submissionVersion: 1,
    workType: "vehicleOwner", vehicleBrand: "Fiat", vehicleModel: "Egea",
    vehicleModelYear: 2024, registrationOwnerType: "applicant",
    fullName: "Secret", storagePath: "secret", documentSetId: "secret"});
  assert.equal(summary.applicationId, "user-a");
  assert.equal("fullName" in summary, false);
  assert.equal("storagePath" in summary, false);
  assert.equal("documentSetId" in summary, false);
  assert.deepEqual(buildNextCursor([summary], true),
    {applicationId: "user-a", submittedAtMillis: 1000});
  assert.equal(buildNextCursor([summary], false), null);
});

test("details yedi canonical belgeyi map eder ve sunucu alanlarını çıkarır", () => {
  const now = Timestamp.fromMillis(1000);
  const application = {status: "pendingReview", submittedAt: now, updatedAt: now,
    reviewedAt: null, submissionVersion: 1, documentSetId: "set-a",
    fullName: "Ali", verifiedPhoneNumber: "+90", email: null,
    driverTaxiStandName: null, driverTaxiStandAddress: null, workType: "vehicleOwner",
    vehiclePlate: "06ABC123", vehicleBrand: "Fiat", vehicleModel: "Egea",
    vehicleModelYear: 2024, registrationOwnerType: "applicant",
    hasVehicleUseAuthorization: false, vehicleTaxiStandName: null,
    informationAccuracyAccepted: true, documentValidityNotificationAccepted: true,
    documentProcessingNoticeAccepted: true, kvkkNoticeAccepted: true,
    termsAccepted: true, marketingConsent: false, rejectionReasonCode: null};
  const documents = REQUIRED_DOCUMENT_TYPES.map((type) => ({type, data: {
    documentType: type, reviewStatus: "pendingReview", reviewedAt: null,
    rejectionReasonCode: null, contentType: "image/jpeg", sizeBytes: 100,
    submissionVersion: 1, documentSetId: "set-a",
    storagePath: `driverApplicationSubmissions/user-a/set-a/${type}`,
    reviewedByAdminUid: "secret"}}));
  const reviewContext = buildReviewContext(application);
  const details = mapApplicationReviewDetails("user-a", application, documents,
    reviewContext);
  assert.deepEqual(details.reviewContext,
    {submissionVersion: 1, documentSetId: "set-a"});
  assert.deepEqual(Object.keys(details.reviewContext).sort(),
    ["documentSetId", "submissionVersion"]);
  assert.equal(details.documents.length, 7);
  assert.equal("storagePath" in details.documents[0], false);
  assert.equal("documentSetId" in details.application, false);
  assert.equal("reviewedByAdminUid" in details.documents[0], false);
});

test("reviewContext yalnız geçerli güncel application alanlarından üretilir", () => {
  assert.deepEqual(buildReviewContext({submissionVersion: 2,
    documentSetId: "set-current"}),
  {submissionVersion: 2, documentSetId: "set-current"});
  for (const data of [{submissionVersion: 0, documentSetId: "set"},
    {submissionVersion: 1.2, documentSetId: "set"},
    {submissionVersion: true, documentSetId: "set"},
    {submissionVersion: 1}, {submissionVersion: 1, documentSetId: " "}]) {
    reason(() => buildReviewContext(data), "driver_application_review_data_invalid");
  }
});

test("signed URL expiry üç dakika ve en fazla beş dakikadır", () => {
  assert.equal(calculateReviewUrlExpiry(1000), 181000);
  assert.equal(calculateReviewUrlExpiry(1000, 300000), 301000);
  assert.throws(() => calculateReviewUrlExpiry(1000, 300001));
});
