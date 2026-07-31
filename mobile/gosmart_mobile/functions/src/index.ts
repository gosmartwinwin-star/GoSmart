import {protos, v2} from "@googlemaps/routing";
import {
  HttpsError,
  onCall,
  onRequest,
} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

type CoordinateInput = {
  latitude: number;
  longitude: number;
};

type ComputeRouteInput = {
  origin: CoordinateInput;
  destination: CoordinateInput;
};

const routesClient = new v2.RoutesClient();
const routing = protos.google.maps.routing.v2;

const invalidCoordinatesError = () => new HttpsError(
  "invalid-argument",
  "Geçerli başlangıç ve varış koordinatları gereklidir.",
);

const validateCoordinate = (value: unknown): CoordinateInput => {
  if (typeof value !== "object" || value === null) {
    throw invalidCoordinatesError();
  }

  const coordinate = value as Record<string, unknown>;
  const {latitude, longitude} = coordinate;

  if (
    typeof latitude !== "number" ||
    typeof longitude !== "number" ||
    !Number.isFinite(latitude) ||
    !Number.isFinite(longitude) ||
    latitude < -90 ||
    latitude > 90 ||
    longitude < -180 ||
    longitude > 180
  ) {
    throw invalidCoordinatesError();
  }

  return {latitude, longitude};
};

const durationToSeconds = (
  duration: protos.google.protobuf.IDuration | null | undefined,
): number | null => {
  if (duration?.seconds === null || duration?.seconds === undefined) {
    return null;
  }

  const seconds = typeof duration.seconds === "number" ?
    duration.seconds :
    Number(duration.seconds.toString());
  const nanos = duration.nanos ?? 0;

  if (
    !Number.isFinite(seconds) ||
    !Number.isFinite(nanos) ||
    nanos < 0 ||
    nanos >= 1_000_000_000
  ) {
    return null;
  }

  const totalSeconds = seconds + nanos / 1_000_000_000;
  if (!Number.isFinite(totalSeconds) || totalSeconds < 0) {
    return null;
  }

  return Math.round(totalSeconds);
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

      if (
        origin.latitude === destination.latitude &&
        origin.longitude === destination.longitude
      ) {
        throw new HttpsError(
          "invalid-argument",
          "Başlangıç ve varış noktaları aynı olamaz.",
        );
      }

      const [response] = await routesClient.computeRoutes(
        {
          origin: {
            location: {
              latLng: {
                latitude: origin.latitude,
                longitude: origin.longitude,
              },
            },
          },
          destination: {
            location: {
              latLng: {
                latitude: destination.latitude,
                longitude: destination.longitude,
              },
            },
          },
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
