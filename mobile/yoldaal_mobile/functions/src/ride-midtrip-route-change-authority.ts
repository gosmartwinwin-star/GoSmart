/* eslint-disable max-len */
import {v2} from "@googlemaps/routing";
import {
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {
  loadApprovedDriverIdInTransaction,
} from "./ride-driver-identity.js";
import {
  RETURN_ROUTE_MATCH_MAX_DETOUR_METERS,
  RETURN_ROUTE_MATCH_MAX_DETOUR_SECONDS,
} from "./ride-match-offer-helpers.js";
import {
  parseRideStatus,
  requirePositiveVersion,
  rideOperationId,
  rideRequestDigest,
  validateRequestId,
  validateRideLocation,
} from "./ride-lifecycle-helpers.js";
import type {
  RideLocationInput,
} from "./ride-lifecycle-helpers.js";
import {
  computeTrafficAwareDrivingMeasurement,
  computeTrafficAwareDrivingRoute,
  coordinatesEqual,
} from "./route-helpers.js";
import type {
  CoordinateInput,
  TrafficAwareDrivingMeasurement,
  TrafficAwareDrivingRoute,
} from "./route-helpers.js";
import {
  deriveRideSupportParticipant,
} from "./ride-support-authority.js";
import type {
  RideSupportParticipant,
} from "./ride-support-authority.js";

export const PROPOSE_RIDE_DROPOFF_CHANGE_CALLABLE =
  "proposeRideDropoffChange";

export const ACKNOWLEDGE_RIDE_DROPOFF_CHANGE_CALLABLE =
  "acknowledgeRideDropoffChange";

export type RideDropoffChangeProposalStatus =
  | "appliedCompatible"
  | "pendingAcknowledgement"
  | "acceptedIncompatible"
  | "rejectedIncompatible";

export type RideDropoffChangeDecision =
  | "accept"
  | "reject";

export type RideDropoffChangeProposalInput = {
  rideId: string;
  newDropoff: RideLocationInput;
  requestId: string;
};

export type RideDropoffChangeAcknowledgementInput = {
  rideId: string;
  proposalId: string;
  decision: RideDropoffChangeDecision;
  requestId: string;
};

export type MidtripCompatibilityMeasurement = {
  pickupDetourMeters: number;
  pickupDetourSeconds: number;
  dropoffDetourMeters: number;
  dropoffDetourSeconds: number;
};

export type RideMidtripRouteChangeDependencies = {
  firestore: Firestore;
  routesClient: v2.RoutesClient;
  now?: () => Timestamp;
  computeMeasurement?: typeof computeTrafficAwareDrivingMeasurement;
  computeRoute?: typeof computeTrafficAwareDrivingRoute;
};

type FailureCode =
  | "invalid-argument"
  | "failed-precondition"
  | "permission-denied"
  | "not-found"
  | "internal"
  | "aborted";

type StoredRideContext = {
  passengerId: string;
  driverId: string;
  version: number;
  returnRouteId: string;
  pickup: RideLocationInput;
  participant: RideSupportParticipant;
  yoldaalRegimeEnded: boolean;
};

type FrozenReturnRoute = {
  driverId: string;
  origin: CoordinateInput;
  destination: CoordinateInput;
};

type StoredProposalRoute = TrafficAwareDrivingRoute & {
  computedAt: Timestamp;
};

const failure = (
  code: FailureCode,
  reason: string,
): HttpsError =>
  new HttpsError(
    code,
    "Rota değişikliği tamamlanamadı.",
    {reason},
  );

const exactObject = (
  value: unknown,
  keys: readonly string[],
  reason: string,
): Record<string, unknown> => {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value)
  ) {
    throw failure(
      "invalid-argument",
      reason,
    );
  }

  const record =
    value as Record<string, unknown>;

  const actual =
    Object.keys(record).sort();

  const expected =
    [...keys].sort();

  if (
    actual.length !== expected.length ||
    actual.some(
      (key, index) =>
        key !== expected[index],
    )
  ) {
    throw failure(
      "invalid-argument",
      reason,
    );
  }

  return record;
};

const validatePathId = (
  value: unknown,
  reason: string,
): string => {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > 128 ||
    !/^[A-Za-z0-9_-]+$/u.test(value)
  ) {
    throw failure(
      "invalid-argument",
      reason,
    );
  }

  return value;
};

export const validateRideDropoffChangeProposalPayload = (
  value: unknown,
): RideDropoffChangeProposalInput => {
  const input =
    exactObject(
      value,
      [
        "rideId",
        "newDropoff",
        "requestId",
      ],
      "invalid_ride_dropoff_change_payload",
    );

  return {
    rideId:
      validatePathId(
        input.rideId,
        "invalid_ride_id",
      ),
    newDropoff:
      validateRideLocation(
        input.newDropoff,
        "invalid_new_dropoff",
      ),
    requestId:
      validateRequestId(
        input.requestId,
      ),
  };
};

export const validateRideDropoffChangeAcknowledgementPayload = (
  value: unknown,
): RideDropoffChangeAcknowledgementInput => {
  const input =
    exactObject(
      value,
      [
        "rideId",
        "proposalId",
        "decision",
        "requestId",
      ],
      "invalid_ride_dropoff_change_ack_payload",
    );

  if (
    input.decision !== "accept" &&
    input.decision !== "reject"
  ) {
    throw failure(
      "invalid-argument",
      "invalid_route_change_decision",
    );
  }

  return {
    rideId:
      validatePathId(
        input.rideId,
        "invalid_ride_id",
      ),
    proposalId:
      validatePathId(
        input.proposalId,
        "invalid_route_change_proposal_id",
      ),
    decision:
      input.decision,
    requestId:
      validateRequestId(
        input.requestId,
      ),
  };
};

export const validateRideDropoffChangeReadPayload = (
  value: unknown,
) => {
  const input =
    exactObject(
      value,
      [
        "rideId",
        "proposalId",
      ],
      "invalid_ride_dropoff_change_read_payload",
    );

  return {
    rideId:
      validatePathId(
        input.rideId,
        "invalid_ride_id",
      ),
    proposalId:
      validatePathId(
        input.proposalId,
        "invalid_route_change_proposal_id",
      ),
  };
};
export const rideDropoffChangeProposalId = (
  actorUid: string,
  requestId: string,
): string =>
  rideOperationId(
    actorUid,
    PROPOSE_RIDE_DROPOFF_CHANGE_CALLABLE,
    requestId,
  );

export const isMidtripRouteChangeCompatible = (
  measurement: MidtripCompatibilityMeasurement,
): boolean =>
  measurement.pickupDetourMeters <=
    RETURN_ROUTE_MATCH_MAX_DETOUR_METERS &&
  measurement.pickupDetourSeconds <=
    RETURN_ROUTE_MATCH_MAX_DETOUR_SECONDS &&
  measurement.dropoffDetourMeters <=
    RETURN_ROUTE_MATCH_MAX_DETOUR_METERS &&
  measurement.dropoffDetourSeconds <=
    RETURN_ROUTE_MATCH_MAX_DETOUR_SECONDS;

const replayOperation = (
  data: Record<string, unknown>,
  digest: string,
): Record<string, unknown> => {
  if (data.requestDigest !== digest) {
    throw failure(
      "failed-precondition",
      "idempotency_payload_mismatch",
    );
  }

  if (
    data.status === "completed" &&
    typeof data.result === "object" &&
    data.result !== null &&
    !Array.isArray(data.result)
  ) {
    return data.result as
      Record<string, unknown>;
  }

  throw failure(
    "aborted",
    "ride_operation_in_progress",
  );
};

const parseCoordinate = (
  value: unknown,
): CoordinateInput | null => {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value)
  ) {
    return null;
  }

  const data =
    value as Record<string, unknown>;

  const latitude =
    data.latitude;

  const longitude =
    data.longitude;

  if (
    typeof latitude !== "number" ||
    !Number.isFinite(latitude) ||
    latitude < -90 ||
    latitude > 90 ||
    typeof longitude !== "number" ||
    !Number.isFinite(longitude) ||
    longitude < -180 ||
    longitude > 180
  ) {
    return null;
  }

  return {
    latitude,
    longitude,
  };
};

const parseStoredRideLocation = (
  value: unknown,
): RideLocationInput => {
  try {
    return validateRideLocation(
      value,
      "ride_data_invalid",
    );
  } catch {
    throw failure(
      "internal",
      "ride_data_invalid",
    );
  }
};

const resolveParticipant = async (
  firestore: Firestore,
  transaction: Transaction,
  actorUid: string,
  passengerId: string,
  driverId: string,
): Promise<RideSupportParticipant> => {
  let approvedDriverId:
    string | null = null;

  if (actorUid !== passengerId) {
    try {
      approvedDriverId =
        await loadApprovedDriverIdInTransaction(
          firestore,
          actorUid,
          transaction,
        );
    } catch (error: unknown) {
      if (
        error instanceof HttpsError &&
        error.code === "permission-denied"
      ) {
        throw failure(
          "permission-denied",
          "ride_dropoff_change_participant_required",
        );
      }

      throw error;
    }
  }

  try {
    return deriveRideSupportParticipant(
      actorUid,
      passengerId,
      driverId,
      approvedDriverId,
    );
  } catch (error: unknown) {
    if (
      error instanceof HttpsError &&
      error.code === "permission-denied"
    ) {
      throw failure(
        "permission-denied",
        "ride_dropoff_change_participant_required",
      );
    }

    throw error;
  }
};

const readRideContext = async (
  firestore: Firestore,
  transaction: Transaction,
  actorUid: string,
  rideId: string,
): Promise<StoredRideContext> => {
  const ride =
    await transaction.get(
      firestore
        .collection("rides")
        .doc(rideId),
    );

  if (!ride.exists) {
    throw failure(
      "not-found",
      "ride_not_found",
    );
  }

  const data =
    ride.data() ?? {};

  if (
    parseRideStatus(
      data.status,
    ) !== "inProgress"
  ) {
    throw failure(
      "failed-precondition",
      "ride_dropoff_change_requires_in_progress",
    );
  }

  const passengerId =
    data.passengerId;

  const driverId =
    data.driverId;

  const returnRouteId =
    data.returnRouteId;

  if (
    typeof passengerId !== "string" ||
    passengerId.length === 0 ||
    typeof driverId !== "string" ||
    driverId.length === 0 ||
    typeof returnRouteId !== "string" ||
    returnRouteId.length === 0
  ) {
    throw failure(
      "failed-precondition",
      "frozen_return_route_context_required",
    );
  }

  const participant =
    await resolveParticipant(
      firestore,
      transaction,
      actorUid,
      passengerId,
      driverId,
    );

  if (
    participant.counterpartyId === null
  ) {
    throw failure(
      "internal",
      "ride_data_invalid",
    );
  }

  return {
    passengerId,
    driverId,
    version:
      requirePositiveVersion(
        data.version,
      ),
    returnRouteId,
    pickup:
      parseStoredRideLocation(
        data.pickup,
      ),
    participant,
    yoldaalRegimeEnded:
      data.yoldaalRegimeEnd !==
        undefined &&
      data.yoldaalRegimeEnd !== null,
  };
};

const readFrozenReturnRoute = async (
  firestore: Firestore,
  transaction: Transaction,
  returnRouteId: string,
  driverId: string,
): Promise<FrozenReturnRoute> => {
  const snapshot =
    await transaction.get(
      firestore
        .collection("driverReturnRoutes")
        .doc(returnRouteId),
    );

  if (!snapshot.exists) {
    throw failure(
      "failed-precondition",
      "frozen_return_route_context_required",
    );
  }

  const data =
    snapshot.data() ?? {};

  const routeDriverId =
    data.driverId;

  const origin =
    parseCoordinate(
      data.origin,
    );

  const destination =
    parseCoordinate(
      data.destination,
    );

  if (
    routeDriverId !== driverId ||
    origin === null ||
    destination === null
  ) {
    throw failure(
      "failed-precondition",
      "frozen_return_route_context_invalid",
    );
  }

  return {
    driverId,
    origin,
    destination,
  };
};

const parseStoredProposalRoute = (
  value: unknown,
): StoredProposalRoute => {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value)
  ) {
    throw failure(
      "internal",
      "route_change_proposal_invalid",
    );
  }

  const data =
    value as Record<string, unknown>;

  const distanceMeters =
    data.distanceMeters;

  const durationSeconds =
    data.durationSeconds;

  const encodedPolyline =
    data.encodedPolyline;

  const computedAt =
    data.computedAt;

  if (
    typeof distanceMeters !== "number" ||
    !Number.isInteger(distanceMeters) ||
    distanceMeters <= 0 ||
    typeof durationSeconds !== "number" ||
    !Number.isInteger(durationSeconds) ||
    durationSeconds <= 0 ||
    typeof encodedPolyline !== "string" ||
    encodedPolyline.length === 0 ||
    !(computedAt instanceof Timestamp)
  ) {
    throw failure(
      "internal",
      "route_change_proposal_invalid",
    );
  }

  return {
    distanceMeters,
    durationSeconds,
    encodedPolyline,
    computedAt,
  };
};

const recoverCommittedOperation = async (
  operationRef:
    FirebaseFirestore.DocumentReference,
  digest: string,
  reason: string,
): Promise<Record<string, unknown>> => {
  const operation =
    await operationRef.get();

  if (operation.exists) {
    return replayOperation(
      operation.data() ?? {},
      digest,
    );
  }

  throw failure(
    "internal",
    reason,
  );
};

export const getPendingRideDropoffChangeProposalForActor = async (
  dependencies: {
    firestore: Firestore;
  },
  actorUid: string,
  rawInput: unknown,
): Promise<Record<string, unknown>> => {
  const input =
    validateRideDropoffChangeReadPayload(
      rawInput,
    );

  const {firestore} =
    dependencies;

  return firestore.runTransaction(
    async (transaction) => {
      const ride =
        await readRideContext(
          firestore,
          transaction,
          actorUid,
          input.rideId,
        );

      const proposal =
        await transaction.get(
          firestore
            .collection("rides")
            .doc(input.rideId)
            .collection("routeChangeProposals")
            .doc(input.proposalId),
        );

      if (!proposal.exists) {
        throw failure(
          "not-found",
          "route_change_proposal_not_found",
        );
      }

      const proposalData =
        proposal.data() ?? {};

      if (
        proposalData.status !==
          "pendingAcknowledgement"
      ) {
        throw failure(
          "failed-precondition",
          "route_change_proposal_already_resolved",
        );
      }

      const counterpartyId =
        proposalData.counterpartyId;

      if (
        typeof counterpartyId !== "string" ||
        counterpartyId.length === 0 ||
        ride.participant.reporterId !==
          counterpartyId
      ) {
        throw failure(
          "permission-denied",
          "route_change_counterparty_required",
        );
      }

      const proposerId =
        proposalData.proposerId;

      if (
        typeof proposerId !== "string" ||
        proposerId.length === 0 ||
        proposerId !==
          ride.participant.counterpartyId
      ) {
        throw failure(
          "internal",
          "route_change_proposal_data_invalid",
        );
      }

      const requestedDropoff =
        parseStoredRideLocation(
          proposalData.requestedDropoff,
        );

      return {
        rideId:
          input.rideId,
        proposalId:
          input.proposalId,
        status:
          "pendingAcknowledgement",
        requestedDropoff,
      };
    },
  );
};
export const proposeRideDropoffChangeForActor = async (
  dependencies:
    RideMidtripRouteChangeDependencies,
  actorUid: string,
  rawInput: unknown,
): Promise<Record<string, unknown>> => {
  const input =
    validateRideDropoffChangeProposalPayload(
      rawInput,
    );

  const {
    firestore,
    routesClient,
  } = dependencies;

  const proposalId =
    rideDropoffChangeProposalId(
      actorUid,
      input.requestId,
    );

  const operationRef =
    firestore
      .collection("rideOperations")
      .doc(proposalId);

  const proposalRef =
    firestore
      .collection("rides")
      .doc(input.rideId)
      .collection("routeChangeProposals")
      .doc(proposalId);

  const digest =
    rideRequestDigest(
      PROPOSE_RIDE_DROPOFF_CHANGE_CALLABLE,
      input,
    );

  const existingOperation =
    await operationRef.get();

  if (existingOperation.exists) {
    return replayOperation(
      existingOperation.data() ?? {},
      digest,
    );
  }

  const preflight =
    await firestore.runTransaction(
      async (transaction) => {
        const ride =
          await readRideContext(
            firestore,
            transaction,
            actorUid,
            input.rideId,
          );

        if (ride.yoldaalRegimeEnded) {
          throw failure(
            "failed-precondition",
            "yoldaal_regime_already_ended",
          );
        }

        if (
          coordinatesEqual(
            ride.pickup,
            input.newDropoff,
          )
        ) {
          throw failure(
            "invalid-argument",
            "identical_ride_locations",
          );
        }

        const frozenRoute =
          await readFrozenReturnRoute(
            firestore,
            transaction,
            ride.returnRouteId,
            ride.driverId,
          );

        return {
          ride,
          frozenRoute,
        };
      },
    );

  const computeMeasurement =
    dependencies.computeMeasurement ??
    computeTrafficAwareDrivingMeasurement;

  const computeRoute =
    dependencies.computeRoute ??
    computeTrafficAwareDrivingRoute;

  let pickupMeasurement:
    TrafficAwareDrivingMeasurement;

  let dropoffMeasurement:
    TrafficAwareDrivingMeasurement;

  let proposedRoute:
    TrafficAwareDrivingRoute;

  try {
    [
      pickupMeasurement,
      dropoffMeasurement,
      proposedRoute,
    ] = await Promise.all([
      computeMeasurement(
        routesClient,
        preflight.frozenRoute.origin,
        preflight.ride.pickup,
      ),
      computeMeasurement(
        routesClient,
        input.newDropoff,
        preflight.frozenRoute.destination,
      ),
      computeRoute(
        routesClient,
        preflight.ride.pickup,
        input.newDropoff,
      ),
    ]);
  } catch (error: unknown) {
    if (error instanceof HttpsError) {
      throw error;
    }

    throw failure(
      "internal",
      "route_change_routing_failed",
    );
  }

  const measurement:
    MidtripCompatibilityMeasurement = {
      pickupDetourMeters:
        pickupMeasurement.distanceMeters,
      pickupDetourSeconds:
        pickupMeasurement.durationSeconds,
      dropoffDetourMeters:
        dropoffMeasurement.distanceMeters,
      dropoffDetourSeconds:
        dropoffMeasurement.durationSeconds,
    };

  const compatible =
    isMidtripRouteChangeCompatible(
      measurement,
    );

  try {
    return await firestore.runTransaction(
      async (transaction) => {
        const operation =
          await transaction.get(
            operationRef,
          );

        if (operation.exists) {
          return replayOperation(
            operation.data() ?? {},
            digest,
          );
        }

        const ride =
          await readRideContext(
            firestore,
            transaction,
            actorUid,
            input.rideId,
          );

        if (ride.yoldaalRegimeEnded) {
          throw failure(
            "failed-precondition",
            "yoldaal_regime_already_ended",
          );
        }

        if (
          ride.version !==
            preflight.ride.version ||
          ride.driverId !==
            preflight.ride.driverId ||
          ride.returnRouteId !==
            preflight.ride.returnRouteId ||
          ride.participant.reporterId !==
            preflight.ride.participant.reporterId ||
          ride.participant.counterpartyId !==
            preflight.ride.participant.counterpartyId ||
          !coordinatesEqual(
            ride.pickup,
            preflight.ride.pickup,
          )
        ) {
          throw failure(
            "failed-precondition",
            "ride_changed_during_route_change_proposal",
          );
        }

        const frozenRoute =
          await readFrozenReturnRoute(
            firestore,
            transaction,
            ride.returnRouteId,
            ride.driverId,
          );

        if (
          !coordinatesEqual(
            frozenRoute.origin,
            preflight.frozenRoute.origin,
          ) ||
          !coordinatesEqual(
            frozenRoute.destination,
            preflight.frozenRoute.destination,
          )
        ) {
          throw failure(
            "failed-precondition",
            "frozen_return_route_context_changed",
          );
        }

        const existingProposal =
          await transaction.get(
            proposalRef,
          );

        if (existingProposal.exists) {
          throw failure(
            "internal",
            "route_change_proposal_operation_inconsistent",
          );
        }

        const now =
          dependencies.now?.() ??
          Timestamp.now();

        const status:
          RideDropoffChangeProposalStatus =
            compatible ?
              "appliedCompatible" :
              "pendingAcknowledgement";

        const nextVersion =
          compatible ?
            ride.version + 1 :
            ride.version;

        const storedRoute = {
          ...proposedRoute,
          computedAt: now,
        };

        const result = {
          rideId:
            input.rideId,
          proposalId,
          status,
          compatible,
          requiresCounterpartyAcknowledgement:
            !compatible,
          version:
            nextVersion,
        };

        if (compatible) {
          transaction.update(
            firestore
              .collection("rides")
              .doc(input.rideId),
            {
              dropoff:
                input.newDropoff,
              route:
                storedRoute,
              version:
                nextVersion,
              updatedAt:
                now,
            },
          );
        }

        transaction.create(
          proposalRef,
          {
            proposerRole:
              ride.participant.role,
            proposerId:
              ride.participant.reporterId,
            counterpartyId:
              ride.participant.counterpartyId,
            driverId:
              ride.driverId,
            returnRouteId:
              ride.returnRouteId,
            requestedDropoff:
              input.newDropoff,
            proposedRoute:
              storedRoute,
            ...measurement,
            compatible,
            status,
            baseRideVersion:
              ride.version,
            createdAt:
              now,
            resolvedAt:
              compatible ?
                now :
                null,
          },
        );

        const eventType =
          compatible ?
            "rideDropoffChangedCompatible" :
            "rideDropoffChangeProposed";

        transaction.create(
          firestore
            .collection("rides")
            .doc(input.rideId)
            .collection("events")
            .doc(
              `${eventType}_${operationRef.id.slice(0, 32)}`,
            ),
          {
            type:
              eventType,
            fromStatus:
              "inProgress",
            toStatus:
              "inProgress",
            actorType:
              ride.participant.role,
            actorId:
              actorUid,
            proposalId,
            createdAt:
              now,
          },
        );

        transaction.create(
          operationRef,
          {
            actorUid,
            callableName:
              PROPOSE_RIDE_DROPOFF_CHANGE_CALLABLE,
            requestDigest:
              digest,
            status:
              "completed",
            result,
            createdAt:
              now,
            updatedAt:
              now,
          },
        );

        return result;
      },
    );
  } catch (error: unknown) {
    if (error instanceof HttpsError) {
      throw error;
    }

    return recoverCommittedOperation(
      operationRef,
      digest,
      "route_change_proposal_failed",
    );
  }
};

export const acknowledgeRideDropoffChangeForActor = async (
  dependencies:
    RideMidtripRouteChangeDependencies,
  actorUid: string,
  rawInput: unknown,
): Promise<Record<string, unknown>> => {
  const input =
    validateRideDropoffChangeAcknowledgementPayload(
      rawInput,
    );

  const {
    firestore,
  } = dependencies;

  const operationId =
    rideOperationId(
      actorUid,
      ACKNOWLEDGE_RIDE_DROPOFF_CHANGE_CALLABLE,
      input.requestId,
    );

  const operationRef =
    firestore
      .collection("rideOperations")
      .doc(operationId);

  const proposalRef =
    firestore
      .collection("rides")
      .doc(input.rideId)
      .collection("routeChangeProposals")
      .doc(input.proposalId);

  const digest =
    rideRequestDigest(
      ACKNOWLEDGE_RIDE_DROPOFF_CHANGE_CALLABLE,
      input,
    );

  const existingOperation =
    await operationRef.get();

  if (existingOperation.exists) {
    return replayOperation(
      existingOperation.data() ?? {},
      digest,
    );
  }

  try {
    return await firestore.runTransaction(
      async (transaction) => {
        const operation =
          await transaction.get(
            operationRef,
          );

        if (operation.exists) {
          return replayOperation(
            operation.data() ?? {},
            digest,
          );
        }

        const ride =
          await readRideContext(
            firestore,
            transaction,
            actorUid,
            input.rideId,
          );

        const proposal =
          await transaction.get(
            proposalRef,
          );

        if (!proposal.exists) {
          throw failure(
            "not-found",
            "route_change_proposal_not_found",
          );
        }

        const proposalData =
          proposal.data() ?? {};

        if (
          proposalData.status !==
            "pendingAcknowledgement"
        ) {
          throw failure(
            "failed-precondition",
            "route_change_proposal_already_resolved",
          );
        }

        const counterpartyId =
          proposalData.counterpartyId;

        if (
          typeof counterpartyId !== "string" ||
          counterpartyId.length === 0 ||
          ride.participant.reporterId !==
            counterpartyId
        ) {
          throw failure(
            "permission-denied",
            "route_change_counterparty_required",
          );
        }

        const baseRideVersion =
          requirePositiveVersion(
            proposalData.baseRideVersion,
          );

        const requestedDropoff =
          parseStoredRideLocation(
            proposalData.requestedDropoff,
          );

        const proposedRoute =
          parseStoredProposalRoute(
            proposalData.proposedRoute,
          );

        const now =
          dependencies.now?.() ??
          Timestamp.now();

        const accepted =
          input.decision === "accept";

        if (accepted) {
          if (ride.yoldaalRegimeEnded) {
            throw failure(
              "failed-precondition",
              "yoldaal_regime_already_ended",
            );
          }

          if (
            ride.version !==
              baseRideVersion
          ) {
            throw failure(
              "failed-precondition",
              "route_change_proposal_stale",
            );
          }
        }

        const resolvedStatus:
          RideDropoffChangeProposalStatus =
            accepted ?
              "acceptedIncompatible" :
              "rejectedIncompatible";

        const nextVersion =
          accepted ?
            ride.version + 1 :
            ride.version;

        if (accepted) {
          transaction.update(
            firestore
              .collection("rides")
              .doc(input.rideId),
            {
              dropoff:
                requestedDropoff,
              route:
                proposedRoute,
              version:
                nextVersion,
              updatedAt:
                now,
              yoldaalRegimeEnd: {
                reason:
                  "incompatible_midtrip_dropoff_change",
                proposalId:
                  input.proposalId,
                endedAt:
                  now,
              },
            },
          );
        }

        transaction.update(
          proposalRef,
          {
            status:
              resolvedStatus,
            resolvedAt:
              now,
          },
        );

        const eventType =
          accepted ?
            "rideDropoffChangeAcceptedIncompatible" :
            "rideDropoffChangeRejectedIncompatible";

        transaction.create(
          firestore
            .collection("rides")
            .doc(input.rideId)
            .collection("events")
            .doc(
              `${eventType}_${operationRef.id.slice(0, 32)}`,
            ),
          {
            type:
              eventType,
            fromStatus:
              "inProgress",
            toStatus:
              "inProgress",
            actorType:
              ride.participant.role,
            actorId:
              actorUid,
            proposalId:
              input.proposalId,
            createdAt:
              now,
          },
        );

        const result = {
          rideId:
            input.rideId,
          proposalId:
            input.proposalId,
          status:
            resolvedStatus,
          decision:
            input.decision,
          version:
            nextVersion,
          yoldaalRegimeEnded:
            accepted,
        };

        transaction.create(
          operationRef,
          {
            actorUid,
            callableName:
              ACKNOWLEDGE_RIDE_DROPOFF_CHANGE_CALLABLE,
            requestDigest:
              digest,
            status:
              "completed",
            result,
            createdAt:
              now,
            updatedAt:
              now,
          },
        );

        return result;
      },
    );
  } catch (error: unknown) {
    if (error instanceof HttpsError) {
      throw error;
    }

    return recoverCommittedOperation(
      operationRef,
      digest,
      "route_change_acknowledgement_failed",
    );
  }
};
