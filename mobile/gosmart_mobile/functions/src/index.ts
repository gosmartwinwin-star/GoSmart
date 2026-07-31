import {protos, v2} from "@googlemaps/routing";
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

const routesClient = new v2.RoutesClient();
const routing = protos.google.maps.routing.v2;

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
