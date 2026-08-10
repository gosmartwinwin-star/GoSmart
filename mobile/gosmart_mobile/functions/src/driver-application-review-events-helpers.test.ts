/* eslint-disable max-len */
import assert from "node:assert/strict";
import test from "node:test";
import {readFileSync} from "node:fs";
import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {buildReviewEventsPage, mapReviewEvent,
  validateReviewEventsPayload} from "./driver-application-review-events-helpers.js";

const reason = (operation: () => unknown, expected: string) => assert.throws(operation,
  (error: unknown) => error instanceof HttpsError &&
    (error.details as {reason?: string}).reason === expected);
const invalidPayload = (value: unknown) => reason(() => validateReviewEventsPayload(value),
  "invalid_driver_application_review_events_payload");
const event = (extra: Record<string, unknown> = {}) => ({id: "event-a", data: {
  applicationId: "app-secret", reviewerAuthUserId: "admin-secret",
  eventType: "documentApproved", documentType: "criminalRecord",
  reasonCode: null, submissionVersion: 2, documentSetId: "set-secret",
  storagePath: "secret", signedUrl: "secret", fullName: "secret",
  createdAt: Timestamp.fromMillis(1000), ...extra}});

test("review event payload defaults and boundaries are strict", () => {
  assert.deepEqual(validateReviewEventsPayload({applicationId: "app-a"}),
    {applicationId: "app-a", pageSize: 20, cursor: null});
  assert.equal(validateReviewEventsPayload({applicationId: "app-a", pageSize: 1}).pageSize, 1);
  assert.equal(validateReviewEventsPayload({applicationId: "app-a", pageSize: 50}).pageSize, 50);
  for (const pageSize of [0, 51, true, 1.2]) invalidPayload({applicationId: "app-a", pageSize});
});

test("review event payload rejects missing, malformed and extra application ids", () => {
  for (const value of [{}, {applicationId: ""}, {applicationId: true},
    {applicationId: "a/b"}, {applicationId: "app-a", admin: true}, null, []]) invalidPayload(value);
});

test("review event cursor is exact and deterministic", () => {
  assert.deepEqual(validateReviewEventsPayload({applicationId: "app-a", cursor: {
    createdAtMillis: 123, eventId: "event-a"}}).cursor,
  {createdAtMillis: 123, eventId: "event-a"});
  for (const cursor of [{eventId: "event-a"}, {createdAtMillis: 1},
    {createdAtMillis: 1, eventId: "event-a", extra: true},
    {createdAtMillis: true, eventId: "event-a"},
    {createdAtMillis: 1.2, eventId: "event-a"},
    {createdAtMillis: -1, eventId: "event-a"},
    {createdAtMillis: 1, eventId: ""}]) invalidPayload({applicationId: "app-a", cursor});
});

test("known event types map to safe fields and derived decisions", () => {
  const cases: readonly (readonly [string, string | undefined])[] = [
    ["applicationViewed", undefined], ["documentViewed", undefined],
    ["documentApproved", "approve"], ["documentReuploadRequired", "requireReupload"],
    ["applicationApproved", "approve"], ["applicationRejected", "reject"],
    ["applicationResubmitted", undefined],
  ];
  for (const [type, decision] of cases) {
    const mapped = mapReviewEvent(event({eventType: type,
      documentType: type.toString().startsWith("document") ? "criminalRecord" : null}).data);
    assert.equal(mapped.type, type);
    assert.equal(mapped.decision, decision);
    assert.equal(mapped.occurredAtMillis, 1000);
  }
});

test("unknown categorical values never pass through", () => {
  const unknownType = mapReviewEvent(event({eventType: "rawSecretEvent"}).data);
  assert.deepEqual(unknownType, {type: "unknownReviewEvent", occurredAtMillis: 1000});
  const unknownDocument = mapReviewEvent(event({documentType: "rawSecretDocument"}).data);
  assert.deepEqual(unknownDocument, {type: "unknownReviewEvent", occurredAtMillis: 1000});
  const unknownReason = mapReviewEvent(event({reasonCode: "rawSecretReason"}).data);
  assert.equal("reasonCode" in unknownReason, false);
});

test("known controlled reasons are retained", () => {
  assert.equal(mapReviewEvent(event({reasonCode: "unreadable_document"}).data).reasonCode,
    "unreadable_document");
  assert.equal(mapReviewEvent(event({eventType: "applicationRejected", documentType: null,
    reasonCode: "duplicate_application"}).data).reasonCode, "duplicate_application");
});

test("timestamp must be a resolved non-negative Firestore Timestamp", () => {
  for (const createdAt of [null, undefined, 1000, new Date(), Timestamp.fromMillis(-1)]) {
    reason(() => mapReviewEvent(event({createdAt}).data),
      "driver_application_review_events_data_invalid");
  }
});

test("mapped items exclude all internal, identity, storage and PII fields", () => {
  const mapped = mapReviewEvent(event().data);
  for (const key of ["eventId", "applicationId", "reviewerAuthUserId", "adminUid",
    "email", "phone", "fullName", "vehiclePlate", "documentSetId",
    "submissionVersion", "signedUrl", "storagePath", "createdAt"]) {
    assert.equal(key in mapped, false);
  }
  assert.deepEqual(Object.keys(mapped).sort(),
    ["decision", "documentType", "occurredAtMillis", "type"]);
});

test("pagination returns page size and cursor from last visible document", () => {
  const documents = [event({createdAt: Timestamp.fromMillis(3000)}),
    {id: "event-b", data: event({createdAt: Timestamp.fromMillis(2000)}).data},
    {id: "event-c", data: event({createdAt: Timestamp.fromMillis(1000)}).data}];
  const page = buildReviewEventsPage(documents, 2);
  assert.equal(page.items.length, 2);
  assert.deepEqual(page.nextCursor, {createdAtMillis: 2000, eventId: "event-b"});
  assert.equal("eventId" in page.items[1], false);
  assert.equal(buildReviewEventsPage(documents.slice(0, 2), 2).nextCursor, null);
});

test("pagination preserves order without exposing raw document ids", () => {
  const page = buildReviewEventsPage([
    event({createdAt: Timestamp.fromMillis(3)}),
    {id: "event-b", data: event({eventType: "applicationViewed",
      documentType: null, createdAt: Timestamp.fromMillis(2)}).data},
  ], 20);
  assert.deepEqual(page.items.map((item) => item.occurredAtMillis), [3, 2]);
  assert.equal(JSON.stringify(page.items).includes("event-b"), false);
});

test("callable query is admin-only, deterministic, bounded and read-only", () => {
  const source = readFileSync("src/index.ts", "utf8");
  const start = source.indexOf("export const listDriverApplicationReviewEvents");
  const end = source.indexOf("export const getDriverApplicationReviewDetails", start);
  assert.ok(start >= 0 && end > start);
  const callable = source.slice(start, end);
  assert.match(callable, /requireGoSmartAdmin\(request\.auth\)/u);
  assert.match(callable, /where\("applicationId", "==", input\.applicationId\)/u);
  assert.match(callable, /orderBy\("createdAt", "desc"\)/u);
  assert.match(callable, /orderBy\(FieldPath\.documentId\(\), "desc"\)/u);
  assert.match(callable, /startAfter\(Timestamp\.fromMillis\(/u);
  assert.match(callable, /limit\(input\.pageSize \+ 1\)/u);
  assert.match(callable, /driver_application_not_found/u);
  assert.doesNotMatch(callable, /\.add\(|\.create\(|\.update\(|\.delete\(/u);
  assert.doesNotMatch(callable, /logger\./u);
});
