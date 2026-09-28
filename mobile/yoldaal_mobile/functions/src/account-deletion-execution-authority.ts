import {randomUUID} from "node:crypto";
import {getAuth} from "firebase-admin/auth";
import {
  FieldValue,
  Firestore,
  QueryDocumentSnapshot,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {HttpsError} from "firebase-functions/v2/https";

const ACTIVE_RIDE_STATUSES = new Set([
  "matching",
  "driverEnRoute",
  "driverArrived",
  "inProgress",
]);

const TERMINAL_RIDE_STATUSES = new Set([
  "completed",
  "cancelled",
  "expired",
]);

const PASSENGER_SENTINEL = "deleted-passenger";
const DRIVER_SENTINEL = "deleted-driver";
const EXECUTION_LEASE_TTL_MS = 5 * 60 * 1000;

const STAGING_DOCUMENT_TYPES = [
  "driverLicenseFront",
  "driverLicenseBack",
  "identityCardFront",
  "identityCardBack",
  "vehicleRegistration",
  "driverProfilePhoto",
  "criminalRecord",
] as const;

const failure = (
  code: "unauthenticated" | "invalid-argument" | "failed-precondition" |
    "not-found" | "internal" | "unavailable",
  reason: string,
): HttpsError =>
  new HttpsError(code, "Account deletion operation failed.", {reason});

const plainRecord = (value: unknown): Record<string, unknown> | null =>
  typeof value === "object" && value !== null && !Array.isArray(value) ?
    value as Record<string, unknown> :
    null;

const executionRequest = (
  data: unknown,
): void => {
  const record = plainRecord(data);
  if (record === null || Object.keys(record).length !== 0) {
    throw failure(
      "invalid-argument",
      "invalid_account_deletion_execution_payload",
    );
  }
};

const boundedString = (
  value: unknown,
): string | null =>
  typeof value === "string" && value.length > 0 && value.length <= 256 ?
    value :
    null;

export const validateAccountDeletionExecutionPayload = executionRequest;

export const isBlockingAccountDeletionRideStatus = (
  status: unknown,
): boolean => typeof status === "string" && ACTIVE_RIDE_STATUSES.has(status);

const readRequest = async (
  firestore: Firestore,
  uid: string,
) => {
  const snapshot = await firestore
    .collection("accountDeletionRequests")
    .doc(uid)
    .get();
  if (!snapshot.exists) {
    throw failure(
      "failed-precondition",
      "account_deletion_request_required",
    );
  }
  return snapshot;
};

const resolveDriverId = async (
  firestore: Firestore,
  uid: string,
  resumeDriverId: string | null,
): Promise<string | null> => {
  if (resumeDriverId !== null) return resumeDriverId;
  const query = await firestore
    .collection("driverProfiles")
    .where("authUserId", "==", uid)
    .limit(2)
    .get();
  if (query.size > 1) {
    throw failure("failed-precondition", "driver_identity_ambiguous");
  }
  return query.empty ? null : query.docs[0].id;
};

const assertNoActiveRide = async (
  firestore: Firestore,
  uid: string,
  driverId: string | null,
): Promise<void> => {
  const reads = [
    firestore.collection("passengerActiveRides").doc(uid).get(),
  ];
  if (driverId !== null) {
    reads.push(
      firestore.collection("driverActiveRides").doc(driverId).get(),
    );
  }
  const snapshots = await Promise.all(reads);
  for (const snapshot of snapshots) {
    if (snapshot.exists &&
        isBlockingAccountDeletionRideStatus(snapshot.get("status"))) {
      throw failure(
        "failed-precondition",
        "active_ride_blocks_account_deletion",
      );
    }
  }
};

type BeginExecutionResult =
  | {state: "started"; leaseId: string}
  | {state: "processing"}
  | {state: "completed"};

const leaseExpiry = (now: Timestamp): Timestamp =>
  Timestamp.fromMillis(now.toMillis() + EXECUTION_LEASE_TTL_MS);

export const isAccountDeletionExecutionLeaseActive = (
  leaseExpiresAtMillis: number | null,
  nowMillis: number,
): boolean =>
  leaseExpiresAtMillis !== null &&
  Number.isFinite(leaseExpiresAtMillis) &&
  leaseExpiresAtMillis > nowMillis;

const beginExecution = async (
  firestore: Firestore,
  uid: string,
  driverId: string | null,
): Promise<BeginExecutionResult> => {
  const ref = firestore.collection("accountDeletionRequests").doc(uid);
  const leaseId = randomUUID();
  return firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) {
      throw failure(
        "failed-precondition",
        "account_deletion_request_required",
      );
    }
    const status = boundedString(snapshot.get("status"));
    if (status === "completed") return {state: "completed"};

    const now = Timestamp.now();
    if (status === "processing") {
      const currentLeaseId =
        boundedString(snapshot.get("executionLeaseId"));
      const currentLeaseExpiry = snapshot.get("leaseExpiresAt");
      const currentLeaseExpiryMillis =
        currentLeaseExpiry instanceof Timestamp ?
          currentLeaseExpiry.toMillis() :
          null;
      if (currentLeaseId !== null &&
          isAccountDeletionExecutionLeaseActive(
            currentLeaseExpiryMillis,
            now.toMillis(),
          )) {
        return {state: "processing"};
      }
    } else if (status !== "requested" && status !== "failed") {
      throw failure(
        "failed-precondition",
        "account_deletion_request_state_invalid",
      );
    }

    transaction.update(ref, {
      status: "processing",
      executionDriverId: driverId,
      executionLeaseId: leaseId,
      leaseExpiresAt: leaseExpiry(now),
      lastFailureCode: FieldValue.delete(),
      updatedAt: now,
    });
    return {state: "started", leaseId};
  });
};

const renewExecutionLease = async (
  firestore: Firestore,
  uid: string,
  leaseId: string,
): Promise<void> => {
  const ref = firestore.collection("accountDeletionRequests").doc(uid);
  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists ||
        snapshot.get("status") !== "processing" ||
        snapshot.get("executionLeaseId") !== leaseId) {
      throw failure(
        "failed-precondition",
        "account_deletion_execution_lease_lost",
      );
    }
    const now = Timestamp.now();
    transaction.update(ref, {
      leaseExpiresAt: leaseExpiry(now),
      updatedAt: now,
    });
  });
};

const markFailed = async (
  firestore: Firestore,
  uid: string,
  leaseId: string,
  code: string,
): Promise<void> => {
  const ref = firestore.collection("accountDeletionRequests").doc(uid);
  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists ||
        snapshot.get("status") !== "processing" ||
        snapshot.get("executionLeaseId") !== leaseId) {
      return;
    }
    transaction.update(ref, {
      status: "failed",
      lastFailureCode: code,
      executionLeaseId: FieldValue.delete(),
      leaseExpiresAt: FieldValue.delete(),
      updatedAt: Timestamp.now(),
    });
  });
};

const deleteEphemeralState = async (
  firestore: Firestore,
  uid: string,
  driverId: string | null,
): Promise<void> => {
  const batch = firestore.batch();
  batch.delete(firestore.collection("passengerActiveRides").doc(uid));
  batch.delete(firestore.collection("passengerPushTargets").doc(uid));
  if (driverId !== null) {
    for (const collection of [
      "driverActiveRides",
      "driverLivePresences",
      "nearbyDriverGeoIndexes",

      "driverReturnRouteCorridorIndexes",
      "driverPushTargets",
    ]) {
      batch.delete(firestore.collection(collection).doc(driverId));
    }
  }
  await batch.commit();
};

const updateOwnRating = async (
  ride: QueryDocumentSnapshot,
  role: "passenger" | "driver",
): Promise<void> => {
  const ratingRef = ride.ref.collection("ratings").doc(role);
  const rating = await ratingRef.get();
  if (!rating.exists) return;
  const expectedSentinel =
    role === "passenger" ? PASSENGER_SENTINEL : DRIVER_SENTINEL;
  if (rating.get("raterId") === expectedSentinel) return;
  await ratingRef.update({raterId: expectedSentinel});
};

const anonymizeVoiceCalls = async (
  ride: QueryDocumentSnapshot,
  authUid: string,
): Promise<void> => {
  const snapshot = await ride.ref.collection("voiceCalls").get();
  for (const call of snapshot.docs) {
    const data = call.data();
    const caller = plainRecord(data.caller);
    const callee = plainRecord(data.callee);
    const updates: Record<string, unknown> = {};
    if (caller?.uid === authUid) {
      updates["caller.uid"] =
        caller.role === "driver" ? DRIVER_SENTINEL : PASSENGER_SENTINEL;
    }
    if (callee?.uid === authUid) {
      updates["callee.uid"] =
        callee.role === "driver" ? DRIVER_SENTINEL : PASSENGER_SENTINEL;
    }
    if (Object.keys(updates).length > 0) await call.ref.update(updates);
  }
};

const anonymizeRide = async (
  ride: QueryDocumentSnapshot,
  authUid: string,
  driverId: string | null,
): Promise<void> => {
  const data = ride.data();
  const status = boundedString(data.status);
  if (status === null || !TERMINAL_RIDE_STATUSES.has(status)) {
    throw failure(
      "failed-precondition",
      "non_terminal_ride_blocks_account_deletion",
    );
  }

  const passengerOwned = data.passengerId === authUid;
  const driverOwned = driverId !== null && data.driverId === driverId;
  if (!passengerOwned && !driverOwned) return;

  if (passengerOwned) await updateOwnRating(ride, "passenger");
  if (driverOwned) await updateOwnRating(ride, "driver");
  await ride.ref.firestore
    .collection("rideVoiceActiveCalls")
    .doc(ride.id)
    .delete();
  await anonymizeVoiceCalls(ride, authUid);

  const updates: Record<string, unknown> = {};
  if (passengerOwned) updates.passengerId = PASSENGER_SENTINEL;
  if (driverOwned) updates.driverId = DRIVER_SENTINEL;
  if (Object.keys(updates).length > 0) await ride.ref.update(updates);
};

const anonymizeRidesForField = async (
  firestore: Firestore,
  field: "passengerId" | "driverId",
  value: string,
  authUid: string,
  driverId: string | null,
): Promise<void> => {
  let cursor: QueryDocumentSnapshot | null = null;
  for (;;) {
    let query = firestore
      .collection("rides")
      .where(field, "==", value)
      .orderBy("__name__")
      .limit(50);
    if (cursor !== null) query = query.startAfter(cursor);
    const page = await query.get();
    if (page.empty) return;
    for (const ride of page.docs) {
      await anonymizeRide(ride, authUid, driverId);
    }
    cursor = page.docs[page.docs.length - 1];
    if (page.size < 50) return;
  }
};

const anonymizeHistoricalData = async (
  firestore: Firestore,
  uid: string,
  driverId: string | null,
): Promise<void> => {
  await anonymizeRidesForField(
    firestore,
    "passengerId",
    uid,
    uid,
    driverId,
  );
  if (driverId !== null) {
    await anonymizeRidesForField(
      firestore,
      "driverId",
      driverId,
      uid,
      driverId,
    );

    let cursor: QueryDocumentSnapshot | null = null;
    for (;;) {
      let query = firestore
        .collection("driverReturnRoutes")
        .where("driverId", "==", driverId)
        .orderBy("__name__")
        .limit(50);
      if (cursor !== null) query = query.startAfter(cursor);
      const page = await query.get();
      if (page.empty) break;
      for (const route of page.docs) {
        await route.ref.update({driverId: DRIVER_SENTINEL});
      }
      cursor = page.docs[page.docs.length - 1];
      if (page.size < 50) break;
    }
  }
};

const deleteStagingObjects = async (
  uid: string,
): Promise<void> => {
  const bucket = getStorage().bucket();
  for (const type of STAGING_DOCUMENT_TYPES) {
    const file = bucket.file(`driverApplicationUploads/${uid}/${type}/current`);
    try {
      await file.delete();
    } catch (error) {
      const code = plainRecord(error)?.code;
      if (code !== 404 && code !== "404") throw error;
    }
  }
};

const anonymizeDriverProfile = async (
  firestore: Firestore,
  driverId: string | null,
): Promise<void> => {
  if (driverId === null) return;
  const ref = firestore.collection("driverProfiles").doc(driverId);
  const snapshot = await ref.get();
  if (!snapshot.exists) return;
  if (snapshot.get("authUserId") === DRIVER_SENTINEL) return;
  await ref.update({authUserId: DRIVER_SENTINEL});
};

const completeRequest = async (
  firestore: Firestore,
  uid: string,
  leaseId: string,
): Promise<void> => {
  const ref = firestore.collection("accountDeletionRequests").doc(uid);
  let lastError: unknown = null;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      await firestore.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(ref);
        if (!snapshot.exists) {
          throw failure(
            "failed-precondition",
            "account_deletion_request_required",
          );
        }
        if (snapshot.get("status") === "completed") return;
        if (snapshot.get("status") !== "processing" ||
            snapshot.get("executionLeaseId") !== leaseId) {
          throw failure(
            "failed-precondition",
            "account_deletion_execution_lease_lost",
          );
        }
        const now = Timestamp.now();
        transaction.update(ref, {
          status: "completed",
          completedAt: now,
          updatedAt: now,
          authUid: FieldValue.delete(),
          executionDriverId: FieldValue.delete(),
          executionLeaseId: FieldValue.delete(),
          leaseExpiresAt: FieldValue.delete(),
          lastFailureCode: FieldValue.delete(),
        });
      });
      return;
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
};

const safeFailureCode = (
  error: unknown,
): string => {
  if (error instanceof HttpsError) {
    const details = plainRecord(error.details);
    const reason = boundedString(details?.reason);
    if (reason !== null) return reason;
  }
  return "account_deletion_execution_failed";
};

export const executeAccountDeletionForUser = async (
  uid: string,
): Promise<{status: "processing" | "completed"; idempotent: boolean}> => {
  if (uid.length === 0) {
    throw failure("unauthenticated", "authentication_required");
  }

  const firestore = getFirestore();
  const request = await readRequest(firestore, uid);
  const requestStatus = boundedString(request.get("status"));
  if (requestStatus === "completed") {
    return {status: "completed", idempotent: true};
  }

  const resumeDriverId =
    boundedString(request.get("executionDriverId"));
  const driverId =
    await resolveDriverId(firestore, uid, resumeDriverId);

  await assertNoActiveRide(firestore, uid, driverId);

  const begin = await beginExecution(firestore, uid, driverId);
  if (begin.state === "completed") {
    return {status: "completed", idempotent: true};
  }
  if (begin.state === "processing") {
    return {status: "processing", idempotent: true};
  }
  const leaseId = begin.leaseId;

  let authDeleted = false;
  try {
    await renewExecutionLease(firestore, uid, leaseId);
    await deleteEphemeralState(firestore, uid, driverId);

    await renewExecutionLease(firestore, uid, leaseId);
    await anonymizeHistoricalData(firestore, uid, driverId);

    await renewExecutionLease(firestore, uid, leaseId);
    await deleteStagingObjects(uid);

    // RETAIN_PENDING_AUTHORITY resources are intentionally untouched:
    // supportCases/adminEvents, ride messages, driverApplications,
    // driver review/audit events and driverApplicationSubmissions.

    await renewExecutionLease(firestore, uid, leaseId);
    await anonymizeDriverProfile(firestore, driverId);

    await renewExecutionLease(firestore, uid, leaseId);
    try {
      await getAuth().deleteUser(uid);
      authDeleted = true;
    } catch (error) {
      const record = plainRecord(error);
      const code = boundedString(record?.code);
      if (code === "auth/user-not-found") {
        authDeleted = true;
      } else {
        throw error;
      }
    }

    await completeRequest(firestore, uid, leaseId);
    return {status: "completed", idempotent: false};
  } catch (error) {
    if (!authDeleted) {
      try {
        await markFailed(
          firestore,
          uid,
          leaseId,
          safeFailureCode(error),
        );
      } catch {
        // Preserve the original failure. A later backend-authorized retry may
        // resume from failed or stale processing state.
      }
    }
    throw error instanceof HttpsError ?
      error :
      failure("unavailable", "account_deletion_execution_failed");
  }
};

export const executeAccountDeletionCallable = async (
  uid: string | undefined,
  data: unknown,
): Promise<{status: "processing" | "completed"; idempotent: boolean}> => {
  if (uid === undefined || uid.length === 0) {
    throw failure("unauthenticated", "authentication_required");
  }
  validateAccountDeletionExecutionPayload(data);
  return executeAccountDeletionForUser(uid);
};
