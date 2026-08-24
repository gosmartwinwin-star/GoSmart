export type RouteCoordinate = {
  latitude: number;
  longitude: number;
};

export type RouteAnchorPair = {
  pickupRouteIndex: number;
  dropoffRouteIndex: number;
  pickupAnchor: RouteCoordinate;
  dropoffAnchor: RouteCoordinate;
  pickupAnchorProximityMeters: number;
  dropoffAnchorProximityMeters: number;
};

const EARTH_RADIUS_METERS = 6371000;
const POLYLINE_PRECISION = 100000;
const MAX_POLYLINE_SHIFT = 30;

const validCoordinate = (
  value: unknown,
): value is RouteCoordinate => {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value)
  ) {
    return false;
  }

  const coordinate =
    value as Record<string, unknown>;

  return (
    typeof coordinate.latitude === "number" &&
    Number.isFinite(coordinate.latitude) &&
    coordinate.latitude >= -90 &&
    coordinate.latitude <= 90 &&
    typeof coordinate.longitude === "number" &&
    Number.isFinite(coordinate.longitude) &&
    coordinate.longitude >= -180 &&
    coordinate.longitude <= 180
  );
};

const requireCoordinate = (
  value: unknown,
  name: string,
): RouteCoordinate => {
  if (!validCoordinate(value)) {
    throw new TypeError(
      `Invalid ${name} coordinate.`,
    );
  }

  return value;
};

const radians = (
  degrees: number,
): number =>
  degrees * Math.PI / 180;

export const geoDistanceMeters = (
  firstValue: RouteCoordinate,
  secondValue: RouteCoordinate,
): number => {
  const first =
    requireCoordinate(
      firstValue,
      "first",
    );

  const second =
    requireCoordinate(
      secondValue,
      "second",
    );

  const latitudeDelta =
    radians(
      second.latitude -
        first.latitude,
    );

  const longitudeDelta =
    radians(
      second.longitude -
        first.longitude,
    );

  const firstLatitude =
    radians(first.latitude);

  const secondLatitude =
    radians(second.latitude);

  const sinLatitude =
    Math.sin(latitudeDelta / 2);

  const sinLongitude =
    Math.sin(longitudeDelta / 2);

  const raw =
    sinLatitude * sinLatitude +
    Math.cos(firstLatitude) *
      Math.cos(secondLatitude) *
      sinLongitude *
      sinLongitude;

  const haversine =
    Math.min(
      1,
      Math.max(0, raw),
    );

  const angularDistance =
    2 *
    Math.atan2(
      Math.sqrt(haversine),
      Math.sqrt(1 - haversine),
    );

  return (
    EARTH_RADIUS_METERS *
    angularDistance
  );
};

type DecodedValue = {
  value: number;
  nextIndex: number;
};

const decodePolylineValue = (
  encoded: string,
  startIndex: number,
): DecodedValue => {
  let index = startIndex;
  let result = 0;
  let shift = 0;

  let continuation = true;

  while (continuation) {
    if (index >= encoded.length) {
      throw new TypeError(
        "Malformed encoded polyline.",
      );
    }

    const code =
      encoded.charCodeAt(index);

    index += 1;

    if (
      code < 63 ||
      code > 126
    ) {
      throw new TypeError(
        "Malformed encoded polyline.",
      );
    }

    const chunk =
      code - 63;

    result +=
      (chunk & 0x1f) *
      2 ** shift;

    continuation =
      (chunk & 0x20) !== 0;

    if (!continuation) {
      continue;
    }

    shift += 5;

    if (shift > MAX_POLYLINE_SHIFT) {
      throw new TypeError(
        "Malformed encoded polyline.",
      );
    }
  }

  const value =
    result % 2 === 1 ?
      -(Math.floor(result / 2) + 1) :
      Math.floor(result / 2);

  return {
    value,
    nextIndex: index,
  };
};

export const decodeEncodedPolyline = (
  encoded: string,
): RouteCoordinate[] => {
  if (
    typeof encoded !== "string" ||
    encoded.length === 0 ||
    encoded.length > 100000
  ) {
    throw new TypeError(
      "Invalid encoded polyline.",
    );
  }

  const points: RouteCoordinate[] = [];

  let index = 0;
  let latitude = 0;
  let longitude = 0;

  while (index < encoded.length) {
    const decodedLatitude =
      decodePolylineValue(
        encoded,
        index,
      );

    index =
      decodedLatitude.nextIndex;

    const decodedLongitude =
      decodePolylineValue(
        encoded,
        index,
      );

    index =
      decodedLongitude.nextIndex;

    latitude +=
      decodedLatitude.value;

    longitude +=
      decodedLongitude.value;

    const point = {
      latitude:
        latitude /
        POLYLINE_PRECISION,
      longitude:
        longitude /
        POLYLINE_PRECISION,
    };

    if (!validCoordinate(point)) {
      throw new TypeError(
        "Decoded polyline coordinate is invalid.",
      );
    }

    points.push(point);
  }

  if (points.length < 2) {
    throw new TypeError(
      "Decoded route must contain at least two points.",
    );
  }

  return points;
};

export const locateRouteAnchors = (
  routePointsValue: readonly RouteCoordinate[],
  pickupValue: RouteCoordinate,
  dropoffValue: RouteCoordinate,
): RouteAnchorPair => {
  if (
    !Array.isArray(routePointsValue) ||
    routePointsValue.length < 2
  ) {
    throw new TypeError(
      "Calculated route requires at least two points.",
    );
  }

  const routePoints =
    routePointsValue.map(
      (point, index) =>
        requireCoordinate(
          point,
          `routePoints[${index}]`,
        ),
    );

  const pickup =
    requireCoordinate(
      pickupValue,
      "pickup",
    );

  const dropoff =
    requireCoordinate(
      dropoffValue,
      "dropoff",
    );

  let pickupRouteIndex = 0;
  let dropoffRouteIndex = 0;

  let pickupAnchor =
    routePoints[0];

  let dropoffAnchor =
    routePoints[0];

  let pickupAnchorProximityMeters =
    geoDistanceMeters(
      pickup,
      pickupAnchor,
    );

  let dropoffAnchorProximityMeters =
    geoDistanceMeters(
      dropoff,
      dropoffAnchor,
    );

  for (
    let index = 1;
    index < routePoints.length;
    index += 1
  ) {
    const routePoint =
      routePoints[index];

    const pickupCandidate =
      geoDistanceMeters(
        pickup,
        routePoint,
      );

    const dropoffCandidate =
      geoDistanceMeters(
        dropoff,
        routePoint,
      );

    // Flutter RouteAnchorLocator uses strict "<".
    // Equal proximity therefore keeps the first index.
    if (
      pickupCandidate <
      pickupAnchorProximityMeters
    ) {
      pickupRouteIndex = index;
      pickupAnchor = routePoint;
      pickupAnchorProximityMeters =
        pickupCandidate;
    }

    if (
      dropoffCandidate <
      dropoffAnchorProximityMeters
    ) {
      dropoffRouteIndex = index;
      dropoffAnchor = routePoint;
      dropoffAnchorProximityMeters =
        dropoffCandidate;
    }
  }

  return {
    pickupRouteIndex,
    dropoffRouteIndex,
    pickupAnchor,
    dropoffAnchor,
    pickupAnchorProximityMeters,
    dropoffAnchorProximityMeters,
  };
};

export const routeAnchorDirectionCompatible = (
  anchors: RouteAnchorPair,
): boolean =>
  anchors.pickupRouteIndex <
  anchors.dropoffRouteIndex;
