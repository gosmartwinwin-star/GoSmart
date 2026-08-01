/* eslint-disable max-len */
import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {DocumentType, REQUIRED_DOCUMENT_TYPES} from "./driver-application-helpers.js";
import {validateCurrentApplicationVersion, validateCurrentDocumentMetadata} from "./driver-application-review-helpers.js";

const STATUSES = ["pendingReview", "approved", "rejected", "withdrawn"] as const;
type ReviewStatus = typeof STATUSES[number];
export type PageCursor = {submittedAtMillis: number; applicationId: string};
export type ListInput = {status: ReviewStatus; pageSize: number; cursor: PageCursor | null};
export type DetailsInput = {applicationId: string; submissionVersion: number; documentSetId: string};
export type UrlInput = DetailsInput & {documentType: DocumentType};

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
  const input = exact(value, ["status", "pageSize", "cursor"], "invalid_admin_list_payload");
  const status = input.status ?? "pendingReview";
  if (!STATUSES.includes(status as ReviewStatus)) throw invalid("invalid_review_status");
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
  return {status: status as ReviewStatus, pageSize, cursor};
};

export const validateApplicationDetailsPayload = (value: unknown): DetailsInput => {
  const input = exact(value, ["applicationId", "submissionVersion", "documentSetId"],
    "invalid_review_details_payload");
  if (Object.keys(input).length !== 3) throw invalid("invalid_review_details_payload");
  return {applicationId: identifier(input.applicationId, "invalid_application_id"),
    submissionVersion: positiveVersion(input.submissionVersion),
    documentSetId: identifier(input.documentSetId, "invalid_document_set_id")};
};

export const validateDocumentReviewUrlPayload = (value: unknown): UrlInput => {
  const input = exact(value, ["applicationId", "submissionVersion", "documentSetId", "documentType"],
    "invalid_document_review_url_payload");
  const common = validateApplicationDetailsPayload({applicationId: input.applicationId,
    submissionVersion: input.submissionVersion, documentSetId: input.documentSetId});
  if (!REQUIRED_DOCUMENT_TYPES.includes(input.documentType as DocumentType)) {
    throw invalid("invalid_document_type");
  }
  return {...common, documentType: input.documentType as DocumentType};
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
  documents: readonly {type: DocumentType; data: Record<string, unknown>}[], input: DetailsInput) => {
  validateCurrentApplicationVersion(data, input.submissionVersion, input.documentSetId);
  if (documents.length !== REQUIRED_DOCUMENT_TYPES.length) {
    throw new HttpsError("internal", "Başvuru belgeleri doğrulanamadı.",
      {reason: "driver_application_review_data_invalid"});
  }
  const mappedDocuments = documents.map(({type, data: metadata}) => {
    validateCurrentDocumentMetadata(metadata, {...input, documentType: type});
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
  return {application: {applicationId: id, status: stringValue(data.status),
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
    marketingConsent: data.marketingConsent === true,
    rejectionReasonCode: stringValue(data.rejectionReasonCode, true)}, documents: mappedDocuments};
};

export const calculateReviewUrlExpiry = (nowMillis: number, durationMillis = 180000): number => {
  if (!Number.isInteger(nowMillis) || nowMillis < 0 || !Number.isInteger(durationMillis) ||
      durationMillis <= 0 || durationMillis > 300000) {
    throw new RangeError("Geçersiz URL süresi.");
  }
  return nowMillis + durationMillis;
};
