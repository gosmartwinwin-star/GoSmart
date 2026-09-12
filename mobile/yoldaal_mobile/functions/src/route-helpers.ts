import {protos, v2} from "@googlemaps/routing";
import {HttpsError} from "firebase-functions/v2/https";

export type CoordinateInput = {
  latitude: number;
  longitude: number;
};

const invalidCoordinatesError = () => new HttpsError(
  "invalid-argument",
  "Geçerli koordinatlar gereklidir.",
);

export const validateCoordinate = (value: unknown): CoordinateInput => {
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

export const validateRouteIndex = (value: unknown): number => {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
    throw new HttpsError(
      "invalid-argument",
      "Geçerli rota indeksleri gereklidir.",
    );
  }

  return value;
};

export const validateDirection = (
  pickupRouteIndex: number,
  dropoffRouteIndex: number,
): void => {
  if (pickupRouteIndex >= dropoffRouteIndex) {
    throw new HttpsError(
      "failed-precondition",
      "Rota noktalarının yön sırası uyumlu değildir.",
      {reason: "incompatible_direction"},
    );
  }
};

export const coordinatesEqual = (
  first: CoordinateInput,
  second: CoordinateInput,
): boolean => first.latitude === second.latitude &&
  first.longitude === second.longitude;

export const durationToSeconds = (
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

export const validateNonNegativeInteger = (
  value: unknown,
): number | null => typeof value === "number" &&
  Number.isInteger(value) &&
  value >= 0 ? value : null;
export type TrafficAwareDrivingMeasurement = {
  distanceMeters: number;
  durationSeconds: number;
};

export const computeTrafficAwareDrivingMeasurement = async (
  routesClient: v2.RoutesClient,
  origin: CoordinateInput,
  destination: CoordinateInput,
): Promise<TrafficAwareDrivingMeasurement> => {
  if (coordinatesEqual(origin, destination)) {
    return {
      distanceMeters: 0,
      durationSeconds: 0,
    };
  }

  const routing = protos.google.maps.routing.v2;

  const toWaypoint = (coordinate: CoordinateInput) => ({
    location: {
      latLng: {
        latitude: coordinate.latitude,
        longitude: coordinate.longitude,
      },
    },
  });

  const [response] = await routesClient.computeRoutes(
    {
      origin: toWaypoint(origin),
      destination: toWaypoint(destination),
      travelMode: routing.RouteTravelMode.DRIVE,
      routingPreference:
        routing.RoutingPreference.TRAFFIC_AWARE,
      computeAlternativeRoutes: false,
      languageCode: "tr-TR",
      regionCode: "TR",
      units: routing.Units.METRIC,
    },
    {
      otherArgs: {
        headers: {
          "X-Goog-FieldMask":
            "routes.duration,routes.distanceMeters",
        },
      },
    },
  );

  const route = response.routes?.[0];

  const distanceMeters =
    validateNonNegativeInteger(route?.distanceMeters);

  const durationSeconds =
    durationToSeconds(route?.duration);

  if (
    distanceMeters === null ||
    durationSeconds === null
  ) {
    throw new HttpsError(
      "internal",
      "Sürüş sapması ölçümü tamamlanamadı.",
    );
  }

  return {
    distanceMeters,
    durationSeconds,
  };
};
export type TrafficAwareDrivingRoute = {
  distanceMeters: number;
  durationSeconds: number;
  encodedPolyline: string;
};

export const computeTrafficAwareDrivingRoute = async (
  routesClient: v2.RoutesClient,
  origin: CoordinateInput,
  destination: CoordinateInput,
): Promise<TrafficAwareDrivingRoute> => {
  const routing = protos.google.maps.routing.v2;

  const toWaypoint = (coordinate: CoordinateInput) => ({
    location: {
      latLng: {
        latitude: coordinate.latitude,
        longitude: coordinate.longitude,
      },
    },
  });

  const [response] = await routesClient.computeRoutes(
    {
      origin: toWaypoint(origin),
      destination: toWaypoint(destination),
      travelMode: routing.RouteTravelMode.DRIVE,
      routingPreference:
        routing.RoutingPreference.TRAFFIC_AWARE,
      computeAlternativeRoutes: false,
      polylineQuality:
        routing.PolylineQuality.OVERVIEW,
      polylineEncoding:
        routing.PolylineEncoding.ENCODED_POLYLINE,
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

  const distanceMeters = route?.distanceMeters;
  const durationSeconds =
    durationToSeconds(route?.duration);
  const encodedPolyline =
    route?.polyline?.encodedPolyline;

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

  return {
    distanceMeters,
    durationSeconds,
    encodedPolyline,
  };
};
