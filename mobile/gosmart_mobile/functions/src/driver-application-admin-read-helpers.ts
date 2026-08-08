/* eslint-disable max-len, indent */
import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {DocumentType, REQUIRED_DOCUMENT_TYPES} from "./driver-application-helpers.js";
import {validateCurrentApplicationVersion, validateCurrentDocumentMetadata} from "./driver-application-review-helpers.js";

const STATUSES = ["pendingReview", "approved", "rejected", "withdrawn"] as const;
type ReviewStatus = typeof STATUSES[number];
const REVIEW_STATES = ["pendingReview", "approved",
  "awaitingDocumentResubmission", "rejected", "withdrawn"] as const;
export type ReviewState = typeof REVIEW_STATES[number];
const APPLICATION_REJECTION_REASONS = ["personal_information_invalid",
  "vehicle_information_invalid", "document_information_mismatch",
  "eligibility_requirements_not_met", "duplicate_application",
  "application_information_incomplete"] as const;
export type PageCursor = {submittedAtMillis: number; applicationId: string};
export type ListInput = {status: ReviewStatus | null; reviewState: ReviewState;
  pageSize: number; cursor: PageCursor | null};
export type DetailsInput = {applicationId: string};
export type ReviewContext = {submissionVersion: number; documentSetId: string};
export type UrlInput = DetailsInput & ReviewContext & {documentType: DocumentType};

const invalid = (reason: string) => new HttpsError("invalid-argument",
  "Yönetici okuma isteği uygun değildir.", {reason});
const exact = (value: unknown, keys: readonly string[], reason: string) => {
  if (value === undefined && keys.includes("status")) return {} as Record<string, unknown>;
  if (typeof value !== "object" || value === null || Array.isArray(value)) throw invalid(reason);
  const record = value as Record<string, unknown>;
  if (Object.keys(record).some((key) => !keys.includes(key))) throw invalid(reason);
  return record;
};
const identifier = (value: unknown, reason: string) => {
  if (typeof value !== "string" || value.trim().length === 0 || value.trim().length > 128 ||
      !/^[A-Za-z0-9_-]+$/u.test(value.trim())) throw invalid(reason);
  return value.trim();
};
const positiveVersion = (value: unknown) => {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1) {
    throw invalid("invalid_submission_version");
  }
  return value;
};

export const validateApplicationListPayload = (value: unknown): ListInput => {
  const input = exact(value, ["status", "reviewState", "pageSize", "cursor"], "invalid_admin_list_payload");
  if (input.status !== undefined && input.reviewState !== undefined) {
    throw invalid("invalid_admin_list_payload");
  }
  const status = input.status;
  if (status !== undefined && !STATUSES.includes(status as ReviewStatus)) {
    throw invalid("invalid_review_status");
  }
  const reviewState = input.reviewState ?? status ?? "pendingReview";
  if (!REVIEW_STATES.includes(reviewState as ReviewState)) {
    throw invalid("invalid_review_state");
  }
  const pageSize = input.pageSize ?? 20;
  if (typeof pageSize !== "number" || !Number.isInteger(pageSize) || pageSize < 1 || pageSize > 50) {
    throw invalid("invalid_page_size");
  }
  let cursor: PageCursor | null = null;
  if (input.cursor !== undefined && input.cursor !== null) {
    const raw = exact(input.cursor, ["submittedAtMillis", "applicationId"], "invalid_page_cursor");
    if (Object.keys(raw).length !== 2 || typeof raw.submittedAtMillis !== "number" ||
        !Number.isInteger(raw.submittedAtMillis) || raw.submittedAtMillis < 0) {
      throw invalid("invalid_page_cursor");
    }
    cursor = {submittedAtMillis: raw.submittedAtMillis,
      applicationId: identifier(raw.applicationId, "invalid_page_cursor")};
  }
  return {status: status === undefined ? null : status as ReviewStatus,
    reviewState: reviewState as ReviewState, pageSize, cursor};
};

export const applicationReviewState = (
  data: Record<string, unknown>,
): ReviewState => {
  const status = data.status;
  if (status === "pendingReview" || status === "approved" ||
      status === "withdrawn") return status;
  if (status !== "rejected") {
    throw new HttpsError("internal", "Başvuru verisi doğrulanamadı.",
      {reason: "driver_application_review_data_invalid"});
  }
  if (data.rejectionReasonCode === "document_reupload_required") {
    return "awaitingDocumentResubmission";
  }
  if (APPLICATION_REJECTION_REASONS.includes(
    data.rejectionReasonCode as typeof APPLICATION_REJECTION_REASONS[number])) {
    return "rejected";
  }
  throw new HttpsError("internal", "Başvuru inceleme durumu doğrulanamadı.",
    {reason: "driver_application_review_state_invalid"});
};

export const reviewStateQuery = (reviewState: ReviewState) => {
  if (reviewState === "awaitingDocumentResubmission") {
    return {status: "rejected", rejectionReasonCodes: ["document_reupload_required"]};
  }
  if (reviewState === "rejected") {
    return {status: "rejected", rejectionReasonCodes: [...APPLICATION_REJECTION_REASONS]};
  }
  return {status: reviewState, rejectionReasonCodes: null};
};

export const validateApplicationDetailsPayload = (value: unknown): DetailsInput => {
  const input = exact(value, ["applicationId"],
    "invalid_review_details_payload");
  if (Object.keys(input).length !== 1) throw invalid("invalid_review_details_payload");
  return {applicationId: identifier(input.applicationId, "invalid_application_id")};
};

export const validateDocumentReviewUrlPayload = (value: unknown): UrlInput => {
  const input = exact(value, ["applicationId", "submissionVersion", "documentSetId", "documentType"],
    "invalid_document_review_url_payload");
  const common = validateApplicationDetailsPayload({applicationId: input.applicationId});
  if (!REQUIRED_DOCUMENT_TYPES.includes(input.documentType as DocumentType)) {
    throw invalid("invalid_document_type");
  }
  return {...common, submissionVersion: positiveVersion(input.submissionVersion),
    documentSetId: identifier(input.documentSetId, "invalid_document_set_id"),
    documentType: input.documentType as DocumentType};
};

export const buildReviewContext = (data: Record<string, unknown>): ReviewContext => {
  const submissionVersion = data.submissionVersion;
  const documentSetId = data.documentSetId;
  if (typeof submissionVersion !== "number" || !Number.isInteger(submissionVersion) ||
      submissionVersion < 1 || typeof documentSetId !== "string" ||
      documentSetId.trim().length === 0 || documentSetId.trim().length > 128 ||
      !/^[A-Za-z0-9_-]+$/u.test(documentSetId.trim())) {
    throw new HttpsError("internal", "Başvuru verisi doğrulanamadı.",
      {reason: "driver_application_review_data_invalid"});
  }
  return {submissionVersion, documentSetId: documentSetId.trim()};
};

const timestampMillis = (value: unknown, nullable = false): number | null => {
  if (nullable && value === null) return null;
  if (!(value instanceof Timestamp)) {
    throw new HttpsError("internal", "Başvuru verisi doğrulanamadı.",
      {reason: "driver_application_review_data_invalid"});
  }
  return value.toMillis();
};
const stringValue = (value: unknown, nullable = false): string | null => {
  if (nullable && value === null) return null;
  if (typeof value !== "string") {
    throw new HttpsError("internal", "Başvuru verisi doğrulanamadı.",
      {reason: "driver_application_review_data_invalid"});
  }
  return value;
};

export const mapApplicationSummary = (id: string, data: Record<string, unknown>) => ({
  applicationId: id, status: stringValue(data.status),
  reviewState: applicationReviewState(data),
  submittedAtMillis: timestampMillis(data.submittedAt) as number,
  updatedAtMillis: timestampMillis(data.updatedAt) as number,
  submissionVersion: positiveStoredInteger(data.submissionVersion), workType: stringValue(data.workType),
  vehicleBrand: stringValue(data.vehicleBrand), vehicleModel: stringValue(data.vehicleModel),
  vehicleModelYear: positiveStoredInteger(data.vehicleModelYear),
  registrationOwnerType: stringValue(data.registrationOwnerType),
});

const positiveStoredInteger = (value: unknown): number => {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1) {
    throw new HttpsError("internal", "Başvuru verisi doğrulanamadı.",
      {reason: "driver_application_review_data_invalid"});
  }
  return value;
};

export const buildNextCursor = (items: readonly {applicationId: string;
  submittedAtMillis: number}[], hasMore: boolean): PageCursor | null =>
  hasMore && items.length > 0 ? {
    applicationId: items[items.length - 1].applicationId,
    submittedAtMillis: items[items.length - 1].submittedAtMillis,
  } : null;

export const mapApplicationReviewDetails = (id: string, data: Record<string, unknown>,
  documents: readonly {type: DocumentType; data: Record<string, unknown>}[],
  reviewContext: ReviewContext) => {
  validateCurrentApplicationVersion(data, reviewContext.submissionVersion,
    reviewContext.documentSetId);
  if (documents.length !== REQUIRED_DOCUMENT_TYPES.length) {
    throw new HttpsError("internal", "Başvuru belgeleri doğrulanamadı.",
      {reason: "driver_application_review_data_invalid"});
  }
  const mappedDocuments = documents.map(({type, data: metadata}) => {
    validateCurrentDocumentMetadata(metadata, {applicationId: id,
      submissionVersion: reviewContext.submissionVersion,
      documentSetId: reviewContext.documentSetId, documentType: type});
    if (!["pendingReview", "approved", "reuploadRequired"].includes(metadata.reviewStatus as string) ||
        typeof metadata.contentType !== "string" || typeof metadata.sizeBytes !== "number" ||
        !Number.isInteger(metadata.sizeBytes) || metadata.sizeBytes <= 0) {
      throw new HttpsError("internal", "Belge verisi doğrulanamadı.",
        {reason: "driver_application_document_data_invalid"});
    }
    return {documentType: type, reviewStatus: metadata.reviewStatus,
      reviewedAtMillis: timestampMillis(metadata.reviewedAt, true),
      rejectionReasonCode: stringValue(metadata.rejectionReasonCode, true),
      contentType: metadata.contentType, sizeBytes: metadata.sizeBytes};
  });
  return {reviewContext: {...reviewContext},
    application: {applicationId: id, status: stringValue(data.status),
    reviewState: applicationReviewState(data),
    submittedAtMillis: timestampMillis(data.submittedAt), updatedAtMillis: timestampMillis(data.updatedAt),
    reviewedAtMillis: timestampMillis(data.reviewedAt, true), submissionVersion: positiveStoredInteger(data.submissionVersion),
    fullName: stringValue(data.fullName), verifiedPhoneNumber: stringValue(data.verifiedPhoneNumber),
    email: stringValue(data.email, true), driverTaxiStandName: stringValue(data.driverTaxiStandName, true),
    driverTaxiStandAddress: stringValue(data.driverTaxiStandAddress, true), workType: stringValue(data.workType),
    vehiclePlate: stringValue(data.vehiclePlate), vehicleBrand: stringValue(data.vehicleBrand),
    vehicleModel: stringValue(data.vehicleModel), vehicleModelYear: positiveStoredInteger(data.vehicleModelYear),
    registrationOwnerType: stringValue(data.registrationOwnerType),
    hasVehicleUseAuthorization: data.hasVehicleUseAuthorization === true,
    vehicleTaxiStandName: stringValue(data.vehicleTaxiStandName, true),
    informationAccuracyAccepted: data.informationAccuracyAccepted === true,
    documentValidityNotificationAccepted: data.documentValidityNotificationAccepted === true,
    documentProcessingNoticeAccepted: data.documentProcessingNoticeAccepted === true,
    kvkkNoticeAccepted: data.kvkkNoticeAccepted === true, termsAccepted: data.termsAccepted === true,
    marketingConsent: data.marketingConsent === true}, documents: mappedDocuments};
};

export const calculateReviewUrlExpiry = (nowMillis: number, durationMillis = 180000): number => {
  if (!Number.isInteger(nowMillis) || nowMillis < 0 || !Number.isInteger(durationMillis) ||
      durationMillis <= 0 || durationMillis > 300000) {
    throw new RangeError("Geçersiz URL süresi.");
  }
  return nowMillis + durationMillis;
};
