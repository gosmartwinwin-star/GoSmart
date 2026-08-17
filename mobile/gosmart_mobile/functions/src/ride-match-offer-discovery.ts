import {
  DocumentSnapshot,
  FieldPath,
  Firestore,
  QueryDocumentSnapshot,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {isActivePass} from "./driver-access-helpers.js";
import {
  loadApprovedDriverId,
  loadApprovedDriverIdInTransaction,
} from "./ride-driver-identity.js";
import {
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
  locateRouteAnchors,
  routeAnchorDirectionCompatible,
} from "./ride-route-geometry.js";
import type {
  RouteCoordinate,
} from "./ride-route-geometry.js";

export const RIDE_MATCH_DISCOVERY_CANDIDATE_LIMIT = 5;
export const RIDE_MATCH_DISCOVERY_OFFER_LIMIT = 3;

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
  pickup: DiscoveredRideLocation;
  dropoff: DiscoveredRideLocation;
};

export type PublicDiscoveredRideOffer = {
  rideId: string;
  rideVersion: number;
  pickup: DiscoveredRideLocation;
  dropoff: DiscoveredRideLocation;
  expiresAtMillis: number;
};

export type RideMatchOfferDiscoveryResult = {
  offers: PublicDiscoveredRideOffer[];
};

type ActiveReturnRouteContext = {
  driverId: string;
  returnRouteId: string;
  expiresAt: Timestamp;
  routePoints: RouteCoordinate[];
};

type ActiveReturnRouteLock = {
  routeId: string;
  activatedAt: Timestamp;
  expiresAt: Timestamp;
};

type EvaluatedCandidate = {
  candidate: MatchingRideCandidate;
  measurement: RideMatchMeasurement;
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
    !isPositiveInteger(data.version)
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

  return {
    rideId,
    passengerId: data.passengerId,
    version: data.version,
    pickup,
    dropoff,
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
): string => {
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
    encodedPolyline.length === 0
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

  return encodedPolyline;
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
  const passes = await firestore
    .collection("driverAccessPasses")
    .where("driverId", "==", driverId)
    .orderBy("purchasedAt", "desc")
    .limit(1)
    .get();

  if (
    passes.empty ||
    !isActivePass(
      passes.docs[0].data(),
      now,
    )
  ) {
    throw failure(
      "subscription_required",
    );
  }
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

  const encodedPolyline =
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
    routePoints:
      decodeReturnRoute(encodedPolyline),
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

  const passQuery = firestore
    .collection("driverAccessPasses")
    .where("driverId", "==", driverId)
    .orderBy("purchasedAt", "desc")
    .limit(1);

  const passes =
    await transaction.get(passQuery);

  if (
    passes.empty ||
    !isActivePass(
      passes.docs[0].data(),
      now,
    )
  ) {
    throw failure(
      "subscription_required",
    );
  }

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
      .orderBy(
        "updatedAt",
        "desc",
      )
      .orderBy(
        FieldPath.documentId(),
        "desc",
      )
      .limit(
        RIDE_MATCH_DISCOVERY_CANDIDATE_LIMIT,
      )
      .get();

  const evaluated: EvaluatedCandidate[] = [];

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

    const deviation =
      parseDeviationMeasurement(
        await dependencies.measureDeviation({
          pickupAnchor:
            anchors.pickupAnchor,
          pickup: candidate.pickup,
          dropoff: candidate.dropoff,
          dropoffAnchor:
            anchors.dropoffAnchor,
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
    });

    if (
      evaluated.length >=
      RIDE_MATCH_DISCOVERY_OFFER_LIMIT
    ) {
      break;
    }
  }

  if (evaluated.length === 0) {
    return {offers: []};
  }

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

        for (const item of evaluated) {
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
