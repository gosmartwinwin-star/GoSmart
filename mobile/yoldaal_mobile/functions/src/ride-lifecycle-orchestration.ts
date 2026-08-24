/* eslint-disable max-len */
import {Firestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  buildInitialRide,
  requireDriverCancellation,
  requirePassengerCancellation,
  requirePositiveVersion,
  requireRideTransition,
  RideRoute,
  rideOperationId,
  rideRequestDigest,
  validateCancelRidePayload,
  validateCreateRideRequestPayload,
  validateRideMutationPayload,
  parseRideStatus,
} from "./ride-lifecycle-helpers.js";
import {
  loadApprovedDriverId,
  loadApprovedDriverIdInTransaction,
} from "./ride-driver-identity.js";
import {requireRideMatchOfferAuthority} from "./ride-match-offer-authority.js";

export type RideRouteProvider = (pickup: {latitude: number; longitude: number},
  dropoff: {latitude: number; longitude: number}) => Promise<RideRoute>;

export type RideLifecycleDependencies = {
  firestore: Firestore;
  computeRoute: RideRouteProvider;
  now?: () => Timestamp;
};

export const createRideRequestForPassenger = async (
  dependencies: RideLifecycleDependencies,
  passengerId: string,
  rawInput: unknown,
): Promise<Record<string, unknown>> => {
  const input = validateCreateRideRequestPayload(rawInput);
  const {firestore} = dependencies;
  const operationRef = firestore.collection("rideOperations")
    .doc(rideOperationId(passengerId, "createRideRequest", input.requestId));
  const activeRef = firestore.collection("passengerActiveRides").doc(passengerId);
  const digest = rideRequestDigest("createRideRequest", input);
  const existingOperation = await operationRef.get();
  if (existingOperation.exists) {
    const data = existingOperation.data() ?? {};
    if (data.requestDigest !== digest) {
      throw new HttpsError("failed-precondition", "Ä°stek daha Ã¶nce farklÄ± veriyle kullanÄ±ldÄ±.",
        {reason: "idempotency_payload_mismatch"});
    }
    if (data.status === "completed" && typeof data.result === "object" &&
        data.result !== null) return data.result as Record<string, unknown>;
    throw new HttpsError("aborted", "Yolculuk isteÄŸi tamamlanamadÄ±.",
      {reason: "ride_operation_in_progress"});
  }
  if ((await activeRef.get()).exists) {
    throw new HttpsError("already-exists", "Aktif bir yolculuÄŸunuz zaten var.",
      {reason: "passenger_active_ride_exists"});
  }

  let route: RideRoute;
  try {
    route = await dependencies.computeRoute(input.pickup, input.dropoff);
  } catch (_error: unknown) {
    throw new HttpsError("unavailable", "Yolculuk rotasÄ± ÅŸu anda hesaplanamadÄ±.",
      {reason: "ride_route_computation_failed"});
  }
  const rideRef = firestore.collection("rides").doc();
  const eventRef = rideRef.collection("events").doc("rideRequestCreated");
  const now = dependencies.now?.() ?? Timestamp.now();
  try {
    return await firestore.runTransaction(async (transaction) => {
      const [operation, active] = await Promise.all([
        transaction.get(operationRef), transaction.get(activeRef),
      ]);
      const operationData = operation.data() ?? {};
      if (operation.exists) {
        if (operationData.requestDigest !== digest) {
          throw new HttpsError("failed-precondition", "Ä°stek daha Ã¶nce farklÄ± veriyle kullanÄ±ldÄ±.",
            {reason: "idempotency_payload_mismatch"});
        }
        if (operationData.status === "completed" &&
            typeof operationData.result === "object" && operationData.result !== null) {
          return operationData.result as Record<string, unknown>;
        }
        throw new HttpsError("aborted", "Yolculuk isteÄŸi tamamlanamadÄ±.",
          {reason: "ride_operation_in_progress"});
      }
      if (active.exists) {
        throw new HttpsError("already-exists", "Aktif bir yolculuÄŸunuz zaten var.",
          {reason: "passenger_active_ride_exists"});
      }
      const result = {rideId: rideRef.id, status: "matching", version: 1,
        createdAtMillis: now.toMillis(), distanceMeters: route.distanceMeters,
        durationSeconds: route.durationSeconds,
        encodedPolyline: route.encodedPolyline};
      transaction.create(rideRef, buildInitialRide(passengerId, input, route, now));
      transaction.create(activeRef, {rideId: rideRef.id, status: "matching", updatedAt: now});
      transaction.create(eventRef, {type: "rideRequestCreated", fromStatus: null,
        toStatus: "matching", actorType: "passenger", actorId: passengerId,
        createdAt: now});
      transaction.create(operationRef, {actorUid: passengerId,
        callableName: "createRideRequest", requestDigest: digest,
        status: "completed", result, createdAt: now, updatedAt: now});
      return result;
    });
  } catch (error: unknown) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("unavailable", "Yolculuk isteÄŸi kaydedilemedi.",
      {reason: "ride_persistence_failed"});
  }
};

export const cancelRideForActor = async (
  dependencies: Pick<RideLifecycleDependencies, "firestore" | "now">,
  actorUid: string,
  rawInput: unknown,
): Promise<Record<string, unknown>> => {
  const input = validateCancelRidePayload(rawInput);
  const {firestore} = dependencies;
  const rideRef = firestore.collection("rides").doc(input.rideId);
  const operationRef = firestore.collection("rideOperations")
    .doc(rideOperationId(actorUid, "cancelRide", input.requestId));
  const digest = rideRequestDigest("cancelRide", input);
  const now = dependencies.now?.() ?? Timestamp.now();
  try {
    return await firestore.runTransaction(async (transaction) => {
      const operation = await transaction.get(operationRef);
      const operationData = operation.data() ?? {};
      if (operation.exists) {
        if (operationData.requestDigest !== digest) {
          throw new HttpsError("failed-precondition", "Ä°stek daha Ã¶nce farklÄ± veriyle kullanÄ±ldÄ±.",
            {reason: "idempotency_payload_mismatch"});
        }
        if (operationData.status === "completed" &&
            typeof operationData.result === "object" && operationData.result !== null) {
          return operationData.result as Record<string, unknown>;
        }
        throw new HttpsError("aborted", "Yolculuk iptali tamamlanamadÄ±.",
          {reason: "ride_operation_in_progress"});
      }
      const ride = await transaction.get(rideRef);
      if (!ride.exists) {
        throw new HttpsError("not-found", "Yolculuk bulunamadÄ±.",
          {reason: "ride_not_found"});
      }
      const data = ride.data() ?? {};
      const passengerId = data.passengerId;
      if (typeof passengerId !== "string") {
        throw new HttpsError("internal",
          "Yolculuk bilgisi doÄŸrulanamadÄ±.", {reason: "ride_data_invalid"});
      }
      let actorType: "passenger" | "driver";
      const driverId = typeof data.driverId === "string" ? data.driverId : null;
      if (passengerId === actorUid) {
        actorType = "passenger";
        if (input.reasonCode !== "passenger_cancelled") {
          throw new HttpsError("failed-precondition", "Ä°ptal nedeni uygun deÄŸildir.",
            {reason: "cancellation_actor_mismatch"});
        }
      } else {
        const authenticatedDriverId = await loadApprovedDriverIdInTransaction(
          firestore, actorUid, transaction);
        if (driverId !== authenticatedDriverId) {
          throw new HttpsError("permission-denied", "Bu yolculuÄŸu iptal edemezsiniz.",
            {reason: "ride_participant_required"});
        }
        actorType = "driver";
        if (input.reasonCode !== "driver_cancelled") {
          throw new HttpsError("failed-precondition", "Ä°ptal nedeni uygun deÄŸildir.",
            {reason: "cancellation_actor_mismatch"});
        }
      }
      const status = parseRideStatus(data.status);
      const version = requirePositiveVersion(data.version);
      if (version !== input.expectedVersion) {
        throw new HttpsError("failed-precondition", "Yolculuk bilgisi gÃ¼ncel deÄŸil.",
          {reason: "stale_ride_version"});
      }
      if (actorType === "passenger") requirePassengerCancellation(status);
      else requireDriverCancellation(status);
      const passengerActiveRef = firestore.collection("passengerActiveRides")
        .doc(passengerId);
      const passengerPointer = await transaction.get(passengerActiveRef);
      if (!passengerPointer.exists || passengerPointer.get("rideId") !== ride.id) {
        throw new HttpsError("failed-precondition", "Aktif yolculuk bilgisi tutarsÄ±z.",
          {reason: "active_ride_pointer_inconsistent"});
      }
      const driverActiveRef = driverId ?
        firestore.collection("driverActiveRides").doc(driverId) : null;
      const driverPointer = driverActiveRef ? await transaction.get(driverActiveRef) : null;
      if (driverPointer?.exists && driverPointer.get("rideId") !== ride.id) {
        throw new HttpsError("failed-precondition", "Aktif yolculuk bilgisi tutarsÄ±z.",
          {reason: "active_ride_pointer_inconsistent"});
      }
      const nextVersion = version + 1;
      const result = {rideId: ride.id, status: "cancelled",
        version: nextVersion, cancelledAtMillis: now.toMillis(),
        cancelledBy: actorType, terminalReason: input.reasonCode};
      transaction.update(rideRef, {status: "cancelled", version: nextVersion,
        updatedAt: now, cancelledAt: now, cancelledBy: actorType,
        terminalReason: input.reasonCode});
      transaction.delete(passengerActiveRef);
      if (driverActiveRef && driverPointer?.exists) transaction.delete(driverActiveRef);
      transaction.create(rideRef.collection("events").doc(
        `rideCancelled_${operationRef.id.slice(0, 32)}`),
      {type: "rideCancelled", fromStatus: status, toStatus: "cancelled",
        actorType, actorId: actorUid, createdAt: now});
      transaction.create(operationRef, {actorUid,
        callableName: "cancelRide", requestDigest: digest,
        status: "completed", result, createdAt: now, updatedAt: now});
      return result;
    });
  } catch (error: unknown) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("unavailable", "Yolculuk iptal edilemedi.",
      {reason: "ride_persistence_failed"});
  }
};

export const cancelRideForPassenger = cancelRideForActor;

type DriverTransitionConfig = {
  callableName: "markDriverArrived" | "startRide" | "completeRide";
  fromStatus: "driverEnRoute" | "driverArrived" | "inProgress";
  toStatus: "driverArrived" | "inProgress" | "completed";
  timestampField: "arrivedAt" | "startedAt" | "completedAt";
  eventType: "rideDriverArrived" | "rideStarted" | "rideCompleted";
  terminal: boolean;
};

const replayOperation = (data: Record<string, unknown>, digest: string) => {
  if (data.requestDigest !== digest) {
    throw new HttpsError("failed-precondition", "Ä°stek daha Ã¶nce farklÄ± veriyle kullanÄ±ldÄ±.",
      {reason: "idempotency_payload_mismatch"});
  }
  if (data.status === "completed" && typeof data.result === "object" &&
      data.result !== null) return data.result as Record<string, unknown>;
  throw new HttpsError("aborted", "Yolculuk iÅŸlemi tamamlanamadÄ±.",
    {reason: "ride_operation_in_progress"});
};

export const acceptRideForDriver = async (
  dependencies: Pick<RideLifecycleDependencies, "firestore" | "now">,
  actorUid: string, rawInput: unknown,
): Promise<Record<string, unknown>> => {
  const input = validateRideMutationPayload(rawInput);
  const {firestore} = dependencies;
  const operationRef = firestore.collection("rideOperations")
    .doc(rideOperationId(actorUid, "acceptRide", input.requestId));
  const digest = rideRequestDigest("acceptRide", input);
  const existing = await operationRef.get();
  if (existing.exists) return replayOperation(existing.data() ?? {}, digest);
  const driverId = await loadApprovedDriverId(firestore, actorUid);
  const rideRef = firestore.collection("rides").doc(input.rideId);
  const driverActiveRef = firestore.collection("driverActiveRides").doc(driverId);
  const now = dependencies.now?.() ?? Timestamp.now();
  try {
    return await firestore.runTransaction(async (transaction) => {
      const [operation, verifiedDriverId, ride, driverPointer] = await Promise.all([
        transaction.get(operationRef),
        loadApprovedDriverIdInTransaction(firestore, actorUid, transaction),
        transaction.get(rideRef), transaction.get(driverActiveRef),
      ]);
      if (verifiedDriverId !== driverId) {
        throw new HttpsError("failed-precondition",
          "SÃ¼rÃ¼cÃ¼ profili deÄŸiÅŸti.", {reason: "driver_identity_changed"});
      }
      if (operation.exists) return replayOperation(operation.data() ?? {}, digest);
      if (!ride.exists) {
        throw new HttpsError("not-found", "Yolculuk bulunamadÄ±.",
          {reason: "ride_not_found"});
      }
      const data = ride.data() ?? {};
      const version = requirePositiveVersion(data.version);
      if (version !== input.expectedVersion) {
        throw new HttpsError("failed-precondition",
          "Yolculuk bilgisi gÃ¼ncel deÄŸil.", {reason: "stale_ride_version"});
      }
      requireRideTransition(parseRideStatus(data.status), "matching");
      if (data.driverId !== null) {
        throw new HttpsError("failed-precondition",
          "Yolculuk daha Ã¶nce atandÄ±.", {reason: "ride_already_assigned"});
      }
      if (driverPointer.exists) {
        throw new HttpsError("already-exists",
          "SÃ¼rÃ¼cÃ¼nÃ¼n aktif yolculuÄŸu var.", {reason: "driver_active_ride_exists"});
      }
      const matchAuthority =
        await requireRideMatchOfferAuthority({
          firestore,
          transaction,
          driverId,
          rideId: ride.id,
          rideVersion: version,
          now,
        });
      const passengerId = data.passengerId;
      if (typeof passengerId !== "string") {
        throw new HttpsError("internal",
          "Yolculuk bilgisi doÄŸrulanamadÄ±.", {reason: "ride_data_invalid"});
      }
      const passengerRef = firestore.collection("passengerActiveRides").doc(passengerId);
      const passengerPointer = await transaction.get(passengerRef);
      if (!passengerPointer.exists || passengerPointer.get("rideId") !== ride.id) {
        throw new HttpsError("failed-precondition", "Aktif yolculuk bilgisi tutarsÄ±z.",
          {reason: "active_ride_pointer_inconsistent"});
      }
      transaction.update(
        matchAuthority.offerRef,
        {
          status: "consumed",
          consumedAt: now,
        },
      );
      const nextVersion = version + 1;
      const result = {rideId: ride.id, status: "driverEnRoute",
        version: nextVersion, updatedAtMillis: now.toMillis()};
      transaction.update(rideRef, {driverId, status: "driverEnRoute",
        version: nextVersion, acceptedAt: now, driverEnRouteAt: now, updatedAt: now});
      transaction.update(passengerRef, {status: "driverEnRoute", updatedAt: now});
      transaction.create(driverActiveRef,
        {rideId: ride.id, status: "driverEnRoute", updatedAt: now});
      transaction.create(rideRef.collection("events").doc(
        `rideDriverAccepted_${operationRef.id.slice(0, 32)}`),
      {type: "rideDriverAccepted", fromStatus: "matching", toStatus: "driverEnRoute",
        actorType: "driver", actorId: actorUid, createdAt: now});
      transaction.create(operationRef, {actorUid, callableName: "acceptRide",
        requestDigest: digest, status: "completed", result, createdAt: now, updatedAt: now});
      return result;
    });
  } catch (error: unknown) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("unavailable", "Yolculuk kabul edilemedi.",
      {reason: "ride_persistence_failed"});
  }
};

export const transitionRideForDriver = async (
  dependencies: Pick<RideLifecycleDependencies, "firestore" | "now">,
  actorUid: string, rawInput: unknown, config: DriverTransitionConfig,
): Promise<Record<string, unknown>> => {
  const input = validateRideMutationPayload(rawInput);
  const {firestore} = dependencies;
  const operationRef = firestore.collection("rideOperations")
    .doc(rideOperationId(actorUid, config.callableName, input.requestId));
  const digest = rideRequestDigest(config.callableName, input);
  const existing = await operationRef.get();
  if (existing.exists) return replayOperation(existing.data() ?? {}, digest);
  const driverId = await loadApprovedDriverId(firestore, actorUid);
  const rideRef = firestore.collection("rides").doc(input.rideId);
  const driverRef = firestore.collection("driverActiveRides").doc(driverId);
  const now = dependencies.now?.() ?? Timestamp.now();
  try {
    return await firestore.runTransaction(async (transaction) => {
      const [operation, verifiedDriverId, ride, driverPointer] = await Promise.all([
        transaction.get(operationRef),
        loadApprovedDriverIdInTransaction(firestore, actorUid, transaction),
        transaction.get(rideRef), transaction.get(driverRef),
      ]);
      if (verifiedDriverId !== driverId) {
        throw new HttpsError("failed-precondition",
          "SÃ¼rÃ¼cÃ¼ profili deÄŸiÅŸti.", {reason: "driver_identity_changed"});
      }
      if (operation.exists) return replayOperation(operation.data() ?? {}, digest);
      if (!ride.exists) {
        throw new HttpsError("not-found", "Yolculuk bulunamadÄ±.",
          {reason: "ride_not_found"});
      }
      const data = ride.data() ?? {};
      if (data.driverId !== driverId) {
        throw new HttpsError("permission-denied",
          "AtanmÄ±ÅŸ sÃ¼rÃ¼cÃ¼ gereklidir.", {reason: "assigned_driver_required"});
      }
      const version = requirePositiveVersion(data.version);
      if (version !== input.expectedVersion) {
        throw new HttpsError("failed-precondition",
          "Yolculuk bilgisi gÃ¼ncel deÄŸil.", {reason: "stale_ride_version"});
      }
      requireRideTransition(parseRideStatus(data.status), config.fromStatus);
      const passengerId = data.passengerId;
      if (typeof passengerId !== "string") {
        throw new HttpsError("internal",
          "Yolculuk bilgisi doÄŸrulanamadÄ±.", {reason: "ride_data_invalid"});
      }
      const passengerRef = firestore.collection("passengerActiveRides").doc(passengerId);
      const passengerPointer = await transaction.get(passengerRef);
      if (!driverPointer.exists || driverPointer.get("rideId") !== ride.id ||
          !passengerPointer.exists || passengerPointer.get("rideId") !== ride.id) {
        throw new HttpsError("failed-precondition", "Aktif yolculuk bilgisi tutarsÄ±z.",
          {reason: "active_ride_pointer_inconsistent"});
      }
      const nextVersion = version + 1;
      const result = {rideId: ride.id, status: config.toStatus,
        version: nextVersion, updatedAtMillis: now.toMillis()};
      transaction.update(rideRef, {status: config.toStatus, version: nextVersion,
        updatedAt: now, [config.timestampField]: now});
      if (config.terminal) {
        transaction.delete(passengerRef);
        transaction.delete(driverRef);
      } else {
        transaction.update(passengerRef, {status: config.toStatus, updatedAt: now});
        transaction.update(driverRef, {status: config.toStatus, updatedAt: now});
      }
      transaction.create(rideRef.collection("events").doc(
        `${config.eventType}_${operationRef.id.slice(0, 32)}`),
      {type: config.eventType, fromStatus: config.fromStatus, toStatus: config.toStatus,
        actorType: "driver", actorId: actorUid, createdAt: now});
      transaction.create(operationRef, {actorUid, callableName: config.callableName,
        requestDigest: digest, status: "completed", result, createdAt: now, updatedAt: now});
      return result;
    });
  } catch (error: unknown) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("unavailable", "Yolculuk durumu gÃ¼ncellenemedi.",
      {reason: "ride_persistence_failed"});
  }
};

export const DRIVER_TRANSITIONS = {
  markDriverArrived: {callableName: "markDriverArrived", fromStatus: "driverEnRoute",
    toStatus: "driverArrived", timestampField: "arrivedAt",
    eventType: "rideDriverArrived", terminal: false},
  startRide: {callableName: "startRide", fromStatus: "driverArrived",
    toStatus: "inProgress", timestampField: "startedAt",
    eventType: "rideStarted", terminal: false},
  completeRide: {callableName: "completeRide", fromStatus: "inProgress",
    toStatus: "completed", timestampField: "completedAt",
    eventType: "rideCompleted", terminal: true},
} as const;
