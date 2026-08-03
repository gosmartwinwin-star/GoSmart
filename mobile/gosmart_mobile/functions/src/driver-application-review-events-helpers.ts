/* eslint-disable max-len */
import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {DocumentType, REQUIRED_DOCUMENT_TYPES} from "./driver-application-helpers.js";

const EVENT_TYPES = ["applicationViewed", "documentViewed", "documentApproved",
  "documentReuploadRequired", "applicationApproved", "applicationRejected"] as const;
const DOCUMENT_REASONS = ["unreadable_document", "incomplete_document",
  "expired_document", "information_mismatch", "wrong_document",
  "unsupported_document"] as const;
const APPLICATION_REASONS = ["personal_information_invalid",
  "vehicle_information_invalid", "document_information_mismatch",
  "eligibility_requirements_not_met", "duplicate_application",
  "application_information_incomplete", "document_reupload_required"] as const;

export type ReviewEventType = typeof EVENT_TYPES[number] | "unknownReviewEvent";
export type ReviewEventsCursor = {createdAtMillis: number; eventId: string};
export type ReviewEventsInput = {applicationId: string; pageSize: number;
  cursor: ReviewEventsCursor | null};
export type SafeReviewEvent = {type: ReviewEventType; occurredAtMillis: number;
  documentType?: DocumentType; decision?: "approve" | "requireReupload" | "reject";
  reasonCode?: string};
export type ReviewEventDocument = {id: string; data: Record<string, unknown>};

const invalid = () => new HttpsError("invalid-argument",
  "İnceleme geçmişi isteği uygun değildir.",
  {reason: "invalid_driver_application_review_events_payload"});
const dataInvalid = () => new HttpsError("internal",
  "İnceleme geçmişi bilgileri doğrulanamadı.",
  {reason: "driver_application_review_events_data_invalid"});
const exact = (value: unknown, keys: readonly string[]): Record<string, unknown> => {
  if (typeof value !== "object" || value === null || Array.isArray(value) ||
      Object.getPrototypeOf(value) !== Object.prototype) throw invalid();
  const result = value as Record<string, unknown>;
  if (Object.keys(result).some((key) => !keys.includes(key))) throw invalid();
  return result;
};
const identifier = (value: unknown): string => {
  if (typeof value !== "string" || value.trim().length === 0 ||
      value.trim().length > 128 || !/^[A-Za-z0-9_-]+$/u.test(value.trim())) {
    throw invalid();
  }
  return value.trim();
};
const nonNegativeInteger = (value: unknown): number => {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) throw invalid();
  return value;
};

export const validateReviewEventsPayload = (value: unknown): ReviewEventsInput => {
  const input = exact(value, ["applicationId", "pageSize", "cursor"]);
  const applicationId = identifier(input.applicationId);
  const pageSize = input.pageSize ?? 20;
  if (typeof pageSize !== "number" || !Number.isInteger(pageSize) ||
      pageSize < 1 || pageSize > 50) throw invalid();
  let cursor: ReviewEventsCursor | null = null;
  if (input.cursor !== undefined && input.cursor !== null) {
    const raw = exact(input.cursor, ["createdAtMillis", "eventId"]);
    if (Object.keys(raw).length !== 2) throw invalid();
    cursor = {createdAtMillis: nonNegativeInteger(raw.createdAtMillis),
      eventId: identifier(raw.eventId)};
  }
  return {applicationId, pageSize, cursor};
};

const safeEvent = (data: Record<string, unknown>): Omit<SafeReviewEvent, "occurredAtMillis"> => {
  const rawType = data.eventType;
  if (!EVENT_TYPES.includes(rawType as typeof EVENT_TYPES[number])) {
    return {type: "unknownReviewEvent"};
  }
  const type = rawType as typeof EVENT_TYPES[number];
  const documentType = data.documentType;
  if ((type === "documentViewed" || type === "documentApproved" ||
       type === "documentReuploadRequired") &&
      !REQUIRED_DOCUMENT_TYPES.includes(documentType as DocumentType)) {
    return {type: "unknownReviewEvent"};
  }
  const result: Omit<SafeReviewEvent, "occurredAtMillis"> = {type};
  if (REQUIRED_DOCUMENT_TYPES.includes(documentType as DocumentType)) {
    result.documentType = documentType as DocumentType;
  }
  if (type === "documentApproved" || type === "applicationApproved") {
    result.decision = "approve";
  } else if (type === "documentReuploadRequired") {
    result.decision = "requireReupload";
  } else if (type === "applicationRejected") {
    result.decision = "reject";
  }
  const reason = data.reasonCode;
  if (typeof reason === "string" &&
      (DOCUMENT_REASONS.includes(reason as typeof DOCUMENT_REASONS[number]) ||
       APPLICATION_REASONS.includes(reason as typeof APPLICATION_REASONS[number]))) {
    result.reasonCode = reason;
  }
  return result;
};

export const mapReviewEvent = (data: Record<string, unknown>): SafeReviewEvent => {
  const createdAt = data.createdAt;
  if (!(createdAt instanceof Timestamp) || createdAt.toMillis() < 0) throw dataInvalid();
  return {...safeEvent(data), occurredAtMillis: createdAt.toMillis()};
};

export const buildReviewEventsPage = (documents: readonly ReviewEventDocument[],
  pageSize: number): {items: SafeReviewEvent[]; nextCursor: ReviewEventsCursor | null} => {
  const visible = documents.slice(0, pageSize);
  const items = visible.map((document) => mapReviewEvent(document.data));
  if (documents.length <= pageSize || visible.length === 0) return {items, nextCursor: null};
  const last = visible[visible.length - 1];
  const timestamp = last.data.createdAt;
  if (!(timestamp instanceof Timestamp) || timestamp.toMillis() < 0 ||
      last.id.trim().length === 0) throw dataInvalid();
  return {items, nextCursor: {createdAtMillis: timestamp.toMillis(), eventId: last.id}};
};
