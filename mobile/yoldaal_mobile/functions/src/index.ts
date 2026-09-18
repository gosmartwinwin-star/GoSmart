import {requestAccountDeletionForUser} from "./account-deletion-request-authority.js";
import {protos, v2} from "@googlemaps/routing";
import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldPath, getFirestore, Timestamp} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {randomUUID} from "node:crypto";
import {
  HttpsError,
  onCall,
  onRequest,
} from "firebase-functions/v2/https";
import {getFunctions} from "firebase-admin/functions";
import {getMessaging} from "firebase-admin/messaging";
import {
  onDocumentCreated,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";
import {onTaskDispatched} from "firebase-functions/v2/tasks";
import * as logger from "firebase-functions/logger";
import {defineSecret} from "firebase-functions/params";
import {
  CoordinateInput,
  computeTrafficAwareDrivingMeasurement,
  computeTrafficAwareDrivingRoute,
  coordinatesEqual,
  durationToSeconds,
  validateCoordinate,
  validateDirection,
  validateRouteIndex,
} from "./route-helpers.js";
import {
  requireExactKeys,
  validateProfileStatus,
  validateRouteValidity,
} from "./driver-access-helpers.js";
import {requireDriverAccess} from "./driver-access-authority.js";
import {
  buildStagingDocumentPath,
  buildSubmissionDocumentPath,
  determineSubmissionTransition,
  getRequiredDocumentTypes,
  validateApplicationPayload,
  validateDocumentMetadata,
  validateVerifiedPhone,
} from "./driver-application-helpers.js";
import {requireYoldaAlAdmin} from "./admin-authorization-helpers.js";
import {
  buildReviewAuditEvent,
  determineDocumentReviewTransition,
  hasAllRequiredApprovedDocuments,
  validateApplicationReviewPayload,
  validateCurrentApplicationVersion,
  validateCurrentDocumentMetadata,
  validateDocumentReviewPayload,
} from "./driver-application-review-helpers.js";
import {
  buildNextCursor,
  buildReviewContext,
  calculateReviewUrlExpiry,
  mapApplicationReviewDetails,
  mapApplicationSummary,
  reviewStateQuery,
  validateApplicationDetailsPayload,
  validateApplicationListPayload,
  validateDocumentReviewUrlPayload,
} from "./driver-application-admin-read-helpers.js";
import {
  buildReviewEventsPage,
  validateReviewEventsPayload,
} from "./driver-application-review-events-helpers.js";
import {
  buildPublicDriverApplicationStatus,
  operationDocumentId,
  requestDigest,
  validateCurrentDocuments,
  validateResubmissionEligibility,
  validateResubmissionPayload,
} from "./driver-application-resubmission-helpers.js";
import {
  parseRideStatus,
  serializeActiveRide,
  TERMINAL_RIDE_STATUSES,
} from "./ride-lifecycle-helpers.js";
import {
  acceptRideForDriver,
  cancelRideForActor,
  createRideRequestForPassenger,
  DRIVER_TRANSITIONS,
  transitionRideForDriver,
} from "./ride-lifecycle-orchestration.js";
import {loadApprovedDriverId} from "./ride-driver-identity.js";
import {publishDriverLivePresence} from "./driver-live-presence-authority.js";
import {
  registerDriverPushTarget as registerDriverPushTargetAuthority,
} from "./driver-push-target-authority.js";
import {
  registerPassengerPushTarget as registerPassengerPushTargetAuthority,
} from "./passenger-push-target-authority.js";
import {
  getActiveRideDriverTrackingForActor,
} from "./ride-live-tracking-authority.js";
import {getRideLiveTrackingEta} from "./ride-live-tracking-eta.js";
import {
  recoverActiveReturnRoute,
} from "./active-return-route-recovery.js";
import {getRideHistoryForActor} from "./ride-history-service.js";
import {
  getRideRatingStatusForActor,
  submitRideRatingForActor,
} from "./ride-rating-authority.js";
import {
  createRideSupportCaseForActor,
} from "./ride-support-authority.js";
import {
  createActiveRideSupportCaseForActor,
} from "./ride-active-support-authority.js";
import {
  listRideChatMessagesForActor,
  sendRideChatMessageForActor,
} from "./ride-chat-authority.js";
import {
  dispatchRideChatPushHint,
} from "./ride-chat-push-hint-authority.js";
import {
  acknowledgeRideDropoffChangeForActor,
  getPendingRideDropoffChangeProposalForActor,
  proposeRideDropoffChangeForActor,
} from "./ride-midtrip-route-change-authority.js";
import {
  resolvePlace as resolvePlaceWithPlacesApi,
  searchPlaces as searchPlacesWithPlacesApi,
} from "./place-search-service.js";
import {
  discoverRideMatchOffersForDriver,
} from "./ride-match-offer-discovery.js";
import type {
  RideMatchDeviationInput,
  RideMatchDeviationMeasurement,
} from "./ride-match-offer-discovery.js";

import {
  discoverNearbyPassengerDriversForPassenger,
} from "./nearby-passenger-discovery-authority.js";
import type {
  NearbyPassengerDiscoveryMeasurementInput,
} from "./nearby-passenger-discovery-authority.js";
import {
  RETURN_ROUTE_MATCH_MAX_DETOUR_METERS,
} from "./ride-match-offer-helpers.js";
import type {
  RideMatchMeasurement,
} from "./ride-match-offer-helpers.js";
import {
  decodeEncodedPolyline,
  geoDistanceMeters,
  locateRouteAnchors,
  routeAnchorDirectionCompatible,
} from "./ride-route-geometry.js";
import {
  buildReturnRouteCorridorPrefixes,
} from "./return-route-corridor-prefix-helpers.js";
import {
  RIDE_OFFER_HINT_TASK_MAX_ATTEMPTS,
  RIDE_OFFER_HINT_TASK_MAX_BACKOFF_SECONDS,
  RIDE_OFFER_HINT_TASK_MAX_CONCURRENT_DISPATCHES,
  RIDE_OFFER_HINT_TASK_MAX_DISPATCHES_PER_SECOND,
  RIDE_OFFER_HINT_TASK_MIN_BACKOFF_SECONDS,
  RIDE_OFFER_HINT_TASK_TIMEOUT_SECONDS,
} from "./ride-background-offer-dispatch-policy.js";
import {
  enqueueRideBackgroundOfferInitialDispatch,
} from "./ride-background-offer-dispatch-enqueue-authority.js";
import {
  executeRideOfferHintPageTask,
} from "./ride-background-offer-dispatch-task-worker-authority.js";

const RETURN_ROUTE_CORRIDOR_INITIAL_PRECISION = 4;
const RETURN_ROUTE_CORRIDOR_MAX_PREFIX_COUNT = 16;


type ComputeRouteInput = {
  origin: CoordinateInput;
  destination: CoordinateInput;
};

type ComputeRouteDeviationInput = {
  pickupAnchor: CoordinateInput;
  pickup: CoordinateInput;
  dropoff: CoordinateInput;
  dropoffAnchor: CoordinateInput;
  pickupRouteIndex: number;
  dropoffRouteIndex: number;
};

type PublishReturnRouteInput = {
  origin: CoordinateInput;
  destination: CoordinateInput;
  validForSeconds: number;
};

type SubmitDriverApplicationInput = {
  fullName: string;
  email?: string;
  driverTaxiStandName?: string;
  driverTaxiStandAddress?: string;
  workType: "vehicleOwner" | "employedDriver" | "shiftDriver";
  vehiclePlate: string;
  vehicleBrand: string;
  vehicleModel: string;
  vehicleModelYear: number;
  registrationOwnerType: "applicant" | "otherIndividual" | "company";
  hasVehicleUseAuthorization: boolean;
  vehicleTaxiStandName?: string;
  informationAccuracyAccepted: boolean;
  documentValidityNotificationAccepted: boolean;
  documentProcessingNoticeAccepted: boolean;
  kvkkNoticeAccepted: boolean;
  termsAccepted: boolean;
  marketingConsent?: boolean;
};

type ResubmitDriverApplicationInput = {
  expectedSubmissionVersion: number;
  requestId: string;
};

const googlePlacesApiKey = defineSecret(
  "GOOGLE_PLACES_API_KEY",
);


const routesClient = new v2.RoutesClient();
const routing = protos.google.maps.routing.v2;
const firestore = getFirestore(getApps()[0] ?? initializeApp());
const auth = getAuth();
const storageBucket = getStorage().bucket();

const toWaypoint = (coordinate: CoordinateInput) => ({
  location: {
    latLng: {
      latitude: coordinate.latitude,
      longitude: coordinate.longitude,
    },
  },
});

const computeDrivingMeasurement = (
  origin: CoordinateInput,
  destination: CoordinateInput,
): Promise<{
  distanceMeters: number;
  durationSeconds: number;
}> =>
  computeTrafficAwareDrivingMeasurement(
    routesClient,
    origin,
    destination,
  );

const computeRideMatchDeviation = async (
  input: RideMatchDeviationInput,
): Promise<RideMatchDeviationMeasurement> => {
  const [
    pickupMeasurement,
    dropoffMeasurement,
  ] = await Promise.all([
    computeDrivingMeasurement(
      input.pickupAnchor,
      input.pickup,
    ),
    computeDrivingMeasurement(
      input.dropoff,
      input.dropoffAnchor,
    ),
  ]);

  return {
    pickupDetourMeters:
      pickupMeasurement.distanceMeters,
    pickupDetourSeconds:
      pickupMeasurement.durationSeconds,
    dropoffDetourMeters:
      dropoffMeasurement.distanceMeters,
    dropoffDetourSeconds:
      dropoffMeasurement.durationSeconds,
  };
};

const computeNearbyPassengerCompatibility = async (
  input: NearbyPassengerDiscoveryMeasurementInput,
): Promise<RideMatchMeasurement | null> => {
  if (
    typeof input.returnRouteData !== "object" ||
    input.returnRouteData === null ||
    Array.isArray(input.returnRouteData)
  ) {
    return null;
  }

  const returnRoute =
    input.returnRouteData as Record<string, unknown>;

  const encodedPolyline =
    returnRoute.encodedPolyline;

  if (
    typeof encodedPolyline !== "string" ||
    encodedPolyline.length === 0
  ) {
    return null;
  }

  let origin: CoordinateInput;
  let destination: CoordinateInput;
  let anchors:
    ReturnType<typeof locateRouteAnchors>;

  try {
    origin =
      validateCoordinate(
        returnRoute.origin,
      );

    destination =
      validateCoordinate(
        returnRoute.destination,
      );

    const routePoints =
      decodeEncodedPolyline(
        encodedPolyline,
      );

    anchors =
      locateRouteAnchors(
        routePoints,
        input.passengerPickup,
        input.passengerDropoff,
      );
  } catch (_error: unknown) {
    return null;
  }

  if (
    !routeAnchorDirectionCompatible(
      anchors,
    )
  ) {
    return null;
  }

  if (
    geoDistanceMeters(
      origin,
      input.passengerPickup,
    ) >
      RETURN_ROUTE_MATCH_MAX_DETOUR_METERS ||
    geoDistanceMeters(
      input.passengerDropoff,
      destination,
    ) >
      RETURN_ROUTE_MATCH_MAX_DETOUR_METERS
  ) {
    return null;
  }

  const deviation =
    await computeRideMatchDeviation({
      pickupAnchor:
        origin,
      pickup:
        input.passengerPickup,
      dropoff:
        input.passengerDropoff,
      dropoffAnchor:
        destination,
      pickupRouteIndex:
        anchors.pickupRouteIndex,
      dropoffRouteIndex:
        anchors.dropoffRouteIndex,
    });

  return {
    pickupRouteIndex:
      anchors.pickupRouteIndex,
    dropoffRouteIndex:
      anchors.dropoffRouteIndex,
    pickupDetourMeters:
      deviation.pickupDetourMeters,
    pickupDetourSeconds:
      deviation.pickupDetourSeconds,
    dropoffDetourMeters:
      deviation.dropoffDetourMeters,
    dropoffDetourSeconds:
      deviation.dropoffDetourSeconds,
  };
};


const safePrecondition = (reason: string) => new HttpsError(
  "failed-precondition",
  "Sürücü erişim koşulları sağlanmıyor.",
  {reason},
);

const loadDriverAccess = async (
  uid: string,
  now: Timestamp,
  getDocuments: (query: FirebaseFirestore.Query) =>
    Promise<FirebaseFirestore.QuerySnapshot>,
): Promise<string> => {
  const profileQuery = firestore.collection("driverProfiles")
    .where("authUserId", "==", uid)
    .limit(2);
  const profiles = await getDocuments(profileQuery);
  if (profiles.empty) throw safePrecondition("driver_profile_required");
  if (profiles.size > 1) throw safePrecondition("duplicate_driver_profile");

  const profile = profiles.docs[0];
  validateProfileStatus(profile.get("status"));

  await requireDriverAccess({
    firestore,
    driverId: profile.id,
    now,
    failure: safePrecondition,
    getDocuments,
  });
  return profile.id;
};

const validatePublishInput = (value: unknown): PublishReturnRouteInput => {
  const input = requireExactKeys(value, [
    "origin", "destination", "validForSeconds",
  ]);
  try {
    requireExactKeys(input.origin, ["latitude", "longitude"]);
    requireExactKeys(input.destination, ["latitude", "longitude"]);
    const origin = validateCoordinate(input.origin);
    const destination = validateCoordinate(input.destination);
    if (coordinatesEqual(origin, destination)) throw new Error();
    return {
      origin,
      destination,
      validForSeconds: validateRouteValidity(input.validForSeconds),
    };
  } catch (error: unknown) {
    if (
      error instanceof HttpsError &&
      (error.details as {reason?: string} | undefined)?.reason ===
        "invalid_route_validity"
    ) {
      throw error;
    }
    throw new HttpsError(
      "invalid-argument",
      "Dönüş rotası koordinatları uygun değildir.",
      {reason: "invalid_route_coordinates"},
    );
  }
};

const computePublishedRoute = (
  origin: CoordinateInput,
  destination: CoordinateInput,
): Promise<{
  distanceMeters: number;
  durationSeconds: number;
  encodedPolyline: string;
}> =>
  computeTrafficAwareDrivingRoute(
    routesClient,
    origin,
    destination,
  );

export const healthCheck = onRequest(
  {
    region: "europe-west1",
  },
  (request, response) => {
    logger.info("YoldaAl functions health check", {
      method: request.method,
    });
    response.status(200).json({
      success: true,
      service: "yoldaal-functions",
    });
  },
);

export const computeRoute = onCall<ComputeRouteInput>(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
    minInstances: 0,
    maxInstances: 3,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Rota hesaplamak için giriş yapmalısınız.",
      );
    }

    try {
      const origin = validateCoordinate(request.data?.origin);
      const destination = validateCoordinate(request.data?.destination);

      if (coordinatesEqual(origin, destination)) {
        throw new HttpsError(
          "invalid-argument",
          "Başlangıç ve varış noktaları aynı olamaz.",
        );
      }

      const [response] = await routesClient.computeRoutes(
        {
          origin: toWaypoint(origin),
          destination: toWaypoint(destination),
          travelMode: routing.RouteTravelMode.DRIVE,
          routingPreference: routing.RoutingPreference.TRAFFIC_AWARE,
          computeAlternativeRoutes: false,
          polylineQuality: routing.PolylineQuality.OVERVIEW,
          polylineEncoding: routing.PolylineEncoding.ENCODED_POLYLINE,
          languageCode: "tr-TR",
          regionCode: "TR",
          units: routing.Units.METRIC,
        },
        {
          otherArgs: {
            headers: {
              "X-Goog-FieldMask":
                "routes.duration,routes.distanceMeters," +
                "routes.polyline.encodedPolyline",
            },
          },
        },
      );

      const route = response.routes?.[0];
      const encodedPolyline = route?.polyline?.encodedPolyline;
      const distanceMeters = route?.distanceMeters;
      const durationSeconds = durationToSeconds(route?.duration);

      if (
        typeof encodedPolyline !== "string" ||
        encodedPolyline.length === 0 ||
        typeof distanceMeters !== "number" ||
        !Number.isFinite(distanceMeters) ||
        distanceMeters < 0 ||
        durationSeconds === null
      ) {
        throw new HttpsError(
          "not-found",
          "Bu iki nokta arasında uygun bir sürüş rotası bulunamadı.",
        );
      }

      logger.info("YoldaAl route computed");

      return {
        encodedPolyline,
        distanceMeters,
        durationSeconds,
      };
    } catch (error: unknown) {
      if (error instanceof HttpsError) {
        throw error;
      }

      logger.error("Google Routes request failed", {
        errorType: error instanceof Error ? error.name : "UnknownError",
      });

      throw new HttpsError(
        "unavailable",
        "Rota servisine şu anda ulaşılamıyor. Lütfen tekrar deneyin.",
      );
    }
  },
);

export const computeRouteDeviation = onCall<ComputeRouteDeviationInput>(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
    minInstances: 0,
    maxInstances: 3,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Sürüş sapması hesaplamak için giriş yapmalısınız.",
      );
    }

    try {
      const pickupAnchor = validateCoordinate(request.data?.pickupAnchor);
      const pickup = validateCoordinate(request.data?.pickup);
      const dropoff = validateCoordinate(request.data?.dropoff);
      const dropoffAnchor = validateCoordinate(request.data?.dropoffAnchor);
      const pickupRouteIndex = validateRouteIndex(
        request.data?.pickupRouteIndex,
      );
      const dropoffRouteIndex = validateRouteIndex(
        request.data?.dropoffRouteIndex,
      );

      validateDirection(pickupRouteIndex, dropoffRouteIndex);

      const [pickupMeasurement, dropoffMeasurement] = await Promise.all([
        computeDrivingMeasurement(pickupAnchor, pickup),
        computeDrivingMeasurement(dropoff, dropoffAnchor),
      ]);

      logger.info("YoldaAl route deviation computed");

      return {
        pickupDetourMeters: pickupMeasurement.distanceMeters,
        pickupDetourSeconds: pickupMeasurement.durationSeconds,
        dropoffDetourMeters: dropoffMeasurement.distanceMeters,
        dropoffDetourSeconds: dropoffMeasurement.durationSeconds,
      };
    } catch (error: unknown) {
      if (error instanceof HttpsError) {
        throw error;
      }

      logger.error("Google Routes deviation request failed", {
        errorType: error instanceof Error ? error.name : "UnknownError",
      });

      throw new HttpsError(
        "unavailable",
        "Sürüş sapması servisine şu anda ulaşılamıyor.",
      );
    }
  },
);

/* eslint-disable max-len */
export const requestAccountDeletion = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 15,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError(
        "unauthenticated",
        "Hesap silme talebi için oturum açmanız gereklidir.",
      );
    }

    return requestAccountDeletionForUser(
      {firestore},
      request.auth.uid,
      request.data,
    );
  },
);

export const getMyRideMatchOffers = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
    minInstances: 0,
    maxInstances: 3,
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError(
        "unauthenticated",
        "Ride match offers require authentication.",
      );
    }

    if (
      typeof request.data !== "object" ||
      request.data === null ||
      Array.isArray(request.data) ||
      Object.keys(request.data).length !== 0
    ) {
      throw new HttpsError(
        "invalid-argument",
        "Ride match offer request is invalid.",
        {
          reason:
            "invalid_ride_match_offer_payload",
        },
      );
    }

    try {
      return await discoverRideMatchOffersForDriver(
        {
          firestore,
          measureDeviation:
            computeRideMatchDeviation,
        },
        request.auth.uid,
      );
    } catch (error: unknown) {
      if (error instanceof HttpsError) {
        throw error;
      }

      logger.error(
        "YoldaAl ride match offer discovery failed",
        {
          errorType:
            error instanceof Error ?
              error.name :
              "UnknownError",
        },
      );

      throw new HttpsError(
        "unavailable",
        "Ride match offers are temporarily unavailable.",
      );
    }
  },
);

export const getNearbyPassengerDrivers = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
    minInstances: 0,
    maxInstances: 3,
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError(
        "unauthenticated",
        "Yak?ndaki s?r?c?ler i?in giri? yapmal?s?n?z.",
      );
    }

    try {
      return await discoverNearbyPassengerDriversForPassenger(
        {
          firestore,
          measureCompatibility:
            computeNearbyPassengerCompatibility,
        },
        request.auth.uid,
        request.data,
      );
    } catch (error: unknown) {
      if (error instanceof HttpsError) {
        throw error;
      }

      logger.error(
        "YoldaAl nearby passenger driver discovery failed",
        {
          errorType:
            error instanceof Error ?
              error.name :
              "UnknownError",
        },
      );

      throw new HttpsError(
        "unavailable",
        "Yak?ndaki s?r?c?ler ?u anda y?klenemedi.",
      );
    }
  },
);


export const createRideRequest = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
    minInstances: 0,
    maxInstances: 3,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Yolculuk oluÅŸturmak iÃ§in giriÅŸ yapmalÄ±sÄ±nÄ±z.");
    }
    return createRideRequestForPassenger(
      {firestore, computeRoute: computePublishedRoute},
      request.auth.uid,
      request.data,
    );
  },
);

export const getMyActiveRide = onCall(
  {region: "europe-west1", timeoutSeconds: 15, memory: "256MiB",
    minInstances: 0, maxInstances: 3},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Aktif yolculuk iÃ§in giriÅŸ yapmalÄ±sÄ±nÄ±z.");
    }
    if (typeof request.data !== "object" || request.data === null ||
        Array.isArray(request.data) || Object.keys(request.data).length !== 0) {
      throw new HttpsError("invalid-argument", "Aktif yolculuk isteÄŸi geÃ§ersiz.",
        {reason: "invalid_active_ride_payload"});
    }
    const passengerId = request.auth.uid;
    const pointer = await firestore.collection("passengerActiveRides")
      .doc(passengerId).get();
    if (!pointer.exists) return {activeRide: null};
    const rideId = pointer.get("rideId");
    if (typeof rideId !== "string" || rideId.length === 0) {
      throw new HttpsError("failed-precondition", "Aktif yolculuk bilgisi tutarsÄ±z.",
        {reason: "active_ride_pointer_inconsistent"});
    }
    const ride = await firestore.collection("rides").doc(rideId).get();
    const data = ride.data();
    if (!ride.exists || !data || data.passengerId !== passengerId ||
        pointer.get("status") !== data.status ||
        TERMINAL_RIDE_STATUSES.includes(parseRideStatus(data.status))) {
      throw new HttpsError("failed-precondition", "Aktif yolculuk bilgisi tutarsÄ±z.",
        {reason: "active_ride_pointer_inconsistent"});
    }
    return {activeRide: serializeActiveRide(ride.id, data)};
  },
);

export const getMyRideHistory = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 15,
    memory: "256MiB",
    minInstances: 0,
    maxInstances: 3,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Ride history requires authentication.",
      );
    }

    return getRideHistoryForActor(
      {firestore},
      request.auth.uid,
      request.data,
    );
  },
);

export const cancelRide = onCall(
  {region: "europe-west1", timeoutSeconds: 15, memory: "256MiB",
    minInstances: 0, maxInstances: 3},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Yolculuk iptali iÃ§in giriÅŸ yapmalÄ±sÄ±nÄ±z.");
    }
    return cancelRideForActor(
      {firestore},
      request.auth.uid,
      request.data,
    );
  },
);


export const acceptRide = onCall(
  {region: "europe-west1", timeoutSeconds: 15, memory: "256MiB",
    minInstances: 0, maxInstances: 3},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated",
        "Yolculuk kabulÃ¼ iÃ§in giriÅŸ yapmalÄ±sÄ±nÄ±z.");
    }
    return acceptRideForDriver({firestore}, request.auth.uid, request.data);
  },
);

export const markDriverArrived = onCall(
  {region: "europe-west1", timeoutSeconds: 15, memory: "256MiB",
    minInstances: 0, maxInstances: 3},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated",
        "SÃ¼rÃ¼cÃ¼ iÅŸlemi iÃ§in giriÅŸ yapmalÄ±sÄ±nÄ±z.");
    }
    return transitionRideForDriver({firestore}, request.auth.uid, request.data,
      DRIVER_TRANSITIONS.markDriverArrived);
  },
);

export const startRide = onCall(
  {region: "europe-west1", timeoutSeconds: 15, memory: "256MiB",
    minInstances: 0, maxInstances: 3},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated",
        "SÃ¼rÃ¼cÃ¼ iÅŸlemi iÃ§in giriÅŸ yapmalÄ±sÄ±nÄ±z.");
    }
    return transitionRideForDriver({firestore}, request.auth.uid, request.data,
      DRIVER_TRANSITIONS.startRide);
  },
);

export const completeRide = onCall(
  {region: "europe-west1", timeoutSeconds: 15, memory: "256MiB",
    minInstances: 0, maxInstances: 3},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated",
        "SÃ¼rÃ¼cÃ¼ iÅŸlemi iÃ§in giriÅŸ yapmalÄ±sÄ±nÄ±z.");
    }
    return transitionRideForDriver({firestore}, request.auth.uid, request.data,
      DRIVER_TRANSITIONS.completeRide);
  },
);

export const submitRideRating = onCall(
  {region: "europe-west1", timeoutSeconds: 15, memory: "256MiB",
    minInstances: 0, maxInstances: 3},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated",
        "Ride rating requires authentication.");
    }
    return submitRideRatingForActor(
      {firestore}, request.auth.uid, request.data);
  },
);
export const getMyRideRatingStatus = onCall(
  {region: "europe-west1", timeoutSeconds: 15, memory: "256MiB",
    minInstances: 0, maxInstances: 3},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Ride rating status requires authentication.",
      );
    }

    return getRideRatingStatusForActor(
      {firestore},
      request.auth.uid,
      request.data,
    );
  },
);
export const createRideSupportCase = onCall(
  {region: "europe-west1", timeoutSeconds: 15, memory: "256MiB",
    minInstances: 0, maxInstances: 3},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Ride support requires authentication.",
      );
    }

    return createRideSupportCaseForActor(
      {firestore},
      request.auth.uid,
      request.data,
    );
  },
);
export const createActiveRideSupportCase = onCall(
  {region: "europe-west1", timeoutSeconds: 15, memory: "256MiB",
    minInstances: 0, maxInstances: 3},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Active ride support requires authentication.",
      );
    }

    return createActiveRideSupportCaseForActor(
      {firestore},
      request.auth.uid,
      request.data,
    );
  },
);
export const sendRideChatMessage = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 15,
    memory: "256MiB",
    minInstances: 0,
    maxInstances: 3,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Ride chat send requires authentication.",
      );
    }

    return sendRideChatMessageForActor(
      {firestore},
      request.auth.uid,
      request.data,
    );
  },
);

export const listRideChatMessages = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 15,
    memory: "256MiB",
    minInstances: 0,
    maxInstances: 3,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Ride chat read requires authentication.",
      );
    }

    return listRideChatMessagesForActor(
      {firestore},
      request.auth.uid,
      request.data,
    );
  },
);
export const proposeRideDropoffChange = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
    minInstances: 0,
    maxInstances: 3,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Ride dropoff change requires authentication.",
      );
    }

    return proposeRideDropoffChangeForActor(
      {
        firestore,
        routesClient,
      },
      request.auth.uid,
      request.data,
    );
  },
);

export const acknowledgeRideDropoffChange = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 15,
    memory: "256MiB",
    minInstances: 0,
    maxInstances: 3,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Ride dropoff change acknowledgement requires authentication.",
      );
    }

    return acknowledgeRideDropoffChangeForActor(
      {
        firestore,
        routesClient,
      },
      request.auth.uid,
      request.data,
    );
  },
);
export const getPendingRideDropoffChangeProposal = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 15,
    memory: "256MiB",
    minInstances: 0,
    maxInstances: 3,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Ride dropoff change proposal requires authentication.",
      );
    }

    return getPendingRideDropoffChangeProposalForActor(
      {
        firestore,
      },
      request.auth.uid,
      request.data,
    );
  },
);
export const getMyActiveDriverRide = onCall(
  {region: "europe-west1", timeoutSeconds: 15, memory: "256MiB",
    minInstances: 0, maxInstances: 3},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated",
        "Aktif yolculuk iÃ§in giriÅŸ yapmalÄ±sÄ±nÄ±z.");
    }
    if (typeof request.data !== "object" || request.data === null ||
        Array.isArray(request.data) || Object.keys(request.data).length !== 0) {
      throw new HttpsError("invalid-argument", "Aktif yolculuk isteÄŸi geÃ§ersiz.",
        {reason: "invalid_active_ride_payload"});
    }
    const driverId = await loadApprovedDriverId(firestore, request.auth.uid);
    const pointer = await firestore.collection("driverActiveRides").doc(driverId).get();
    if (!pointer.exists) return {activeRide: null};
    const rideId = pointer.get("rideId");
    if (typeof rideId !== "string" || rideId.length === 0) {
      throw new HttpsError("failed-precondition", "Aktif yolculuk bilgisi tutarsÄ±z.",
        {reason: "active_ride_pointer_inconsistent"});
    }
    const ride = await firestore.collection("rides").doc(rideId).get();
    const data = ride.data();
    if (!ride.exists || !data || data.driverId !== driverId ||
        pointer.get("status") !== data.status ||
        TERMINAL_RIDE_STATUSES.includes(parseRideStatus(data.status))) {
      throw new HttpsError("failed-precondition", "Aktif yolculuk bilgisi tutarsÄ±z.",
        {reason: "active_ride_pointer_inconsistent"});
    }
    return {activeRide: serializeActiveRide(ride.id, data)};
  },
);
/* eslint-enable max-len */

/* eslint-disable max-len */
export const getMyActiveReturnRoute = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 15,
    memory: "256MiB",
    minInstances: 0,
    maxInstances: 3,
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError(
        "unauthenticated",
        "Aktif dönüş rotası için giriş yapmalısınız.",
      );
    }

    if (
      typeof request.data !== "object" ||
      request.data === null ||
      Array.isArray(request.data) ||
      Object.keys(request.data).length !== 0
    ) {
      throw new HttpsError(
        "invalid-argument",
        "Aktif dönüş rotası isteği geçersiz.",
        {
          reason: "invalid_active_return_route_payload",
        },
      );
    }

    try {
      const activeReturnRoute =
        await recoverActiveReturnRoute(
          {
            loadDriverId: (uid) =>
              loadApprovedDriverId(firestore, uid),
            readLock: (driverId) =>
              firestore
                .collection("driverActiveReturnRoutes")
                .doc(driverId)
                .get(),
            readRoute: (routeId) =>
              firestore
                .collection("driverReturnRoutes")
                .doc(routeId)
                .get(),
            now: () => Timestamp.now(),
          },
          request.auth.uid,
        );

      return {
        activeReturnRoute,
      };
    } catch (error: unknown) {
      if (error instanceof HttpsError) {
        throw error;
      }

      logger.error(
        "YoldaAl active return route recovery failed",
        {
          errorType:
            error instanceof Error ?
              error.name :
              "UnknownError",
        },
      );

      throw new HttpsError(
        "unavailable",
        "Aktif dönüş rotası şu anda yüklenemedi.",
        {
          reason: "active_return_route_read_failed",
        },
      );
    }
  },
);
/* eslint-enable max-len */

/* eslint-disable max-len */

export const getMyDriverApplicationStatus = onCall(
  {region: "europe-west1", timeoutSeconds: 30, memory: "256MiB",
    minInstances: 0, maxInstances: 3},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Oturum açmanız gereklidir.",
        {reason: "authentication_required"});
    }
    if (request.data !== undefined && request.data !== null &&
        (typeof request.data !== "object" || Array.isArray(request.data) ||
         Object.keys(request.data as Record<string, unknown>).length !== 0)) {
      throw new HttpsError("invalid-argument", "İstek uygun değildir.",
        {reason: "invalid_driver_application_status_payload"});
    }
    const uid = request.auth.uid;
    const applicationRef = firestore.collection("driverApplications").doc(uid);
    try {
      const [application, ...documents] = await Promise.all([
        applicationRef.get(), ...getRequiredDocumentTypes().map((type) =>
          applicationRef.collection("documents").doc(type).get()),
      ]);
      if (!application.exists) {
        throw new HttpsError("not-found", "Sürücü başvurusu bulunamadı.",
          {reason: "driver_application_not_found"});
      }
      if (documents.some((document) => !document.exists)) {
        throw new HttpsError("internal", "Sürücü başvurusu doğrulanamadı.",
          {reason: "driver_application_document_data_invalid"});
      }
      const applicationData = application.data() ?? {};
      const currentDocuments = validateCurrentDocuments(uid, applicationData,
        documents.map((document) => document.data() ?? {}));
      return buildPublicDriverApplicationStatus(applicationData, currentDocuments);
    } catch (error: unknown) {
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("unavailable", "Sürücü başvurusu yüklenemedi.",
        {reason: "driver_application_status_read_failed"});
    }
  },
);

export const resubmitDriverApplicationDocuments =
  onCall<ResubmitDriverApplicationInput>(
    {region: "europe-west1", timeoutSeconds: 120, memory: "512MiB",
      minInstances: 0, maxInstances: 3},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Oturum açmanız gereklidir.",
          {reason: "authentication_required"});
      }
      const input = validateResubmissionPayload(request.data);
      const uid = request.auth.uid;
      const applicationRef = firestore.collection("driverApplications").doc(uid);
      const documentRefs = getRequiredDocumentTypes().map((type) =>
        applicationRef.collection("documents").doc(type));
      const operationRef = firestore.collection("driverApplicationResubmissionOperations")
        .doc(operationDocumentId(uid));
      const digest = requestDigest(input.requestId);
      const now = Timestamp.now();

      type Reservation = {completed: true; result: Record<string, unknown>} |
        {completed: false; documentSetId: string; submissionVersion: number};
      let reservation: Reservation;
      try {
        reservation = await firestore.runTransaction(async (transaction) => {
          const [operation, application, ...documents] = await Promise.all([
            transaction.get(operationRef), transaction.get(applicationRef),
            ...documentRefs.map((reference) => transaction.get(reference)),
          ]);
          const operationData = operation.data() ?? {};
          if (operation.exists && operationData.requestDigest === digest &&
              operationData.expectedSubmissionVersion === input.expectedSubmissionVersion) {
            if (operationData.status === "completed" &&
                typeof operationData.result === "object" && operationData.result !== null) {
              return {completed: true,
                result: operationData.result as Record<string, unknown>} as Reservation;
            }
            if (operationData.status === "processing" &&
                typeof operationData.documentSetId === "string" &&
                typeof operationData.submissionVersion === "number") {
              return {completed: false, documentSetId: operationData.documentSetId,
                submissionVersion: operationData.submissionVersion} as Reservation;
            }
          }
          if (operation.exists && operationData.status === "processing") {
            throw new HttpsError("aborted", "Belge gönderimi devam ediyor.",
              {reason: "driver_application_resubmission_in_progress"});
          }
          if (!application.exists) {
            throw new HttpsError("not-found", "Sürücü başvurusu bulunamadı.",
              {reason: "driver_application_not_found"});
          }
          if (documents.some((document) => !document.exists)) {
            throw new HttpsError("internal", "Sürücü başvurusu doğrulanamadı.",
              {reason: "driver_application_document_data_invalid"});
          }
          const applicationData = application.data() ?? {};
          const currentDocuments = validateCurrentDocuments(uid, applicationData,
            documents.map((document) => document.data() ?? {}));
          const submissionVersion = validateResubmissionEligibility(applicationData,
            currentDocuments, input.expectedSubmissionVersion);
          const documentSetId = randomUUID();
          transaction.set(operationRef, {status: "processing", requestDigest: digest,
            expectedSubmissionVersion: input.expectedSubmissionVersion,
            submissionVersion, documentSetId, createdAt: now, updatedAt: now});
          return {completed: false, documentSetId, submissionVersion} as Reservation;
        });
      } catch (error: unknown) {
        if (error instanceof HttpsError) throw error;
        throw new HttpsError("unavailable", "Belge gönderimi başlatılamadı.",
          {reason: "driver_application_resubmission_persistence_failed"});
      }
      if (reservation.completed) return reservation.result;

      const destinationPaths: string[] = [];
      const consumedStaging: Array<{path: string; generation: string}> = [];
      try {
        const [application, ...documents] = await Promise.all([
          applicationRef.get(), ...documentRefs.map((reference) => reference.get()),
        ]);
        if (!application.exists || documents.some((document) => !document.exists)) {
          throw new HttpsError("failed-precondition", "Başvuru güncel değildir.",
            {reason: "stale_driver_application_submission"});
        }
        const applicationData = application.data() ?? {};
        const currentDocuments = validateCurrentDocuments(uid, applicationData,
          documents.map((document) => document.data() ?? {}));
        validateResubmissionEligibility(applicationData, currentDocuments,
          input.expectedSubmissionVersion);

        const copiedDocuments = [] as Array<{documentType: typeof currentDocuments[number]["documentType"];
          path: string; metadata: ReturnType<typeof validateDocumentMetadata>;
          reviewStatus: "pendingReview" | "approved"; reviewedAt: unknown}>;
        for (const document of currentDocuments) {
          let sourcePath = document.storagePath;
          let sourceGeneration = document.storageGeneration;
          let expectedContentType = document.contentType;
          let expectedSizeBytes = document.sizeBytes;
          if (document.reviewStatus === "reuploadRequired") {
            sourcePath = buildStagingDocumentPath(uid, document.documentType);
            const [metadata] = await storageBucket.file(sourcePath).getMetadata();
            const validated = validateDocumentMetadata(document.documentType, metadata, uid);
            if (!validated.generation) {
              throw new HttpsError("failed-precondition", "Belge doğrulanamadı.",
                {reason: "driver_application_document_invalid"});
            }
            sourceGeneration = validated.generation;
            expectedContentType = validated.contentType;
            expectedSizeBytes = validated.sizeBytes;
            consumedStaging.push({path: sourcePath, generation: sourceGeneration});
          } else {
            const [metadata] = await storageBucket.file(sourcePath,
              {generation: sourceGeneration}).getMetadata();
            const validated = validateDocumentMetadata(document.documentType, metadata, uid);
            if (validated.generation !== sourceGeneration ||
                validated.contentType !== document.contentType ||
                validated.sizeBytes !== document.sizeBytes) {
              throw new HttpsError("failed-precondition", "Belge doğrulanamadı.",
                {reason: "driver_application_document_invalid"});
            }
          }
          const path = buildSubmissionDocumentPath(uid, reservation.documentSetId,
            document.documentType);
          const destination = storageBucket.file(path);
          destinationPaths.push(path);
          try {
            await storageBucket.file(sourcePath, {generation: sourceGeneration})
              .copy(destination, {preconditionOpts: {ifGenerationMatch: 0}});
          } catch (_error: unknown) {
            const [existing] = await destination.getMetadata();
            validateDocumentMetadata(document.documentType, existing, uid);
          }
          const [destinationMetadata] = await destination.getMetadata();
          const metadata = validateDocumentMetadata(document.documentType,
            destinationMetadata, uid);
          if (metadata.contentType !== expectedContentType ||
              metadata.sizeBytes !== expectedSizeBytes) {
            throw new HttpsError("failed-precondition", "Belge doğrulanamadı.",
              {reason: "driver_application_document_invalid"});
          }
          copiedDocuments.push({documentType: document.documentType, path, metadata,
            reviewStatus: document.reviewStatus === "approved" ? "approved" : "pendingReview",
            reviewedAt: document.reviewStatus === "approved" ? document.reviewedAt : null});
        }

        const completedAt = Timestamp.now();
        const result = {status: "pendingReview", submittedAtMillis: completedAt.toMillis(),
          updatedAtMillis: completedAt.toMillis(),
          submissionVersion: reservation.submissionVersion};
        await firestore.runTransaction(async (transaction) => {
          const [operation, currentApplication, ...currentDocumentSnapshots] =
            await Promise.all([transaction.get(operationRef),
              transaction.get(applicationRef),
              ...documentRefs.map((reference) => transaction.get(reference))]);
          const operationData = operation.data() ?? {};
          if (!operation.exists || operationData.status !== "processing" ||
              operationData.requestDigest !== digest ||
              operationData.documentSetId !== reservation.documentSetId) {
            throw new HttpsError("aborted", "Belge gönderimi güncel değildir.",
              {reason: "driver_application_resubmission_in_progress"});
          }
          if (!currentApplication.exists ||
              currentDocumentSnapshots.some((document) => !document.exists)) {
            throw new HttpsError("failed-precondition", "Başvuru güncel değildir.",
              {reason: "stale_driver_application_submission"});
          }
          const currentApplicationData = currentApplication.data() ?? {};
          const currentDocuments = validateCurrentDocuments(uid, currentApplicationData,
            currentDocumentSnapshots.map((document) => document.data() ?? {}));
          validateResubmissionEligibility(currentApplicationData, currentDocuments,
            input.expectedSubmissionVersion);
          transaction.update(applicationRef, {status: "pendingReview",
            submissionVersion: reservation.submissionVersion,
            documentSetId: reservation.documentSetId, submittedAt: completedAt,
            updatedAt: completedAt, reviewedAt: null, rejectionReasonCode: null,
            reviewedByAdminUid: null});
          copiedDocuments.forEach((document, index) => transaction.set(
            documentRefs[index], {documentType: document.documentType,
              storagePath: document.path, contentType: document.metadata.contentType,
              sizeBytes: document.metadata.sizeBytes,
              uploadedAt: Timestamp.fromMillis(document.metadata.uploadedAtMillis),
              reviewStatus: document.reviewStatus, reviewedAt: document.reviewedAt,
              rejectionReasonCode: null, documentSetId: reservation.documentSetId,
              submissionVersion: reservation.submissionVersion,
              storageGeneration: document.metadata.generation ?? null}));
          transaction.set(firestore.collection("driverApplicationReviewEvents")
            .doc(`resubmission_${operationRef.id}_${digest.slice(0, 32)}`),
          {applicationId: uid,
            eventType: "applicationResubmitted", documentType: null,
            reasonCode: null, createdAt: completedAt});
          transaction.update(operationRef, {status: "completed", result,
            updatedAt: completedAt});
        });
        await Promise.allSettled(consumedStaging.map((item) =>
          storageBucket.file(item.path).delete({ignoreNotFound: true,
            ifGenerationMatch: item.generation})));
        return result;
      } catch (error: unknown) {
        const current = await applicationRef.get().catch(() => null);
        if (!current?.exists ||
            current.data()?.documentSetId !== reservation.documentSetId) {
          await Promise.allSettled(destinationPaths.map((path) =>
            storageBucket.file(path).delete({ignoreNotFound: true})));
        }
        if (error instanceof HttpsError) throw error;
        throw new HttpsError("unavailable", "Belgeler yeniden gönderilemedi.",
          {reason: "driver_application_resubmission_failed"});
      }
    },
  );

/* eslint-enable max-len */
export const submitDriverApplication =
  onCall<SubmitDriverApplicationInput>(
    {
      region: "europe-west1",
      timeoutSeconds: 120,
      memory: "512MiB",
      minInstances: 0,
      maxInstances: 3,
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError(
          "unauthenticated",
          "Sürücü başvurusu göndermek için giriş yapmalısınız.",
          {reason: "authentication_required"},
        );
      }

      const input = validateApplicationPayload(request.data);
      const uid = request.auth.uid;
      const now = Timestamp.now();
      const applicationReference = firestore
        .collection("driverApplications").doc(uid);
      const profileQuery = firestore.collection("driverProfiles")
        .where("authUserId", "==", uid)
        .limit(2);
      let tokenPhone = request.auth.token.phone_number;
      if (typeof tokenPhone !== "string" || tokenPhone.trim().length === 0) {
        try {
          tokenPhone = (await auth.getUser(uid)).phoneNumber;
        } catch (_error: unknown) {
          tokenPhone = undefined;
        }
      }
      const verifiedPhoneNumber = validateVerifiedPhone(tokenPhone);

      try {
        const [profiles, application] = await Promise.all([
          profileQuery.get(), applicationReference.get(),
        ]);
        if (profiles.size > 1) {
          throw new HttpsError(
            "internal", "Sürücü profili verileri doğrulanamadı.",
            {reason: "driver_application_data_invalid"});
        }
        if (!profiles.empty) {
          throw new HttpsError(
            "failed-precondition", "Mevcut sürücü profili bulunmaktadır.",
            {reason: "driver_profile_exists"});
        }
        determineSubmissionTransition(
          application.exists ? application.data() ?? {} : null,
        );
      } catch (error: unknown) {
        if (error instanceof HttpsError) throw error;
        throw new HttpsError("unavailable",
          "Sürücü başvurusu şu anda doğrulanamadı.",
          {reason: "driver_application_persistence_failed"});
      }

      const documentTypes = getRequiredDocumentTypes();
      const stagingDocuments = await Promise.all(documentTypes.map(
        async (documentType) => {
          const path = buildStagingDocumentPath(uid, documentType);
          const file = storageBucket.file(path);
          try {
            const [metadata] = await file.getMetadata();
            return {
              documentType, file,
              metadata: validateDocumentMetadata(documentType, metadata, uid),
            };
          } catch (error: unknown) {
            if (error instanceof HttpsError) throw error;
            throw new HttpsError("failed-precondition",
              "Zorunlu sürücü başvurusu belgeleri eksiktir.",
              {reason: "required_documents_missing"});
          }
        },
      ));

      const documentSetId = randomUUID();
      const copiedDocuments: Array<{
        documentType: typeof documentTypes[number];
        path: string;
        metadata: ReturnType<typeof validateDocumentMetadata>;
      }> = [];
      const cleanupCopiedDocuments = async () => {
        await Promise.allSettled(copiedDocuments.map((item) =>
          storageBucket.file(item.path).delete({ignoreNotFound: true})));
      };

      try {
        for (const source of stagingDocuments) {
          const path = buildSubmissionDocumentPath(
            uid, documentSetId, source.documentType,
          );
          const destination = storageBucket.file(path);
          await source.file.copy(destination);
          const [metadata] = await destination.getMetadata();
          copiedDocuments.push({
            documentType: source.documentType,
            path,
            metadata: validateDocumentMetadata(
              source.documentType, metadata, uid,
            ),
          });
        }
      } catch (_error: unknown) {
        await cleanupCopiedDocuments();
        throw new HttpsError("unavailable",
          "Sürücü başvurusu belgeleri kopyalanamadı.",
          {reason: "driver_application_document_copy_failed"});
      }

      let submissionVersion: number;

      try {
        submissionVersion = await firestore.runTransaction(
          async (transaction) => {
            const [profiles, application] = await Promise.all([
              transaction.get(profileQuery),
              transaction.get(applicationReference),
            ]);
            if (profiles.size > 1) {
              throw new HttpsError(
                "internal",
                "Sürücü profili verileri doğrulanamadı.",
                {reason: "driver_application_data_invalid"},
              );
            }
            if (!profiles.empty) {
              throw new HttpsError(
                "failed-precondition",
                "Mevcut sürücü profili için yeni başvuru oluşturulamaz.",
                {reason: "driver_profile_exists"},
              );
            }

            const transition = determineSubmissionTransition(
              application.exists ? application.data() ?? {} : null,
            );
            transaction.set(applicationReference, {
              authUserId: uid,
              verifiedPhoneNumber,
              fullName: input.fullName,
              email: input.email,
              driverTaxiStandName: input.driverTaxiStandName,
              driverTaxiStandAddress: input.driverTaxiStandAddress,
              workType: input.workType,
              vehiclePlate: input.vehiclePlate,
              vehicleBrand: input.vehicleBrand,
              vehicleModel: input.vehicleModel,
              vehicleModelYear: input.vehicleModelYear,
              registrationOwnerType: input.registrationOwnerType,
              hasVehicleUseAuthorization: input.hasVehicleUseAuthorization,
              vehicleTaxiStandName: input.vehicleTaxiStandName,
              status: "pendingReview",
              submittedAt: now,
              updatedAt: now,
              reviewedAt: null,
              rejectionReasonCode: null,
              submissionVersion: transition.submissionVersion,
              documentSetId,
              informationAccuracyAccepted: true,
              documentValidityNotificationAccepted: true,
              documentProcessingNoticeAccepted: true,
              kvkkNoticeAccepted: true,
              termsAccepted: true,
              marketingConsent: input.marketingConsent,
            });
            for (const document of copiedDocuments) {
              transaction.set(
                applicationReference.collection("documents")
                  .doc(document.documentType),
                {
                  documentType: document.documentType,
                  storagePath: document.path,
                  contentType: document.metadata.contentType,
                  sizeBytes: document.metadata.sizeBytes,
                  uploadedAt: Timestamp.fromMillis(
                    document.metadata.uploadedAtMillis,
                  ),
                  reviewStatus: "pendingReview",
                  reviewedAt: null,
                  rejectionReasonCode: null,
                  documentSetId,
                  submissionVersion: transition.submissionVersion,
                  storageGeneration: document.metadata.generation ?? null,
                },
              );
            }
            return transition.submissionVersion;
          },
        );
      } catch (error: unknown) {
        await cleanupCopiedDocuments();
        if (error instanceof HttpsError) throw error;
        logger.error("Driver application persistence failed", {
          errorType: error instanceof Error ? error.name : "UnknownError",
        });
        throw new HttpsError(
          "unavailable",
          "Sürücü başvurusu şu anda kaydedilemedi.",
          {reason: "driver_application_persistence_failed"},
        );
      }

      await Promise.allSettled(stagingDocuments.map((item) =>
        item.file.delete({ignoreNotFound: true})));

      return {
        status: "pendingReview",
        submittedAtMillis: now.toMillis(),
        updatedAtMillis: now.toMillis(),
        submissionVersion,
      };
    },
  );

/* eslint-disable max-len */
export const reviewDriverApplicationDocument = onCall(
  {region: "europe-west1", timeoutSeconds: 30, memory: "256MiB",
    minInstances: 0, maxInstances: 3},
  async (request) => {
    const reviewerUid = requireYoldaAlAdmin(request.auth);
    const input = validateDocumentReviewPayload(request.data);
    const now = Timestamp.now();
    const applicationRef = firestore.collection("driverApplications")
      .doc(input.applicationId);
    const documentRef = applicationRef.collection("documents")
      .doc(input.documentType);
    const auditRef = firestore.collection("driverApplicationReviewEvents").doc();
    try {
      return await firestore.runTransaction(async (transaction) => {
        const [application, document] = await Promise.all([
          transaction.get(applicationRef), transaction.get(documentRef),
        ]);
        if (!application.exists) {
          throw new HttpsError("not-found", "Başvuru bulunamadı.",
            {reason: "driver_application_not_found"});
        }
        if (!document.exists) {
          throw new HttpsError("not-found", "Belge bulunamadı.",
            {reason: "driver_application_document_not_found"});
        }
        const applicationData = application.data() ?? {};
        const documentData = document.data() ?? {};
        validateCurrentApplicationVersion(applicationData,
          input.submissionVersion, input.documentSetId);
        validateCurrentDocumentMetadata(documentData, input);
        const transition = determineDocumentReviewTransition(
          documentData.reviewStatus, input.decision);
        const idempotentReupload = transition.idempotent &&
          transition.status === "reuploadRequired" &&
          applicationData.status === "rejected";
        if (applicationData.status !== "pendingReview" && !idempotentReupload) {
          throw new HttpsError("failed-precondition", "Başvuru incelemeye açık değildir.",
            {reason: "driver_application_not_pending"});
        }
        if (transition.idempotent) {
          const reviewedAt = documentData.reviewedAt;
          if (!(reviewedAt instanceof Timestamp)) {
            throw new HttpsError("internal", "İnceleme verisi doğrulanamadı.",
              {reason: "driver_application_review_data_invalid"});
          }
          return {applicationStatus: applicationData.status,
            documentStatus: transition.status,
            reviewedAtMillis: reviewedAt.toMillis()};
        }
        transaction.update(documentRef, {reviewStatus: transition.status,
          reviewedAt: now, rejectionReasonCode: input.reasonCode,
          reviewedByAdminUid: reviewerUid});
        const applicationStatus = transition.status === "reuploadRequired" ?
          "rejected" : "pendingReview";
        if (applicationStatus === "rejected") {
          transaction.update(applicationRef, {status: "rejected", updatedAt: now,
            reviewedAt: now, rejectionReasonCode: "document_reupload_required",
            reviewedByAdminUid: reviewerUid});
        }
        transaction.create(auditRef, buildReviewAuditEvent({
          applicationId: input.applicationId, reviewerAuthUserId: reviewerUid,
          eventType: transition.status === "approved" ? "documentApproved" :
            "documentReuploadRequired", documentType: input.documentType,
          reasonCode: input.reasonCode, submissionVersion: input.submissionVersion,
          documentSetId: input.documentSetId, now,
        }));
        return {applicationStatus, documentStatus: transition.status,
          reviewedAtMillis: now.toMillis()};
      });
    } catch (error: unknown) {
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("unavailable", "İnceleme kaydedilemedi.",
        {reason: "driver_application_review_persistence_failed"});
    }
  },
);

export const reviewDriverApplication = onCall(
  {region: "europe-west1", timeoutSeconds: 30, memory: "256MiB",
    minInstances: 0, maxInstances: 3},
  async (request) => {
    const reviewerUid = requireYoldaAlAdmin(request.auth);
    const input = validateApplicationReviewPayload(request.data);
    const now = Timestamp.now();
    const applicationRef = firestore.collection("driverApplications")
      .doc(input.applicationId);
    const documentRefs = getRequiredDocumentTypes().map((type) =>
      applicationRef.collection("documents").doc(type));
    const profileQuery = firestore.collection("driverProfiles")
      .where("authUserId", "==", input.applicationId).limit(2);
    const profileRef = firestore.collection("driverProfiles").doc(input.applicationId);
    const auditRef = firestore.collection("driverApplicationReviewEvents").doc();
    try {
      return await firestore.runTransaction(async (transaction) => {
        const [application, profiles, ...documents] = await Promise.all([
          transaction.get(applicationRef), transaction.get(profileQuery),
          ...documentRefs.map((ref) => transaction.get(ref)),
        ]);
        if (!application.exists) {
          throw new HttpsError("not-found", "Başvuru bulunamadı.",
            {reason: "driver_application_not_found"});
        }
        const data = application.data() ?? {};
        validateCurrentApplicationVersion(data, input.submissionVersion,
          input.documentSetId);
        if (data.status !== "pendingReview") {
          throw new HttpsError("failed-precondition", "Başvuru incelemeye açık değildir.",
            {reason: "driver_application_not_pending"});
        }
        if (profiles.size > 1 || (!profiles.empty && input.decision === "approve")) {
          throw new HttpsError("failed-precondition", "Sürücü profili zaten bulunmaktadır.",
            {reason: "driver_profile_exists"});
        }
        if (input.decision === "approve") {
          const documentData = documents.filter((item) => item.exists)
            .map((item) => item.data() ?? {});
          if (!hasAllRequiredApprovedDocuments(documentData,
            input.applicationId, input.submissionVersion, input.documentSetId)) {
            throw new HttpsError("failed-precondition", "Belgeler onaylanmamıştır.",
              {reason: "driver_application_documents_not_approved"});
          }
          transaction.create(profileRef, {authUserId: input.applicationId,
            status: "approved", createdAt: now, approvedAt: now, suspendedAt: null});
        }
        const status = input.decision === "approve" ? "approved" : "rejected";
        transaction.update(applicationRef, {status, updatedAt: now, reviewedAt: now,
          rejectionReasonCode: input.rejectionReasonCode,
          reviewedByAdminUid: reviewerUid});
        transaction.create(auditRef, buildReviewAuditEvent({
          applicationId: input.applicationId, reviewerAuthUserId: reviewerUid,
          eventType: status === "approved" ? "applicationApproved" :
            "applicationRejected", reasonCode: input.rejectionReasonCode,
          submissionVersion: input.submissionVersion,
          documentSetId: input.documentSetId, now,
        }));
        return {status, reviewedAtMillis: now.toMillis(),
          driverProfileCreated: status === "approved"};
      });
    } catch (error: unknown) {
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("unavailable", "İnceleme kaydedilemedi.",
        {reason: "driver_application_review_persistence_failed"});
    }
  },
);

export const listDriverApplicationsForReview = onCall(
  {region: "europe-west1", timeoutSeconds: 30, memory: "256MiB",
    minInstances: 0, maxInstances: 3},
  async (request) => {
    requireYoldaAlAdmin(request.auth);
    const input = validateApplicationListPayload(request.data);
    try {
      const filter = input.status === null ? reviewStateQuery(input.reviewState) :
        {status: input.status, rejectionReasonCodes: null};
      let query = firestore.collection("driverApplications")
        .where("status", "==", filter.status);
      if (filter.rejectionReasonCodes !== null) {
        query = query.where("rejectionReasonCode", "in",
          filter.rejectionReasonCodes);
      }
      query = query
        .orderBy("submittedAt", "desc")
        .orderBy(FieldPath.documentId(), "desc");
      if (input.cursor) {
        query = query.startAfter(Timestamp.fromMillis(
          input.cursor.submittedAtMillis), input.cursor.applicationId);
      }
      const snapshot = await query.limit(input.pageSize + 1).get();
      const hasMore = snapshot.size > input.pageSize;
      const items = snapshot.docs.slice(0, input.pageSize)
        .map((document) => mapApplicationSummary(document.id,
          document.data()));
      return {items, nextCursor: buildNextCursor(items, hasMore)};
    } catch (error: unknown) {
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("unavailable", "Başvurular yüklenemedi.",
        {reason: "driver_application_list_failed"});
    }
  },
);

export const listDriverApplicationReviewEvents = onCall(
  {region: "europe-west1", timeoutSeconds: 30, memory: "256MiB",
    minInstances: 0, maxInstances: 3},
  async (request) => {
    requireYoldaAlAdmin(request.auth);
    const input = validateReviewEventsPayload(request.data);
    const applicationRef = firestore.collection("driverApplications")
      .doc(input.applicationId);
    try {
      const application = await applicationRef.get();
      if (!application.exists) {
        throw new HttpsError("not-found", "Başvuru bulunamadı.",
          {reason: "driver_application_not_found"});
      }
      let query = firestore.collection("driverApplicationReviewEvents")
        .where("applicationId", "==", input.applicationId)
        .orderBy("createdAt", "desc")
        .orderBy(FieldPath.documentId(), "desc");
      if (input.cursor) {
        query = query.startAfter(Timestamp.fromMillis(
          input.cursor.createdAtMillis), input.cursor.eventId);
      }
      const snapshot = await query.limit(input.pageSize + 1).get();
      return buildReviewEventsPage(snapshot.docs.map((document) => ({
        id: document.id, data: document.data(),
      })), input.pageSize);
    } catch (error: unknown) {
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("unavailable", "İnceleme geçmişi yüklenemedi.",
        {reason: "driver_application_review_events_failed"});
    }
  },
);

export const getDriverApplicationReviewDetails = onCall(
  {region: "europe-west1", timeoutSeconds: 30, memory: "256MiB",
    minInstances: 0, maxInstances: 3},
  async (request) => {
    const reviewerUid = requireYoldaAlAdmin(request.auth);
    const input = validateApplicationDetailsPayload(request.data);
    const applicationRef = firestore.collection("driverApplications")
      .doc(input.applicationId);
    try {
      const [application, ...documents] = await Promise.all([
        applicationRef.get(), ...getRequiredDocumentTypes().map((type) =>
          applicationRef.collection("documents").doc(type).get()),
      ]);
      if (!application.exists) {
        throw new HttpsError("not-found", "Başvuru bulunamadı.",
          {reason: "driver_application_not_found"});
      }
      if (documents.some((document) => !document.exists)) {
        throw new HttpsError("internal", "Başvuru belgeleri doğrulanamadı.",
          {reason: "driver_application_review_data_invalid"});
      }
      const reviewContext = buildReviewContext(application.data() ?? {});
      const result = mapApplicationReviewDetails(application.id,
        application.data() ?? {}, documents.map((document, index) => ({
          type: getRequiredDocumentTypes()[index], data: document.data() ?? {},
        })), reviewContext);
      const now = Timestamp.now();
      await firestore.collection("driverApplicationReviewEvents").add(
        buildReviewAuditEvent({applicationId: input.applicationId,
          reviewerAuthUserId: reviewerUid, eventType: "applicationViewed",
          submissionVersion: reviewContext.submissionVersion,
          documentSetId: reviewContext.documentSetId, now}));
      return result;
    } catch (error: unknown) {
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("unavailable", "Başvuru ayrıntıları yüklenemedi.",
        {reason: "driver_application_details_failed"});
    }
  },
);

export const createDriverApplicationDocumentReviewUrl = onCall(
  {region: "europe-west1", timeoutSeconds: 30, memory: "256MiB",
    minInstances: 0, maxInstances: 3},
  async (request) => {
    const reviewerUid = requireYoldaAlAdmin(request.auth);
    const input = validateDocumentReviewUrlPayload(request.data);
    const applicationRef = firestore.collection("driverApplications")
      .doc(input.applicationId);
    const documentRef = applicationRef.collection("documents")
      .doc(input.documentType);
    try {
      const [application, document] = await Promise.all([
        applicationRef.get(), documentRef.get(),
      ]);
      if (!application.exists) {
        throw new HttpsError("not-found", "Başvuru bulunamadı.",
          {reason: "driver_application_not_found"});
      }
      if (!document.exists) {
        throw new HttpsError("not-found", "Belge bulunamadı.",
          {reason: "driver_application_document_not_found"});
      }
      validateCurrentApplicationVersion(application.data() ?? {},
        input.submissionVersion, input.documentSetId);
      const metadata = document.data() ?? {};
      validateCurrentDocumentMetadata(metadata, input);
      const contentType = metadata.contentType;
      const sizeBytes = metadata.sizeBytes;
      const allowedTypes = input.documentType === "vehicleRegistration" ||
        input.documentType === "criminalRecord" ?
        ["image/jpeg", "image/png", "application/pdf"] :
        ["image/jpeg", "image/png"];
      const maximum = (input.documentType === "driverProfilePhoto" ? 5 : 10) *
        1024 * 1024;
      if (typeof contentType !== "string" ||
          !allowedTypes.includes(contentType) || typeof sizeBytes !== "number" ||
          !Number.isInteger(sizeBytes) || sizeBytes <= 0 || sizeBytes > maximum) {
        throw new HttpsError("internal", "Belge bilgileri doğrulanamadı.",
          {reason: "driver_application_document_data_invalid"});
      }
      const path = buildSubmissionDocumentPath(input.applicationId,
        input.documentSetId, input.documentType);
      const file = storageBucket.file(path);
      let objectMetadata;
      try {
        [objectMetadata] = await file.getMetadata();
      } catch (_error: unknown) {
        throw new HttpsError("not-found", "Belge bulunamadı.",
          {reason: "driver_application_document_not_found"});
      }
      if (objectMetadata.contentType !== contentType ||
          Number(objectMetadata.size) !== sizeBytes) {
        throw new HttpsError("internal", "Belge bilgileri doğrulanamadı.",
          {reason: "driver_application_document_data_invalid"});
      }
      const now = Timestamp.now();
      const expiresAtMillis = calculateReviewUrlExpiry(now.toMillis());
      let url: string;
      try {
        [url] = await file.getSignedUrl({version: "v4", action: "read",
          expires: expiresAtMillis});
      } catch (_error: unknown) {
        throw new HttpsError("unavailable", "Belge erişimi oluşturulamadı.",
          {reason: "document_review_url_unavailable"});
      }
      try {
        await firestore.collection("driverApplicationReviewEvents").add(
          buildReviewAuditEvent({applicationId: input.applicationId,
            reviewerAuthUserId: reviewerUid, eventType: "documentViewed",
            documentType: input.documentType,
            submissionVersion: input.submissionVersion,
            documentSetId: input.documentSetId, now}));
      } catch (_error: unknown) {
        throw new HttpsError("unavailable", "Belge erişimi kaydedilemedi.",
          {reason: "driver_application_review_audit_failed"});
      }
      return {url, expiresAtMillis, contentType, sizeBytes};
    } catch (error: unknown) {
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("unavailable", "Belge erişimi oluşturulamadı.",
        {reason: "document_review_url_unavailable"});
    }
  },
);

/* eslint-enable max-len */
export const publishReturnRoute = onCall<PublishReturnRouteInput>(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
    minInstances: 0,
    maxInstances: 3,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Dönüş rotası yayımlamak için giriş yapmalısınız.",
      );
    }

    const uid = request.auth.uid;
    const input = validatePublishInput(request.data);
    let driverId: string;
    try {
      const accessNow = Timestamp.now();
      driverId = await loadDriverAccess(
        uid,
        accessNow,
        (query) => query.get(),
      );
    } catch (error: unknown) {
      if (error instanceof HttpsError) throw error;
      throw new HttpsError(
        "internal",
        "Sürücü erişimi doğrulanamadı.",
        {reason: "route_persistence_failed"},
      );
    }

    let routeMeasurement: Awaited<ReturnType<typeof computePublishedRoute>>;
    let corridorPrefixes: ReturnType<typeof buildReturnRouteCorridorPrefixes>;
    try {
      routeMeasurement = await computePublishedRoute(
        input.origin,
        input.destination,
      );
      corridorPrefixes = buildReturnRouteCorridorPrefixes({
        routePoints: decodeEncodedPolyline(
          routeMeasurement.encodedPolyline,
        ),
        radiusMeters: RETURN_ROUTE_MATCH_MAX_DETOUR_METERS,
        initialPrecision: RETURN_ROUTE_CORRIDOR_INITIAL_PRECISION,
        maxPrefixCount: RETURN_ROUTE_CORRIDOR_MAX_PREFIX_COUNT,
      });
    } catch (_error: unknown) {
      throw new HttpsError(
        "unavailable",
        "Dönüş rotası şu anda hesaplanamadı.",
        {reason: "route_computation_failed"},
      );
    }

    const now = Timestamp.now();
    const expiresAt = Timestamp.fromMillis(
      now.toMillis() + input.validForSeconds * 1000,
    );
    const routeReference = firestore.collection("driverReturnRoutes").doc();
    const lockReference = firestore.collection("driverActiveReturnRoutes")
      .doc(driverId);
    const corridorIndexReference = firestore
      .collection("driverReturnRouteCorridorIndexes")
      .doc(driverId);

    try {
      await firestore.runTransaction(async (transaction) => {
        const verifiedDriverId = await loadDriverAccess(
          uid,
          now,
          (query) => transaction.get(query),
        );
        if (verifiedDriverId !== driverId) {
          throw new HttpsError(
            "internal",
            "Sürücü erişimi doğrulanamadı.",
            {reason: "route_persistence_failed"},
          );
        }

        const lock = await transaction.get(lockReference);
        const lockExpiresAt = lock.get("expiresAt");
        if (
          lock.exists &&
          lockExpiresAt instanceof Timestamp &&
          now.toMillis() < lockExpiresAt.toMillis()
        ) {
          throw safePrecondition("active_return_route_exists");
        }

        transaction.create(routeReference, {
          driverId,
          origin: input.origin,
          destination: input.destination,
          status: "active",
          createdAt: now,
          activatedAt: now,
          expiresAt,
          routeDistanceMeters: routeMeasurement.distanceMeters,
          routeDurationSeconds: routeMeasurement.durationSeconds,
          encodedPolyline: routeMeasurement.encodedPolyline,
          pricingVersion: null,
        });
        transaction.set(corridorIndexReference, {
          driverId,
          returnRouteId: routeReference.id,
          corridorPrefixes,
          activatedAt: now,
          expiresAt,
        });
        transaction.set(lockReference, {
          routeId: routeReference.id,
          activatedAt: now,
          expiresAt,
        });
      });
    } catch (error: unknown) {
      if (error instanceof HttpsError) throw error;
      throw new HttpsError(
        "internal",
        "Dönüş rotası kaydedilemedi.",
        {reason: "route_persistence_failed"},
      );
    }

    return {
      routeId: routeReference.id,
      driverId,
      status: "active",
      activatedAtMillis: now.toMillis(),
      expiresAtMillis: expiresAt.toMillis(),
      distanceMeters: routeMeasurement.distanceMeters,
      durationSeconds: routeMeasurement.durationSeconds,
      encodedPolyline: routeMeasurement.encodedPolyline,
    };
  },
);

export const publishDriverLiveLocation = onCall(
  {region: "europe-west1", timeoutSeconds: 15, memory: "256MiB",
    minInstances: 0, maxInstances: 3},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Sürücü konumunu yayımlamak için giriş yapmalısınız.",
      );
    }

    return publishDriverLivePresence(
      {firestore},
      request.auth.uid,
      request.data,
    );
  },
);
export const registerPassengerPushTarget = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 15,
    memory: "256MiB",
    minInstances: 0,
    maxInstances: 3,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Passenger push target requires authentication.",
      );
    }

    return registerPassengerPushTargetAuthority(
      {firestore},
      request.auth.uid,
      request.data,
    );
  },
);

export const registerDriverPushTarget = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 15,
    memory: "256MiB",
    minInstances: 0,
    maxInstances: 3,
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError(
        "unauthenticated",
        "Driver push target requires authentication.",
      );
    }

    return registerDriverPushTargetAuthority(
      {firestore},
      request.auth.uid,
      request.data,
    );
  },
);
export const getActiveRideDriverTracking = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
    minInstances: 0,
    maxInstances: 3,
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError(
        "unauthenticated",
        "Canlı yolculuk konumu için giriş yapmalısınız.",
      );
    }

    return getActiveRideDriverTrackingForActor(
      {
        firestore,
        resolveEta: (input) =>
          getRideLiveTrackingEta(
            {
              firestore,
              computeDrivingMeasurement,
            },
            input,
          ),
      },
      request.auth.uid,
      request.data,
    );
  },
);
export const searchPlaces = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 15,
    memory: "256MiB",
    minInstances: 0,
    maxInstances: 3,
    secrets: [googlePlacesApiKey],
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError(
        "unauthenticated",
        "Oturum a\u00e7man\u0131z gerekiyor.",
      );
    }

    return searchPlacesWithPlacesApi(
      request.data,
      googlePlacesApiKey.value(),
    );
  },
);

export const resolvePlace = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 15,
    memory: "256MiB",
    minInstances: 0,
    maxInstances: 3,
    secrets: [googlePlacesApiKey],
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError(
        "unauthenticated",
        "Oturum a\u00e7man\u0131z gerekiyor.",
      );
    }

    return resolvePlaceWithPlacesApi(
      request.data,
      googlePlacesApiKey.value(),
    );
  },
);

export const onRideChatMessageCreated =
  onDocumentCreated(
    {
      document: "rides/{rideId}/messages/{messageId}",
      region: "europe-west1",
    },
    async (event) => {
      const snapshot =
        event.data;

      if (snapshot === undefined) {
        return;
      }

      await dispatchRideChatPushHint(
        {
          firestore,
          getMessaging: () => ({
            sendEachForMulticast: async (message) => {
              const response =
                await getMessaging()
                  .sendEachForMulticast({
                    tokens: message.fids,
                    data: {
                      ...message.data,
                    },
                  });

              return {
                successCount: response.successCount,
                failureCount: response.failureCount,
                responses: response.responses.map(
                  (item) => ({
                    success: item.success,
                    error: item.error === undefined ?
                      undefined :
                      {
                        code: item.error.code,
                      },
                  }),
                ),
              };
            },
          }),
          warn: (message) => {
            logger.warn(message);
          },
        },
        {
          rideId: event.params.rideId,
          messageId: event.params.messageId,
          messageData: snapshot.data(),
        },
      );
    },
  );

const RIDE_OFFER_HINT_TASK_QUEUE_TARGET =
  "locations/europe-west1/functions/dispatchRideOfferHintPage";

export const onRideBackgroundOfferHintWritten =
  onDocumentWritten(
    {
      document: "rides/{rideId}",
      region: "europe-west1",
      retry: true,
    },
    async (event) => {
      await enqueueRideBackgroundOfferInitialDispatch(
        {
          beforeValue:
            event.data?.before.data(),
          afterValue:
            event.data?.after.data(),
          eventId:
            event.id,
          eventTime:
            event.time,
          rideId:
            event.params.rideId,
        },
        {
          enqueueTask: (
            payload,
            taskId,
          ) =>
            getFunctions()
              .taskQueue(
                RIDE_OFFER_HINT_TASK_QUEUE_TARGET,
              )
              .enqueue(
                payload,
                {
                  id: taskId,
                },
              ),
        },
      );
    },
  );

export const dispatchRideOfferHintPage =
  onTaskDispatched(
    {
      region: "europe-west1",
      retryConfig: {
        maxAttempts:
          RIDE_OFFER_HINT_TASK_MAX_ATTEMPTS,
        minBackoffSeconds:
          RIDE_OFFER_HINT_TASK_MIN_BACKOFF_SECONDS,
        maxBackoffSeconds:
          RIDE_OFFER_HINT_TASK_MAX_BACKOFF_SECONDS,
      },
      rateLimits: {
        maxConcurrentDispatches:
          RIDE_OFFER_HINT_TASK_MAX_CONCURRENT_DISPATCHES,
        maxDispatchesPerSecond:
          RIDE_OFFER_HINT_TASK_MAX_DISPATCHES_PER_SECOND,
      },
      timeoutSeconds:
        RIDE_OFFER_HINT_TASK_TIMEOUT_SECONDS,
    },
    async (request) => {
      await executeRideOfferHintPageTask(
        request.data,
        {
          firestore,
          getTaskQueue: () => ({
            enqueue: (
              payload,
              options,
            ) =>
              getFunctions()
                .taskQueue(
                  RIDE_OFFER_HINT_TASK_QUEUE_TARGET,
                )
                .enqueue(
                  payload,
                  options,
                ),
          }),
          getMessaging: () => ({
            sendEachForMulticast: (
              message,
            ) =>
              getMessaging()
                .sendEachForMulticast(
                  message,
                ),
          }),
          warn: (message) => {
            logger.warn(message);
          },
        },
      );
    },
  );
