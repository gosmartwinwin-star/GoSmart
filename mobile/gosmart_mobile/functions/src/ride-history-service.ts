import {
  FieldPath,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {loadDriverProfileId} from "./ride-driver-identity.js";
import {
  TERMINAL_RIDE_STATUSES,
  parseRideStatus,
  serializeActiveRide,
} from "./ride-lifecycle-helpers.js";
import {
  validateRideHistoryPayload,
} from "./ride-history-helpers.js";

export type RideHistoryDependencies = {
  firestore: Firestore;
};

const invalidStoredRide = (): never => {
  throw new HttpsError(
    "internal",
    "Ride history data is invalid.",
    {reason: "ride_data_invalid"},
  );
};

export const getRideHistoryForActor = async (
  dependencies: RideHistoryDependencies,
  actorUid: string,
  rawInput: unknown,
): Promise<Record<string, unknown>> => {
  const input = validateRideHistoryPayload(rawInput);

  const participantField =
    input.scope === "passenger" ? "passengerId" : "driverId";

  const participantId = input.scope === "passenger" ?
    actorUid :
    await loadDriverProfileId(
      dependencies.firestore,
      actorUid,
    );

  if (participantId === null) {
    return {
      rides: [],
      nextCursor: null,
    };
  }

  let query = dependencies.firestore
    .collection("rides")
    .where(participantField, "==", participantId)
    .where("status", "in", TERMINAL_RIDE_STATUSES)
    .orderBy("updatedAt", "desc")
    .orderBy(FieldPath.documentId(), "desc")
    .limit(input.pageSize + 1);

  if (input.cursor !== null) {
    query = query.startAfter(
      Timestamp.fromMillis(input.cursor.updatedAtMillis),
      input.cursor.rideId,
    );
  }

  const snapshot = await query.get();
  const visibleDocs = snapshot.docs.slice(0, input.pageSize);
  const hasMore = snapshot.docs.length > input.pageSize;

  const rides = visibleDocs.map((document) => {
    const data = document.data();

    if (data[participantField] !== participantId) {
      return invalidStoredRide();
    }

    const status = parseRideStatus(data.status);

    if (!TERMINAL_RIDE_STATUSES.includes(status)) {
      return invalidStoredRide();
    }

    return serializeActiveRide(document.id, data);
  });

  let nextCursor: {
    updatedAtMillis: number;
    rideId: string;
  } | null = null;

  if (hasMore && visibleDocs.length > 0) {
    const last = visibleDocs[visibleDocs.length - 1];
    const updatedAt = last.get("updatedAt");

    if (!(updatedAt instanceof Timestamp)) {
      return invalidStoredRide();
    }

    nextCursor = {
      updatedAtMillis: updatedAt.toMillis(),
      rideId: last.id,
    };
  }

  return {
    rides,
    nextCursor,
  };
};
