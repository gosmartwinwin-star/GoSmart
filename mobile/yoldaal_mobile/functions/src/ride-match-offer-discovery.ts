import {
  DocumentSnapshot,
  Firestore,
  QueryDocumentSnapshot,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  requireDriverAccess,
  requireDriverAccessInTransaction,
} from "./driver-access-authority.js";
import {
  loadApprovedDriverId,
  loadApprovedDriverIdInTransaction,
} from "./ride-driver-identity.js";
import {
  RETURN_ROUTE_MATCH_MAX_DETOUR_METERS,
  RETURN_ROUTE_MATCH_MAX_DETOUR_SECONDS,
  buildRideMatchOffer,
  isRideMatchMeasurementEligible,
  parseRideMatchOffer,
  rideMatchOfferDocumentId,
} from "./ride-match-offer-helpers.js";
import type {
  RideMatchMeasurement,
  RideMatchOfferRecord,
} from "./ride-match-offer-helpers.js";
import {
  decodeEncodedPolyline,
  geoDistanceMeters,
  locateRouteAnchors,
  routeAnchorDirectionCompatible,
} from "./ride-route-geometry.js";
import type {
  RouteAnchorPair,
  RouteCoordinate,
} from "./ride-route-geometry.js";

export const RIDE_MATCH_DISCOVERY_CANDIDATE_LIMIT = 5;
export const RIDE_MATCH_DISCOVERY_OFFER_LIMIT = 3;

export const RIDE_MATCH_DISCOVERY_AGING_THRESHOLD_SECONDS =
  15 * 60;

export const RIDE_MATCH_DISCOVERY_FAIRNESS_SLOT_LIMIT = 2;

export const RIDE_MATCH_DISCOVERY_BEST_ROUTE_SLOT_LIMIT = 3;

export type RideMatchDeviationInput = {
  pickupAnchor: RouteCoordinate;
  pickup: RouteCoordinate;
  dropoff: RouteCoordinate;
  dropoffAnchor: RouteCoordinate;
  pickupRouteIndex: number;
  dropoffRouteIndex: number;
};

export type RideMatchDeviationMeasurement = {
  pickupDetourMeters: number;
  pickupDetourSeconds: number;
  dropoffDetourMeters: number;
  dropoffDetourSeconds: number;
};

export type RideMatchOfferDiscoveryDependencies = {
  firestore: Firestore;
  measureDeviation: (
    input: RideMatchDeviationInput,
  ) => Promise<RideMatchDeviationMeasurement>;
  now?: () => Timestamp;
};

export type DiscoveredRideLocation = {
  latitude: number;
  longitude: number;
  addressLabel: string;
};

export type MatchingRideCandidate = {
  rideId: string;
  passengerId: string;
  version: number;
  createdAt: Timestamp;
  pickup: DiscoveredRideLocation;
  dropoff: DiscoveredRideLocation;
  passengerTripDistanceMeters: number;
  passengerTripDurationSeconds: number;
};

export type PublicDiscoveredRideOffer = {
  rideId: string;
  rideVersion: number;
  pickup: DiscoveredRideLocation;
  dropoff: DiscoveredRideLocation;
  pickupDetourMeters: number;
  pickupDetourSeconds: number;
  dropoffDetourMeters: number;
  dropoffDetourSeconds: number;
  passengerTripDistanceMeters: number;
  passengerTripDurationSeconds: number;
  expiresAtMillis: number;
};

export type RideMatchOfferDiscoveryResult = {
  offers: PublicDiscoveredRideOffer[];
};

type ValidatedReturnRoute = {
  origin: RouteCoordinate;
  destination: RouteCoordinate;
  encodedPolyline: string;
};

type ActiveReturnRouteContext = {
  driverId: string;
  returnRouteId: string;
  expiresAt: Timestamp;
  origin: RouteCoordinate;
  destination: RouteCoordinate;
  routePoints: RouteCoordinate[];
};

type ActiveReturnRouteLock = {
  routeId: string;
  activatedAt: Timestamp;
  expiresAt: Timestamp;
};

export type PreparedRideMatchCandidate = {
  candidate: MatchingRideCandidate;
  anchors: RouteAnchorPair;
};

export type SelectedRideMatchCandidate =
  PreparedRideMatchCandidate & {
    fairnessProtected: boolean;
  };

export type EvaluatedCandidate = {
  candidate: MatchingRideCandidate;
  measurement: RideMatchMeasurement;
  fairnessProtected: boolean;
};

const compareAscendingNumber = (
  first: number,
  second: number,
): number =>
  first < second ?
    -1 :
    first > second ?
      1 :
      0;

const compareAscendingString = (
  first: string,
  second: string,
): number =>
  first < second ?
    -1 :
    first > second ?
      1 :
      0;

const compareCandidateFairness = (
  first: MatchingRideCandidate,
  second: MatchingRideCandidate,
): number => {
  const createdAtOrder =
    compareAscendingNumber(
      first.createdAt.toMillis(),
      second.createdAt.toMillis(),
    );

  if (createdAtOrder !== 0) {
    return createdAtOrder;
  }

  return compareAscendingString(
    first.rideId,
    second.rideId,
  );
};

const cheapRouteQuality = (
  item: PreparedRideMatchCandidate,
): {
  worst: number;
  total: number;
} => {
  const pickupQuality =
    item.anchors.pickupAnchorProximityMeters /
    RETURN_ROUTE_MATCH_MAX_DETOUR_METERS;

  const dropoffQuality =
    item.anchors.dropoffAnchorProximityMeters /
    RETURN_ROUTE_MATCH_MAX_DETOUR_METERS;

  return {
    worst: Math.max(
      pickupQuality,
      dropoffQuality,
    ),
    total:
      pickupQuality +
      dropoffQuality,
  };
};

const compareCheapRouteQuality = (
  first: PreparedRideMatchCandidate,
  second: PreparedRideMatchCandidate,
): number => {
  const firstQuality =
    cheapRouteQuality(first);

  const secondQuality =
    cheapRouteQuality(second);

  const worstOrder =
    compareAscendingNumber(
      firstQuality.worst,
      secondQuality.worst,
    );

  if (worstOrder !== 0) {
    return worstOrder;
  }

  const totalOrder =
    compareAscendingNumber(
      firstQuality.total,
      secondQuality.total,
    );

  if (totalOrder !== 0) {
    return totalOrder;
  }

  return compareCandidateFairness(
    first.candidate,
    second.candidate,
  );
};

const measuredRouteQuality = (
  item: EvaluatedCandidate,
): {
  worst: number;
  total: number;
} => {
  const pickupMetersRatio =
    item.measurement.pickupDetourMeters /
    RETURN_ROUTE_MATCH_MAX_DETOUR_METERS;

  const pickupSecondsRatio =
    item.measurement.pickupDetourSeconds /
    RETURN_ROUTE_MATCH_MAX_DETOUR_SECONDS;

  const dropoffMetersRatio =
    item.measurement.dropoffDetourMeters /
    RETURN_ROUTE_MATCH_MAX_DETOUR_METERS;

  const dropoffSecondsRatio =
    item.measurement.dropoffDetourSeconds /
    RETURN_ROUTE_MATCH_MAX_DETOUR_SECONDS;

  return {
    worst: Math.max(
      pickupMetersRatio,
      pickupSecondsRatio,
      dropoffMetersRatio,
      dropoffSecondsRatio,
    ),
    total:
      pickupMetersRatio +
      pickupSecondsRatio +
      dropoffMetersRatio +
      dropoffSecondsRatio,
  };
};

const compareMeasuredRouteQuality = (
  first: EvaluatedCandidate,
  second: EvaluatedCandidate,
): number => {
  const firstQuality =
    measuredRouteQuality(first);

  const secondQuality =
    measuredRouteQuality(second);

  const worstOrder =
    compareAscendingNumber(
      firstQuality.worst,
      secondQuality.worst,
    );

  if (worstOrder !== 0) {
    return worstOrder;
  }

  const totalOrder =
    compareAscendingNumber(
      firstQuality.total,
      secondQuality.total,
    );

  if (totalOrder !== 0) {
    return totalOrder;
  }

  return compareCandidateFairness(
    first.candidate,
    second.candidate,
  );
};

export const isRideMatchCandidateAged = (
  candidate: MatchingRideCandidate,
  now: Timestamp,
): boolean =>
  now.toMillis() -
    candidate.createdAt.toMillis() >=
  RIDE_MATCH_DISCOVERY_AGING_THRESHOLD_SECONDS *
    1000;

export const isRideMatchCheapEndpointEligible = (
  origin: RouteCoordinate,
  destination: RouteCoordinate,
  candidate: MatchingRideCandidate,
): boolean =>
  geoDistanceMeters(
    origin,
    candidate.pickup,
  ) <=
    RETURN_ROUTE_MATCH_MAX_DETOUR_METERS &&
  geoDistanceMeters(
    candidate.dropoff,
    destination,
  ) <=
    RETURN_ROUTE_MATCH_MAX_DETOUR_METERS;

export const selectRideMatchPromisingCandidates = (
  candidates: PreparedRideMatchCandidate[],
  now: Timestamp,
): SelectedRideMatchCandidate[] => {
  const fairnessCandidates =
    [...candidates]
      .filter(
        (item) =>
          isRideMatchCandidateAged(
            item.candidate,
            now,
          ),
      )
      .sort(
        (first, second) =>
          compareCandidateFairness(
            first.candidate,
            second.candidate,
          ),
      )
      .slice(
        0,
        RIDE_MATCH_DISCOVERY_FAIRNESS_SLOT_LIMIT,
      );

  const fairnessRideIds =
    new Set(
      fairnessCandidates.map(
        (item) =>
          item.candidate.rideId,
      ),
    );

  const unusedFairnessSlots =
    RIDE_MATCH_DISCOVERY_FAIRNESS_SLOT_LIMIT -
    fairnessCandidates.length;

  const bestRouteSlots =
    RIDE_MATCH_DISCOVERY_BEST_ROUTE_SLOT_LIMIT +
    unusedFairnessSlots;

  const bestRouteCandidates =
    [...candidates]
      .filter(
        (item) =>
          !fairnessRideIds.has(
            item.candidate.rideId,
          ),
      )
      .sort(compareCheapRouteQuality)
      .slice(
        0,
        bestRouteSlots,
      );

  return [
    ...fairnessCandidates.map(
      (item) => ({
        ...item,
        fairnessProtected: true,
      }),
    ),
    ...bestRouteCandidates.map(
      (item) => ({
        ...item,
        fairnessProtected: false,
      }),
    ),
  ];
};

export const rankRideMatchEligibleOffers = (
  candidates: EvaluatedCandidate[],
): EvaluatedCandidate[] => {
  const protectedCandidates =
    [...candidates]
      .filter(
        (item) =>
          item.fairnessProtected,
      )
      .sort(
        (first, second) =>
          compareCandidateFairness(
            first.candidate,
            second.candidate,
          ),
      )
      .slice(
        0,
        RIDE_MATCH_DISCOVERY_FAIRNESS_SLOT_LIMIT,
      );

  const protectedRideIds =
    new Set(
      protectedCandidates.map(
        (item) =>
          item.candidate.rideId,
      ),
    );

  const remainingOfferSlots =
    RIDE_MATCH_DISCOVERY_OFFER_LIMIT -
    protectedCandidates.length;

  const routeCandidates =
    [...candidates]
      .filter(
        (item) =>
          !protectedRideIds.has(
            item.candidate.rideId,
          ),
      )
      .sort(compareMeasuredRouteQuality)
      .slice(
        0,
        remainingOfferSlots,
      );

  return [
    ...protectedCandidates,
    ...routeCandidates,
  ];
};
const failure = (
  reason: string,
): HttpsError =>
  new HttpsError(
    "failed-precondition",
    "Yolculuk eslesme kosullari saglanmiyor.",
    {reason},
  );

const internalFailure = (
  reason: string,
): HttpsError =>
  new HttpsError(
    "internal",
    "Yolculuk eslesmesi tamamlanamadi.",
    {reason},
  );

const isRecord = (
  value: unknown,
): value is Record<string, unknown> =>
  typeof value === "object" &&
  value !== null &&
  !Array.isArray(value);

const isIdentifier = (
  value: unknown,
): value is string =>
  typeof value === "string" &&
  value.length > 0 &&
  value.length <= 1500 &&
  !value.includes("/");

const isPositiveInteger = (
  value: unknown,
): value is number =>
  typeof value === "number" &&
  Number.isInteger(value) &&
  value > 0;

const isNonNegativeInteger = (
  value: unknown,
): value is number =>
  typeof value === "number" &&
  Number.isInteger(value) &&
  value >= 0;

const parseRouteCoordinate = (
  value: unknown,
): RouteCoordinate | null => {
  if (!isRecord(value)) {
    return null;
  }

  const {latitude, longitude} = value;

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

  return {latitude, longitude};
};

const parseLocation = (
  value: unknown,
): DiscoveredRideLocation | null => {
  if (!isRecord(value)) {
    return null;
  }

  const {
    latitude,
    longitude,
    addressLabel,
  } = value;

  if (
    typeof latitude !== "number" ||
    !Number.isFinite(latitude) ||
    latitude < -90 ||
    latitude > 90 ||
    typeof longitude !== "number" ||
    !Number.isFinite(longitude) ||
    longitude < -180 ||
    longitude > 180 ||
    typeof addressLabel !== "string"
  ) {
    return null;
  }

  const normalizedLabel =
    addressLabel.trim();

  if (
    normalizedLabel.length === 0 ||
    normalizedLabel.length > 300
  ) {
    return null;
  }

  return {
    latitude,
    longitude,
    addressLabel: normalizedLabel,
  };
};

export const parseMatchingRideCandidate = (
  rideId: string,
  data: Record<string, unknown>,
): MatchingRideCandidate | null => {
  if (
    !isIdentifier(rideId) ||
    data.status !== "matching" ||
    data.driverId !== null ||
    !isIdentifier(data.passengerId) ||
    !isPositiveInteger(data.version) ||
    !(data.createdAt instanceof Timestamp)
  ) {
    return null;
  }

  const pickup =
    parseLocation(data.pickup);

  const dropoff =
    parseLocation(data.dropoff);

  if (
    pickup === null ||
    dropoff === null
  ) {
    return null;
  }

  const routeValue = data.route;

  if (
    routeValue === null ||
    typeof routeValue !== "object" ||
    Array.isArray(routeValue)
  ) {
    return null;
  }

  const route =
    routeValue as Record<string, unknown>;

  if (
    !isPositiveInteger(route.distanceMeters) ||
    !isPositiveInteger(route.durationSeconds)
  ) {
    return null;
  }

  return {
    rideId,
    passengerId: data.passengerId,
    version: data.version,
    createdAt: data.createdAt,
    pickup,
    dropoff,
    passengerTripDistanceMeters:
      route.distanceMeters,
    passengerTripDurationSeconds:
      route.durationSeconds,
  };
};

const parseMatchingRideDocument = (
  snapshot: QueryDocumentSnapshot,
): MatchingRideCandidate | null =>
  parseMatchingRideCandidate(
    snapshot.id,
    snapshot.data(),
  );

const locationsEqual = (
  first: DiscoveredRideLocation,
  second: DiscoveredRideLocation,
): boolean =>
  first.latitude === second.latitude &&
  first.longitude === second.longitude;

const parseActiveRouteLock = (
  snapshot: DocumentSnapshot,
  now: Timestamp,
  expectedRouteId?: string,
): ActiveReturnRouteLock => {
  if (!snapshot.exists) {
    throw failure(
      "active_return_route_required",
    );
  }

  const routeId =
    snapshot.get("routeId");

  const activatedAt =
    snapshot.get("activatedAt");

  const expiresAt =
    snapshot.get("expiresAt");

  if (
    !isIdentifier(routeId) ||
    !(activatedAt instanceof Timestamp) ||
    !(expiresAt instanceof Timestamp) ||
    expiresAt.toMillis() <=
      activatedAt.toMillis()
  ) {
    throw failure(
      "active_return_route_invalid",
    );
  }

  if (
    expectedRouteId !== undefined &&
    routeId !== expectedRouteId
  ) {
    throw failure(
      "active_return_route_changed",
    );
  }

  if (
    now.toMillis() <
      activatedAt.toMillis() ||
    now.toMillis() >=
      expiresAt.toMillis()
  ) {
    throw failure(
      "active_return_route_expired",
    );
  }

  return {
    routeId,
    activatedAt,
    expiresAt,
  };
};

const validateReturnRoute = (
  snapshot: DocumentSnapshot,
  driverId: string,
  lock: ActiveReturnRouteLock,
  now: Timestamp,
): ValidatedReturnRoute => {
  if (!snapshot.exists) {
    throw failure(
      "active_return_route_invalid",
    );
  }

  const routeDriverId =
    snapshot.get("driverId");

  const status =
    snapshot.get("status");

  const activatedAt =
    snapshot.get("activatedAt");

  const expiresAt =
    snapshot.get("expiresAt");

  const distanceMeters =
    snapshot.get("routeDistanceMeters");

  const durationSeconds =
    snapshot.get("routeDurationSeconds");

  const encodedPolyline =
    snapshot.get("encodedPolyline");

  const origin =
    parseRouteCoordinate(
      snapshot.get("origin"),
    );

  const destination =
    parseRouteCoordinate(
      snapshot.get("destination"),
    );

  if (
    routeDriverId !== driverId ||
    status !== "active" ||
    !(activatedAt instanceof Timestamp) ||
    !(expiresAt instanceof Timestamp) ||
    activatedAt.toMillis() !==
      lock.activatedAt.toMillis() ||
    expiresAt.toMillis() !==
      lock.expiresAt.toMillis() ||
    !isPositiveInteger(distanceMeters) ||
    !isPositiveInteger(durationSeconds) ||
    typeof encodedPolyline !== "string" ||
    encodedPolyline.length === 0 ||
    origin === null ||
    destination === null
  ) {
    throw failure(
      "active_return_route_invalid",
    );
  }

  if (
    now.toMillis() <
      activatedAt.toMillis() ||
    now.toMillis() >=
      expiresAt.toMillis()
  ) {
    throw failure(
      "active_return_route_expired",
    );
  }

  return {
    origin,
    destination,
    encodedPolyline,
  };
};

const decodeReturnRoute = (
  encodedPolyline: string,
): RouteCoordinate[] => {
  try {
    return decodeEncodedPolyline(
      encodedPolyline,
    );
  } catch {
    throw failure(
      "active_return_route_invalid",
    );
  }
};

const requireActivePass = async (
  firestore: Firestore,
  driverId: string,
  now: Timestamp,
): Promise<void> => {
  await requireDriverAccess({
    firestore,
    driverId,
    now,
    failure,
  });
};

const loadInitialContext = async (
  firestore: Firestore,
  uid: string,
  now: Timestamp,
): Promise<ActiveReturnRouteContext> => {
  const driverId =
    await loadApprovedDriverId(
      firestore,
      uid,
    );

  await requireActivePass(
    firestore,
    driverId,
    now,
  );

  const driverActiveRide =
    await firestore
      .collection("driverActiveRides")
      .doc(driverId)
      .get();

  if (driverActiveRide.exists) {
    throw failure(
      "driver_active_ride_exists",
    );
  }

  const lockSnapshot =
    await firestore
      .collection("driverActiveReturnRoutes")
      .doc(driverId)
      .get();

  const lock =
    parseActiveRouteLock(
      lockSnapshot,
      now,
    );

  const returnRouteSnapshot =
    await firestore
      .collection("driverReturnRoutes")
      .doc(lock.routeId)
      .get();

  const returnRoute =
    validateReturnRoute(
      returnRouteSnapshot,
      driverId,
      lock,
      now,
    );

  return {
    driverId,
    returnRouteId: lock.routeId,
    expiresAt: lock.expiresAt,
    origin: returnRoute.origin,
    destination: returnRoute.destination,
    routePoints:
      decodeReturnRoute(
        returnRoute.encodedPolyline,
      ),
  };
};

const revalidateContextInTransaction = async (
  firestore: Firestore,
  transaction: Transaction,
  uid: string,
  expectedDriverId: string,
  expectedReturnRouteId: string,
  now: Timestamp,
): Promise<ActiveReturnRouteLock> => {
  const driverId =
    await loadApprovedDriverIdInTransaction(
      firestore,
      uid,
      transaction,
    );

  if (driverId !== expectedDriverId) {
    throw failure(
      "driver_identity_changed",
    );
  }

  await requireDriverAccessInTransaction({
    firestore,
    transaction,
    driverId,
    now,
    failure,
  });

  const driverActiveRide =
    await transaction.get(
      firestore
        .collection("driverActiveRides")
        .doc(driverId),
    );

  if (driverActiveRide.exists) {
    throw failure(
      "driver_active_ride_exists",
    );
  }

  const lock =
    parseActiveRouteLock(
      await transaction.get(
        firestore
          .collection("driverActiveReturnRoutes")
          .doc(driverId),
      ),
      now,
      expectedReturnRouteId,
    );

  const routeSnapshot =
    await transaction.get(
      firestore
        .collection("driverReturnRoutes")
        .doc(lock.routeId),
    );

  validateReturnRoute(
    routeSnapshot,
    driverId,
    lock,
    now,
  );

  return lock;
};

const parseDeviationMeasurement = (
  value: RideMatchDeviationMeasurement,
): RideMatchDeviationMeasurement => {
  if (
    !isNonNegativeInteger(
      value.pickupDetourMeters,
    ) ||
    !isNonNegativeInteger(
      value.pickupDetourSeconds,
    ) ||
    !isNonNegativeInteger(
      value.dropoffDetourMeters,
    ) ||
    !isNonNegativeInteger(
      value.dropoffDetourSeconds,
    )
  ) {
    throw internalFailure(
      "ride_match_measurement_invalid",
    );
  }

  return value;
};

export const toPublicDiscoveredRideOffer = (
  candidate: MatchingRideCandidate,
  offer: RideMatchOfferRecord,
): PublicDiscoveredRideOffer => ({
  rideId: candidate.rideId,
  rideVersion: candidate.version,
  pickup: candidate.pickup,
  dropoff: candidate.dropoff,
  pickupDetourMeters:
    offer.measurement.pickupDetourMeters,
  pickupDetourSeconds:
    offer.measurement.pickupDetourSeconds,
  dropoffDetourMeters:
    offer.measurement.dropoffDetourMeters,
  dropoffDetourSeconds:
    offer.measurement.dropoffDetourSeconds,
  passengerTripDistanceMeters:
    candidate.passengerTripDistanceMeters,
  passengerTripDurationSeconds:
    candidate.passengerTripDurationSeconds,
  expiresAtMillis:
    offer.expiresAt.toMillis(),
});

export const discoverRideMatchOffersForDriver = async (
  dependencies: RideMatchOfferDiscoveryDependencies,
  uid: string,
): Promise<RideMatchOfferDiscoveryResult> => {
  if (!isIdentifier(uid)) {
    throw new HttpsError(
      "unauthenticated",
      "Surucu oturumu gereklidir.",
    );
  }

  const nowProvider =
    dependencies.now ??
    (() => Timestamp.now());

  const initialNow =
    nowProvider();

  const context =
    await loadInitialContext(
      dependencies.firestore,
      uid,
      initialNow,
    );

  const candidateSnapshots =
    await dependencies.firestore
      .collection("rides")
      .where(
        "status",
        "==",
        "matching",
      )
      .get();

  const cheapEligibleCandidates:
    PreparedRideMatchCandidate[] = [];

  for (
    const snapshot of candidateSnapshots.docs
  ) {
    const candidate =
      parseMatchingRideDocument(snapshot);

    if (
      candidate === null ||
      candidate.passengerId === uid
    ) {
      continue;
    }

    if (
      !isRideMatchCheapEndpointEligible(
        context.origin,
        context.destination,
        candidate,
      )
    ) {
      continue;
    }

    const anchors =
      locateRouteAnchors(
        context.routePoints,
        candidate.pickup,
        candidate.dropoff,
      );

    if (
      !routeAnchorDirectionCompatible(
        anchors,
      )
    ) {
      continue;
    }

    cheapEligibleCandidates.push({
      candidate,
      anchors,
    });
  }

  const selectedCandidates =
    selectRideMatchPromisingCandidates(
      cheapEligibleCandidates,
      initialNow,
    );

  const evaluated: EvaluatedCandidate[] = [];

  for (
    const selected of selectedCandidates
  ) {
    const candidate =
      selected.candidate;

    const anchors =
      selected.anchors;

    const deviation =
      parseDeviationMeasurement(
        await dependencies.measureDeviation({
          pickupAnchor:
            context.origin,
          pickup: candidate.pickup,
          dropoff: candidate.dropoff,
          dropoffAnchor:
            context.destination,
          pickupRouteIndex:
            anchors.pickupRouteIndex,
          dropoffRouteIndex:
            anchors.dropoffRouteIndex,
        }),
      );

    const measurement: RideMatchMeasurement = {
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

    if (
      !isRideMatchMeasurementEligible(
        measurement,
      )
    ) {
      continue;
    }

    evaluated.push({
      candidate,
      measurement,
      fairnessProtected:
        selected.fairnessProtected,
    });
  }

  if (evaluated.length === 0) {
    return {offers: []};
  }

  const rankedOfferCandidates =
    rankRideMatchEligibleOffers(
      evaluated,
    );

  return dependencies.firestore
    .runTransaction(
      async (transaction) => {
        const transactionNow =
          nowProvider();

        const lock =
          await revalidateContextInTransaction(
            dependencies.firestore,
            transaction,
            uid,
            context.driverId,
            context.returnRouteId,
            transactionNow,
          );

        const acceptedCandidates: EvaluatedCandidate[] =
          [];

        for (const item of rankedOfferCandidates) {
          const rideSnapshot =
            await transaction.get(
              dependencies.firestore
                .collection("rides")
                .doc(item.candidate.rideId),
            );

          if (!rideSnapshot.exists) {
            continue;
          }

          const currentCandidate =
            parseMatchingRideCandidate(
              rideSnapshot.id,
              rideSnapshot.data() ?? {},
            );

          if (
            currentCandidate === null ||
            currentCandidate.version !==
              item.candidate.version ||
            currentCandidate.passengerId !==
              item.candidate.passengerId ||
            currentCandidate.createdAt.toMillis() !==
              item.candidate.createdAt.toMillis() ||
            currentCandidate.passengerTripDistanceMeters !==
              item.candidate.passengerTripDistanceMeters ||
            currentCandidate.passengerTripDurationSeconds !==
              item.candidate.passengerTripDurationSeconds ||
            !locationsEqual(
              currentCandidate.pickup,
              item.candidate.pickup,
            ) ||
            !locationsEqual(
              currentCandidate.dropoff,
              item.candidate.dropoff,
            )
          ) {
            continue;
          }

          const passengerPointer =
            await transaction.get(
              dependencies.firestore
                .collection(
                  "passengerActiveRides",
                )
                .doc(
                  currentCandidate.passengerId,
                ),
            );

          if (
            !passengerPointer.exists ||
            passengerPointer.get("rideId") !==
              currentCandidate.rideId ||
            passengerPointer.get("status") !==
              "matching"
          ) {
            continue;
          }

          const existingOfferRef =
            dependencies.firestore
              .collection(
                "driverRideMatchOffers",
              )
              .doc(
                rideMatchOfferDocumentId(
                  context.driverId,
                  currentCandidate.rideId,
                  currentCandidate.version,
                ),
              );

          const existingOfferSnapshot =
            await transaction.get(
              existingOfferRef,
            );

          if (existingOfferSnapshot.exists) {
            const existingOffer =
              parseRideMatchOffer(
                existingOfferSnapshot.data() ?? {},
              );

            if (
              existingOffer.status === "consumed"
            ) {
              continue;
            }
          }

          acceptedCandidates.push(item);
        }

        const offers:
          PublicDiscoveredRideOffer[] = [];

        for (
          const item of acceptedCandidates
        ) {
          const offer =
            buildRideMatchOffer({
              driverId: context.driverId,
              rideId: item.candidate.rideId,
              rideVersion:
                item.candidate.version,
              returnRouteId:
                context.returnRouteId,
              routeExpiresAt:
                lock.expiresAt,
              now: transactionNow,
              measurement:
                item.measurement,
            });

          const offerRef =
            dependencies.firestore
              .collection(
                "driverRideMatchOffers",
              )
              .doc(
                rideMatchOfferDocumentId(
                  context.driverId,
                  item.candidate.rideId,
                  item.candidate.version,
                ),
              );

          transaction.set(
            offerRef,
            offer,
          );

          offers.push(
            toPublicDiscoveredRideOffer(
              item.candidate,
              offer,
            ),
          );
        }

        return {offers};
      },
    );
};
