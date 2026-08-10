import {createHash} from "node:crypto";
/* eslint-disable max-len */
import {HttpsError} from "firebase-functions/v2/https";
import {DocumentType, REQUIRED_DOCUMENT_TYPES,
  buildSubmissionDocumentPath} from "./driver-application-helpers.js";
import {APPLICATION_REJECTION_REASONS, DOCUMENT_REUPLOAD_REASONS}
  from "./driver-application-review-helpers.js";

export const DOCUMENT_REUPLOAD_APPLICATION_MARKER = "document_reupload_required";
export type ResubmissionInput = {expectedSubmissionVersion: number; requestId: string};
const failure = (code: "invalid-argument" | "failed-precondition" | "internal",
  reason: string) => new HttpsError(code, "Sürücü başvurusu işlemi tamamlanamadı.", {reason});

export const validateResubmissionPayload = (value: unknown): ResubmissionInput => {
  if (typeof value !== "object" || value === null || Array.isArray(value) ||
      Object.getPrototypeOf(value) !== Object.prototype) {
    throw failure("invalid-argument", "invalid_resubmission_payload");
  }
  const input = value as Record<string, unknown>;
  const keys = Object.keys(input);
  if (keys.length !== 2 || !keys.includes("expectedSubmissionVersion") ||
      !keys.includes("requestId")) {
    throw failure("invalid-argument", "invalid_resubmission_payload");
  }
  if (typeof input.expectedSubmissionVersion !== "number" ||
      !Number.isInteger(input.expectedSubmissionVersion) || input.expectedSubmissionVersion < 1) {
    throw failure("invalid-argument", "invalid_submission_version");
  }
  if (typeof input.requestId !== "string" || input.requestId.length < 16 ||
      input.requestId.length > 128 || !/^[A-Za-z0-9_-]+$/u.test(input.requestId)) {
    throw failure("invalid-argument", "invalid_request_id");
  }
  return {expectedSubmissionVersion: input.expectedSubmissionVersion,
    requestId: input.requestId};
};

export const operationDocumentId = (uid: string): string =>
  createHash("sha256").update(`driver-resubmission:${uid}`).digest("hex");
export const requestDigest = (requestId: string): string =>
  createHash("sha256").update(`driver-resubmission-request:${requestId}`).digest("hex");

const positiveVersion = (value: unknown): number => {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1) {
    throw failure("internal", "driver_application_data_invalid");
  }
  return value;
};

export const publicReviewState = (application: Record<string, unknown>) => {
  const status = application.status;
  if (status === "pendingReview" || status === "approved" || status === "withdrawn") {
    return status;
  }
  if (status !== "rejected") throw failure("internal", "driver_application_data_invalid");
  const reason = application.rejectionReasonCode;
  if (reason === DOCUMENT_REUPLOAD_APPLICATION_MARKER) return "awaitingDocumentResubmission";
  if (APPLICATION_REJECTION_REASONS.includes(
    reason as typeof APPLICATION_REJECTION_REASONS[number])) return "rejected";
  throw failure("internal", "driver_application_data_invalid");
};

export type CurrentDocument = {documentType: DocumentType;
  reviewStatus: "pendingReview" | "approved" | "reuploadRequired";
  reuploadReasonCode?: typeof DOCUMENT_REUPLOAD_REASONS[number];
  storagePath: string; storageGeneration: string; contentType: string;
  sizeBytes: number; uploadedAt: unknown; reviewedAt: unknown};

export const validateCurrentDocuments = (uid: string,
  application: Record<string, unknown>, documents: readonly Record<string, unknown>[]): CurrentDocument[] => {
  const version = positiveVersion(application.submissionVersion);
  const setId = application.documentSetId;
  if (typeof setId !== "string" || setId.length === 0 || setId.length > 128 ||
      !/^[A-Za-z0-9_-]+$/u.test(setId) || documents.length !== REQUIRED_DOCUMENT_TYPES.length) {
    throw failure("internal", "driver_application_data_invalid");
  }
  return REQUIRED_DOCUMENT_TYPES.map((type, index) => {
    const data = documents[index];
    const status = data.reviewStatus;
    const path = buildSubmissionDocumentPath(uid, setId, type);
    if (data.documentType !== type || data.documentSetId !== setId ||
        data.submissionVersion !== version || data.storagePath !== path ||
        !["pendingReview", "approved", "reuploadRequired"].includes(status as string) ||
        typeof data.storageGeneration !== "string" || !/^[0-9]+$/u.test(data.storageGeneration) ||
        typeof data.contentType !== "string" || typeof data.sizeBytes !== "number" ||
        !Number.isInteger(data.sizeBytes) || data.sizeBytes < 1) {
      throw failure("internal", "driver_application_document_data_invalid");
    }
    const reason = data.rejectionReasonCode;
    if (status === "reuploadRequired" && !DOCUMENT_REUPLOAD_REASONS.includes(
      reason as typeof DOCUMENT_REUPLOAD_REASONS[number])) {
      throw failure("internal", "driver_application_document_data_invalid");
    }
    if (status !== "reuploadRequired" && reason !== null && reason !== undefined) {
      throw failure("internal", "driver_application_document_data_invalid");
    }
    return {documentType: type, reviewStatus: status as CurrentDocument["reviewStatus"],
      ...(status === "reuploadRequired" ?
        {reuploadReasonCode: reason as typeof DOCUMENT_REUPLOAD_REASONS[number]} : {}),
      storagePath: path, storageGeneration: data.storageGeneration,
      contentType: data.contentType, sizeBytes: data.sizeBytes,
      uploadedAt: data.uploadedAt, reviewedAt: data.reviewedAt};
  });
};

export const buildPublicDriverApplicationStatus = (application: Record<string, unknown>,
  documents: readonly CurrentDocument[]) => {
  const reviewState = publicReviewState(application);
  return {reviewState, submissionVersion: positiveVersion(application.submissionVersion),
    ...(reviewState === "rejected" ?
      {applicationReasonCode: application.rejectionReasonCode} : {}),
    documents: documents.map((document) => ({documentType: document.documentType,
      reviewStatus: document.reviewStatus,
      ...(document.reviewStatus === "reuploadRequired" ?
        {reuploadReasonCode: document.reuploadReasonCode} : {})}))};
};

export const validateResubmissionEligibility = (application: Record<string, unknown>,
  documents: readonly CurrentDocument[], expectedVersion: number): number => {
  if (application.status !== "rejected" ||
      application.rejectionReasonCode !== DOCUMENT_REUPLOAD_APPLICATION_MARKER) {
    throw failure("failed-precondition", "driver_application_not_awaiting_resubmission");
  }
  const version = positiveVersion(application.submissionVersion);
  if (version !== expectedVersion) {
    throw failure("failed-precondition", "stale_driver_application_submission");
  }
  if (!documents.some((document) => document.reviewStatus === "reuploadRequired")) {
    throw failure("failed-precondition", "driver_application_no_documents_to_reupload");
  }
  return version + 1;
};
