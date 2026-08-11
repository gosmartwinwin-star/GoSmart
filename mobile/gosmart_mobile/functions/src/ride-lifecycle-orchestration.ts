/* eslint-disable max-len */
import {Firestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  buildInitialRide,
  requirePassengerCancellation,
  requirePositiveVersion,
  RideRoute,
  rideOperationId,
  rideRequestDigest,
  validateCancelRidePayload,
  validateCreateRideRequestPayload,
  parseRideStatus,
} from "./ride-lifecycle-helpers.js";

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

export const cancelRideForPassenger = async (
  dependencies: Pick<RideLifecycleDependencies, "firestore" | "now">,
  passengerId: string,
  rawInput: unknown,
): Promise<Record<string, unknown>> => {
  const input = validateCancelRidePayload(rawInput);
  const {firestore} = dependencies;
  const rideRef = firestore.collection("rides").doc(input.rideId);
  const passengerActiveRef = firestore.collection("passengerActiveRides").doc(passengerId);
  const operationRef = firestore.collection("rideOperations")
    .doc(rideOperationId(passengerId, "cancelRide", input.requestId));
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
      if (data.passengerId !== passengerId) {
        throw new HttpsError("permission-denied", "Bu yolculuÄŸu iptal edemezsiniz.",
          {reason: "ride_participant_required"});
      }
      const status = parseRideStatus(data.status);
      const version = requirePositiveVersion(data.version);
      if (version !== input.expectedVersion) {
        throw new HttpsError("failed-precondition", "Yolculuk bilgisi gÃ¼ncel deÄŸil.",
          {reason: "stale_ride_version"});
      }
      requirePassengerCancellation(status);
      const passengerPointer = await transaction.get(passengerActiveRef);
      if (!passengerPointer.exists || passengerPointer.get("rideId") !== ride.id) {
        throw new HttpsError("failed-precondition", "Aktif yolculuk bilgisi tutarsÄ±z.",
          {reason: "active_ride_pointer_inconsistent"});
      }
      const driverId = data.driverId;
      const driverActiveRef = typeof driverId === "string" ?
        firestore.collection("driverActiveRides").doc(driverId) : null;
      const driverPointer = driverActiveRef ? await transaction.get(driverActiveRef) : null;
      if (driverPointer?.exists && driverPointer.get("rideId") !== ride.id) {
        throw new HttpsError("failed-precondition", "Aktif yolculuk bilgisi tutarsÄ±z.",
          {reason: "active_ride_pointer_inconsistent"});
      }
      const nextVersion = version + 1;
      const result = {rideId: ride.id, status: "cancelled",
        version: nextVersion, cancelledAtMillis: now.toMillis(),
        cancelledBy: "passenger", terminalReason: input.reasonCode};
      transaction.update(rideRef, {status: "cancelled", version: nextVersion,
        updatedAt: now, cancelledAt: now, cancelledBy: "passenger",
        terminalReason: input.reasonCode});
      transaction.delete(passengerActiveRef);
      if (driverActiveRef && driverPointer?.exists) transaction.delete(driverActiveRef);
      transaction.create(rideRef.collection("events").doc(
        `rideCancelled_${operationRef.id.slice(0, 32)}`),
      {type: "rideCancelled", fromStatus: status, toStatus: "cancelled",
        actorType: "passenger", actorId: passengerId, createdAt: now});
      transaction.create(operationRef, {actorUid: passengerId,
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
