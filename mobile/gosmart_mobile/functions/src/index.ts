import {protos, v2} from "@googlemaps/routing";
import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {
  HttpsError,
  onCall,
  onRequest,
} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {
  CoordinateInput,
  coordinatesEqual,
  durationToSeconds,
  validateCoordinate,
  validateDirection,
  validateNonNegativeInteger,
  validateRouteIndex,
} from "./route-helpers.js";
import {
  isActivePass,
  requireExactKeys,
  validateProfileStatus,
  validateRouteValidity,
} from "./driver-access-helpers.js";

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

const routesClient = new v2.RoutesClient();
const routing = protos.google.maps.routing.v2;
const firestore = getFirestore(getApps()[0] ?? initializeApp());

const toWaypoint = (coordinate: CoordinateInput) => ({
  location: {
    latLng: {
      latitude: coordinate.latitude,
      longitude: coordinate.longitude,
    },
  },
});

const computeDrivingMeasurement = async (
  origin: CoordinateInput,
  destination: CoordinateInput,
): Promise<{distanceMeters: number; durationSeconds: number}> => {
  if (coordinatesEqual(origin, destination)) {
    return {distanceMeters: 0, durationSeconds: 0};
  }

  const [response] = await routesClient.computeRoutes(
    {
      origin: toWaypoint(origin),
      destination: toWaypoint(destination),
      travelMode: routing.RouteTravelMode.DRIVE,
      routingPreference: routing.RoutingPreference.TRAFFIC_AWARE,
      computeAlternativeRoutes: false,
      languageCode: "tr-TR",
      regionCode: "TR",
      units: routing.Units.METRIC,
    },
    {
      otherArgs: {
        headers: {
          "X-Goog-FieldMask": "routes.duration,routes.distanceMeters",
        },
      },
    },
  );

  const route = response.routes?.[0];
  const distanceMeters = validateNonNegativeInteger(route?.distanceMeters);
  const durationSeconds = durationToSeconds(route?.duration);

  if (distanceMeters === null || durationSeconds === null) {
    throw new HttpsError(
      "internal",
      "Sürüş sapması ölçümü tamamlanamadı.",
    );
  }

  return {distanceMeters, durationSeconds};
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

  const passQuery = firestore.collection("driverAccessPasses")
    .where("driverId", "==", profile.id)
    .orderBy("purchasedAt", "desc")
    .limit(1);
  const passes = await getDocuments(passQuery);
  if (passes.empty || !isActivePass(passes.docs[0].data(), now)) {
    throw safePrecondition("subscription_required");
  }
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

const computePublishedRoute = async (
  origin: CoordinateInput,
  destination: CoordinateInput,
): Promise<{
  distanceMeters: number;
  durationSeconds: number;
  encodedPolyline: string;
}> => {
  const [response] = await routesClient.computeRoutes({
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
  }, {
    otherArgs: {headers: {"X-Goog-FieldMask":
      "routes.duration,routes.distanceMeters," +
      "routes.polyline.encodedPolyline"}},
  });
  const route = response.routes?.[0];
  const distanceMeters = route?.distanceMeters;
  const durationSeconds = durationToSeconds(route?.duration);
  const encodedPolyline = route?.polyline?.encodedPolyline;
  if (
    typeof distanceMeters !== "number" ||
    !Number.isInteger(distanceMeters) ||
    distanceMeters <= 0 ||
    durationSeconds === null ||
    !Number.isInteger(durationSeconds) ||
    durationSeconds <= 0 ||
    typeof encodedPolyline !== "string" ||
    encodedPolyline.length === 0
  ) {
    throw new Error("Invalid route response");
  }
  return {distanceMeters, durationSeconds, encodedPolyline};
};

export const healthCheck = onRequest(
  {
    region: "europe-west1",
  },
  (request, response) => {
    logger.info("GoSmart functions health check", {
      method: request.method,
    });
    response.status(200).json({
      success: true,
      service: "gosmart-functions",
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

    const uid = request.auth.uid;

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

      logger.info("GoSmart route computed", {uid});

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
        uid,
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

    const uid = request.auth.uid;

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

      logger.info("GoSmart route deviation computed", {uid});

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
        uid,
        errorType: error instanceof Error ? error.name : "UnknownError",
      });

      throw new HttpsError(
        "unavailable",
        "Sürüş sapması servisine şu anda ulaşılamıyor.",
      );
    }
  },
);

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
    try {
      routeMeasurement = await computePublishedRoute(
        input.origin,
        input.destination,
      );
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
