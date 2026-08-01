import {Timestamp} from "firebase-admin/firestore";
/* eslint-disable max-len */
import {HttpsError} from "firebase-functions/v2/https";
import {DocumentType, REQUIRED_DOCUMENT_TYPES} from "./driver-application-helpers.js";

const DOCUMENT_REASONS = ["unreadable_document", "incomplete_document",
  "expired_document", "information_mismatch", "wrong_document",
  "unsupported_document"] as const;
const APPLICATION_REASONS = ["personal_information_invalid",
  "vehicle_information_invalid", "document_information_mismatch",
  "eligibility_requirements_not_met", "duplicate_application",
  "application_information_incomplete"] as const;
type DocumentDecision = "approve" | "requireReupload";
type ApplicationDecision = "approve" | "reject";

export type DocumentReviewInput = {applicationId: string;
  submissionVersion: number; documentSetId: string; documentType: DocumentType;
  decision: DocumentDecision; reasonCode: string | null};
export type ApplicationReviewInput = {applicationId: string;
  submissionVersion: number; documentSetId: string;
  decision: ApplicationDecision; rejectionReasonCode: string | null};

const invalid = (reason: string) => new HttpsError("invalid-argument",
  "İnceleme bilgileri uygun değildir.", {reason});
const exact = (value: unknown, keys: readonly string[]) => {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw invalid("invalid_review_payload");
  }
  const result = value as Record<string, unknown>;
  if (Object.keys(result).some((key) => !keys.includes(key))) {
    throw invalid("invalid_review_payload");
  }
  return result;
};
const text = (value: unknown, reason: string) => {
  if (typeof value !== "string" || value.trim().length === 0 ||
      value.trim().length > 128 || !/^[A-Za-z0-9_-]+$/u.test(value.trim())) {
    throw invalid(reason);
  }
  return value.trim();
};
const version = (value: unknown) => {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1) {
    throw invalid("invalid_submission_version");
  }
  return value;
};

export const validateDocumentReviewPayload = (value: unknown): DocumentReviewInput => {
  const input = exact(value, ["applicationId", "submissionVersion",
    "documentSetId", "documentType", "decision", "reasonCode"]);
  const documentType = input.documentType;
  if (!REQUIRED_DOCUMENT_TYPES.includes(documentType as DocumentType)) {
    throw invalid("invalid_document_type");
  }
  if (input.decision !== "approve" && input.decision !== "requireReupload") {
    throw invalid("invalid_document_review_decision");
  }
  const reason = input.reasonCode;
  if ((input.decision === "approve" && reason !== undefined && reason !== null) ||
      (input.decision === "requireReupload" &&
       !DOCUMENT_REASONS.includes(reason as typeof DOCUMENT_REASONS[number]))) {
    throw invalid("invalid_document_rejection_reason");
  }
  return {applicationId: text(input.applicationId, "invalid_application_id"),
    submissionVersion: version(input.submissionVersion),
    documentSetId: text(input.documentSetId, "invalid_document_set_id"),
    documentType: documentType as DocumentType,
    decision: input.decision, reasonCode: typeof reason === "string" ? reason : null};
};

export const validateApplicationReviewPayload = (value: unknown): ApplicationReviewInput => {
  const input = exact(value, ["applicationId", "submissionVersion",
    "documentSetId", "decision", "rejectionReasonCode"]);
  if (input.decision !== "approve" && input.decision !== "reject") {
    throw invalid("invalid_application_review_decision");
  }
  const reason = input.rejectionReasonCode;
  if ((input.decision === "approve" && reason !== undefined && reason !== null) ||
      (input.decision === "reject" &&
       !APPLICATION_REASONS.includes(reason as typeof APPLICATION_REASONS[number]))) {
    throw invalid("invalid_application_rejection_reason");
  }
  return {applicationId: text(input.applicationId, "invalid_application_id"),
    submissionVersion: version(input.submissionVersion),
    documentSetId: text(input.documentSetId, "invalid_document_set_id"),
    decision: input.decision, rejectionReasonCode: typeof reason === "string" ? reason : null};
};

export const validateCurrentApplicationVersion = (data: Record<string, unknown>,
  submissionVersion: number, documentSetId: string): void => {
  if (data.submissionVersion !== submissionVersion || data.documentSetId !== documentSetId) {
    throw new HttpsError("failed-precondition", "Başvuru sürümü güncel değildir.",
      {reason: "stale_driver_application_review"});
  }
};

export const validateCurrentDocumentMetadata = (data: Record<string, unknown>,
  input: Pick<DocumentReviewInput, "applicationId" | "submissionVersion" |
  "documentSetId" | "documentType">): void => {
  if (data.submissionVersion !== input.submissionVersion ||
      data.documentSetId !== input.documentSetId) {
    throw new HttpsError("failed-precondition", "Başvuru sürümü güncel değildir.",
      {reason: "stale_driver_application_review"});
  }
  const canonical = `driverApplicationSubmissions/${input.applicationId}/${input.documentSetId}/${input.documentType}`;
  if (data.documentType !== input.documentType || data.storagePath !== canonical ||
      !["pendingReview", "approved", "reuploadRequired"].includes(data.reviewStatus as string)) {
    throw new HttpsError("internal", "Belge bilgileri doğrulanamadı.",
      {reason: "driver_application_document_data_invalid"});
  }
};

export const determineDocumentReviewTransition = (status: unknown,
  decision: DocumentDecision): {status: "approved" | "reuploadRequired"; idempotent: boolean} => {
  const target = decision === "approve" ? "approved" : "reuploadRequired";
  if (status === target) return {status: target, idempotent: true};
  if (status !== "pendingReview") {
    throw new HttpsError("failed-precondition", "Belge daha önce incelenmiştir.",
      {reason: "driver_application_document_already_reviewed"});
  }
  return {status: target, idempotent: false};
};

export const hasAllRequiredApprovedDocuments = (
  documents: readonly Record<string, unknown>[], applicationId: string,
  submissionVersion: number, documentSetId: string): boolean =>
  documents.length === REQUIRED_DOCUMENT_TYPES.length &&
  REQUIRED_DOCUMENT_TYPES.every((type) => documents.some((data) =>
    data.documentType === type && data.reviewStatus === "approved" &&
    data.submissionVersion === submissionVersion && data.documentSetId === documentSetId &&
    data.storagePath === `driverApplicationSubmissions/${applicationId}/${documentSetId}/${type}`));

export const buildReviewAuditEvent = (input: {applicationId: string;
  reviewerAuthUserId: string; eventType: string; documentType?: string | null;
  reasonCode?: string | null; submissionVersion: number; documentSetId: string;
  now: Timestamp}) => ({applicationId: input.applicationId,
  reviewerAuthUserId: input.reviewerAuthUserId, eventType: input.eventType,
  documentType: input.documentType ?? null, reasonCode: input.reasonCode ?? null,
  submissionVersion: input.submissionVersion, documentSetId: input.documentSetId,
  createdAt: input.now});
