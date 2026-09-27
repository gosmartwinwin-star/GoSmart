import {FieldPath, Timestamp, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {requireYoldaAlAdmin} from "./admin-authorization-helpers.js";

const SUPPORT_CATEGORIES = new Set([
  "safety",
  "behavior",
  "fare",
  "route",
  "pickup",
  "no-show",
  "cancel",
  "vehicle",
  "technical",
  "lost-item",
]);

type AdminListCursor = {
  createdAtMillis: number;
  rideId: string;
  caseId: string;
};

type AdminListInput = {
  pageSize: number;
  cursor: AdminListCursor | null;
};

const invalidPayload = (): never => {
  throw new HttpsError(
    "invalid-argument",
    "Ride support admin request failed.",
    {reason: "invalid_ride_support_admin_list_payload"},
  );
};

const invalidData = (): never => {
  throw new HttpsError(
    "internal",
    "Ride support admin request failed.",
    {reason: "ride_support_admin_list_data_invalid"},
  );
};

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const requiredText = (value: unknown): string => {
  if (typeof value !== "string" || value.trim().length === 0) {
    return invalidData();
  }
  return value.trim();
};

const nullableText = (value: unknown): string | null => {
  if (value === null) return null;
  return requiredText(value);
};

const timestampMillis = (value: unknown): number => {
  if (!(value instanceof Timestamp)) return invalidData();
  return value.toMillis();
};

export const parseRideSupportAdminListInput = (
  raw: unknown,
): AdminListInput => {
  if (raw === undefined || raw === null) {
    return {pageSize: 20, cursor: null};
  }
  if (!isRecord(raw)) return invalidPayload();

  const keys = Object.keys(raw);
  if (keys.some((key) => key !== "pageSize" && key !== "cursor")) {
    return invalidPayload();
  }

  const pageSizeValue = raw.pageSize ?? 20;
  if (
    typeof pageSizeValue !== "number" ||
    !Number.isInteger(pageSizeValue) ||
    pageSizeValue < 1 ||
    pageSizeValue > 50
  ) {
    return invalidPayload();
  }

  if (raw.cursor === undefined || raw.cursor === null) {
    return {pageSize: pageSizeValue, cursor: null};
  }
  if (!isRecord(raw.cursor)) return invalidPayload();

  const cursorKeys = Object.keys(raw.cursor);
  if (
    cursorKeys.length !== 3 ||
    cursorKeys.some(
      (key) =>
        key !== "createdAtMillis" &&
        key !== "rideId" &&
        key !== "caseId",
    )
  ) {
    return invalidPayload();
  }

  const createdAtMillis = raw.cursor.createdAtMillis;
  const rideId = raw.cursor.rideId;
  const caseId = raw.cursor.caseId;
  if (
    typeof createdAtMillis !== "number" ||
    !Number.isSafeInteger(createdAtMillis) ||
    createdAtMillis < 0 ||
    typeof rideId !== "string" ||
    rideId.trim().length === 0 ||
    rideId.includes("/") ||
    typeof caseId !== "string" ||
    caseId.trim().length === 0 ||
    caseId.includes("/")
  ) {
    return invalidPayload();
  }

  return {
    pageSize: pageSizeValue,
    cursor: {
      createdAtMillis,
      rideId: rideId.trim(),
      caseId: caseId.trim(),
    },
  };
};

export const serializeRideSupportCaseForAdmin = (
  path: string,
  data: Record<string, unknown>,
) => {
  const match = /^rides\/([^/]+)\/supportCases\/([^/]+)$/.exec(path);
  if (!match) return invalidData();

  const reporterRole = requiredText(data.reporterRole);
  if (reporterRole !== "passenger" && reporterRole !== "driver") {
    return invalidData();
  }

  const category = requiredText(data.category);
  if (!SUPPORT_CATEGORIES.has(category)) return invalidData();

  const status = requiredText(data.status);
  if (status !== "new") return invalidData();

  return {
    rideId: match[1],
    caseId: match[2],
    reporterRole,
    reporterId: requiredText(data.reporterId),
    counterpartyId: nullableText(data.counterpartyId),
    category,
    reporterNote: nullableText(data.reporterNote),
    status,
    createdAtMillis: timestampMillis(data.createdAt),
    updatedAtMillis: timestampMillis(data.updatedAt),
  };
};

export const listRideSupportCasesForAdmin = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 15,
    memory: "256MiB",
    maxInstances: 3,
  },
  async (request) => {
    requireYoldaAlAdmin(request.auth);
    const input = parseRideSupportAdminListInput(request.data);
    const firestore = getFirestore();

    let query = firestore
      .collectionGroup("supportCases")
      .orderBy("createdAt", "desc")
      .orderBy(FieldPath.documentId(), "desc");

    if (input.cursor !== null) {
      const cursorPath =
        `rides/${input.cursor.rideId}/supportCases/${input.cursor.caseId}`;
      query = query.startAfter(
        Timestamp.fromMillis(input.cursor.createdAtMillis),
        cursorPath,
      );
    }

    let snapshot;
    try {
      snapshot = await query.limit(input.pageSize + 1).get();
    } catch {
      throw new HttpsError(
        "unavailable",
        "Ride support admin request failed.",
        {reason: "ride_support_admin_list_failed"},
      );
    }

    const hasMore = snapshot.docs.length > input.pageSize;
    const visibleDocs = snapshot.docs.slice(0, input.pageSize);
    const items = visibleDocs.map((doc) =>
      serializeRideSupportCaseForAdmin(doc.ref.path, doc.data()),
    );

    const last = visibleDocs[visibleDocs.length - 1];
    const nextCursor =
      hasMore && last ?
        {
          createdAtMillis: timestampMillis(last.get("createdAt")),
          rideId: last.ref.parent.parent?.id ?? invalidData(),
          caseId: last.id,
        } :
        null;

    return {items, nextCursor};
  },
);
