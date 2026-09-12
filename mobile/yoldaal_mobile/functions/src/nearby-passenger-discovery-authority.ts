import {
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import {
  HttpsError,
} from "firebase-functions/v2/https";

import {
  type NearbyDriverGeoCoordinate,
} from "./nearby-driver-geo-index-helpers.js";
import {
  measureNearbyDriverGeoHashCoverage,
} from "./nearby-driver-geohash-coverage-measurement-helpers.js";
import {
  buildNearbyDriverGeoHashCoveragePlan,
} from "./nearby-driver-geohash-coverage-plan-helpers.js";
import {
  selectNearbyDriverGeoPrecision,
} from "./nearby-driver-geohash-precision-selection-helpers.js";
import {
  type NearbyDriverCandidateProjection,
  projectNearbyDriverCandidate,
} from "./nearby-driver-discovery-helpers.js";
import {
  composeNearbyPassengerDiscovery,
  PASSENGER_DISCOVERY_RADIUS_METERS,
} from "./nearby-passenger-discovery-composition-helpers.js";
import {
  type RideMatchMeasurement,
} from "./ride-match-offer-helpers.js";

const PASSENGER_DISCOVERY_PRECISIONS =
  [4, 5, 6] as const;

const PASSENGER_DISCOVERY_MAX_RANGE_COUNT =
  3864;

const PASSENGER_DISCOVERY_MAX_OVERFETCH_AREA_RATIO =
  7.23187526334938;

type PlainRecord =
  Record<string, unknown>;

export type NearbyPassengerDiscoveryMeasurementInput = {
  passengerRideId: string;
  passengerPickup: NearbyDriverGeoCoordinate;
  passengerDropoff: NearbyDriverGeoCoordinate;
  driverId: string;
  returnRouteId: string;
  projection: NearbyDriverCandidateProjection;
  returnRouteData: unknown;
};

export type NearbyPassengerDiscoveryDependencies = {
  firestore: Firestore;
  now?: () => Timestamp;
  measureCompatibility: (
    input: NearbyPassengerDiscoveryMeasurementInput,
  ) => Promise<RideMatchMeasurement | null>;
};

const failure = (
  code:
    | "invalid-argument"
    | "failed-precondition"
    | "internal"
    | "unavailable",
  reason: string,
): HttpsError =>
  new HttpsError(
    code,
    "Yakındaki sürücüler şu anda yüklenemedi.",
    {reason},
  );

const plainRecord = (
  value: unknown,
): PlainRecord | null =>
  typeof value === "object" &&
  value !== null &&
  !Array.isArray(value) ?
    value as PlainRecord :
    null;

const nonEmptyString = (
  value: unknown,
): value is string =>
  typeof value === "string" &&
  value.length > 0;

const validCoordinate = (
  value: unknown,
): value is NearbyDriverGeoCoordinate => {
  const record =
    plainRecord(value);

  if (record === null) {
    return false;
  }

  const latitude =
    record.latitude;

  const longitude =
    record.longitude;

  return (
    typeof latitude === "number" &&
    Number.isFinite(latitude) &&
    latitude >= -90 &&
    latitude <= 90 &&
    typeof longitude === "number" &&
    Number.isFinite(longitude) &&
    longitude >= -180 &&
    longitude <= 180
  );
};

const validateEmptyPayload = (
  rawInput: unknown,
): void => {
  if (
    plainRecord(rawInput) === null ||
    Object.keys(rawInput as PlainRecord).length !== 0
  ) {
    throw failure(
      "invalid-argument",
      "invalid_nearby_passenger_discovery_payload",
    );
  }
};

const loadPassengerDiscoveryContext = async (
  firestore: Firestore,
  passengerId: string,
): Promise<{
  rideId: string;
  pickup: NearbyDriverGeoCoordinate;
  dropoff: NearbyDriverGeoCoordinate;
}> => {
  const pointer = await firestore
    .collection("passengerActiveRides")
    .doc(passengerId)
    .get();

  if (!pointer.exists) {
    throw failure(
      "failed-precondition",
      "passenger_active_ride_required",
    );
  }

  const rideId =
    pointer.get("rideId");

  const pointerStatus =
    pointer.get("status");

  if (
    !nonEmptyString(rideId) ||
    !nonEmptyString(pointerStatus)
  ) {
    throw failure(
      "internal",
      "active_ride_pointer_inconsistent",
    );
  }

  if (pointerStatus !== "matching") {
    throw failure(
      "failed-precondition",
      "passenger_ride_not_matching",
    );
  }

  const ride = await firestore
    .collection("rides")
    .doc(rideId)
    .get();

  if (!ride.exists) {
    throw failure(
      "internal",
      "active_ride_pointer_inconsistent",
    );
  }

  const data =
    plainRecord(ride.data());

  if (
    data === null ||
    data.passengerId !== passengerId ||
    data.status !== pointerStatus ||
    data.status !== "matching" ||
    !(
      data.driverId === null ||
      data.driverId === undefined
    ) ||
    !validCoordinate(data.pickup) ||
    !validCoordinate(data.dropoff)
  ) {
    throw failure(
      "internal",
      "passenger_ride_invalid",
    );
  }

  return {
    rideId,
    pickup: data.pickup,
    dropoff: data.dropoff,
  };
};

const requireCoveragePlan = (
  pickup: NearbyDriverGeoCoordinate,
) => {
  const measurements = [];

  for (
    const precision of
    PASSENGER_DISCOVERY_PRECISIONS
  ) {
    const measurement =
      measureNearbyDriverGeoHashCoverage(
        pickup,
        PASSENGER_DISCOVERY_RADIUS_METERS,
        precision,
      );

    if (measurement !== null) {
      measurements.push(measurement);
    }
  }

  const selected =
    selectNearbyDriverGeoPrecision(
      measurements,
      {
        maxRangeCount:
          PASSENGER_DISCOVERY_MAX_RANGE_COUNT,
        maxOverfetchAreaRatio:
          PASSENGER_DISCOVERY_MAX_OVERFETCH_AREA_RATIO,
      },
    );

  if (selected === null) {
    throw failure(
      "failed-precondition",
      "nearby_passenger_discovery_geography_unsupported",
    );
  }

  const plan =
    buildNearbyDriverGeoHashCoveragePlan(
      pickup,
      PASSENGER_DISCOVERY_RADIUS_METERS,
      selected.precision,
    );

  if (plan === null) {
    throw failure(
      "failed-precondition",
      "nearby_passenger_discovery_geography_unsupported",
    );
  }

  return plan;
};

const loadCompleteGeoIndexDriverIds = async (
  firestore: Firestore,
  pickup: NearbyDriverGeoCoordinate,
): Promise<string[]> => {
  const plan =
    requireCoveragePlan(pickup);

  const driverIds =
    new Set<string>();

  try {
    for (const cell of plan.cells) {
      const snapshot = await firestore
        .collection("nearbyDriverGeoIndexes")
        .orderBy("geohash", "asc")
        .orderBy("updatedAt", "asc")
        .startAt(cell.range.startInclusive)
        .endBefore(cell.range.endExclusive)
        .get();

      for (const document of snapshot.docs) {
        const data =
          plainRecord(document.data());

        if (data === null) {
          throw failure(
            "internal",
            "nearby_driver_geo_index_invalid",
          );
        }

        const keys =
          Object.keys(data)
            .sort()
            .join(",");

        const driverId =
          data.driverId;

        const geohash =
          data.geohash;

        const updatedAt =
          data.updatedAt;

        if (
          keys !== "driverId,geohash,updatedAt" ||
          !nonEmptyString(driverId) ||
          document.id !== driverId ||
          !nonEmptyString(geohash) ||
          !(
            geohash >=
              cell.range.startInclusive &&
            geohash <
              cell.range.endExclusive
          ) ||
          !(updatedAt instanceof Timestamp)
        ) {
          throw failure(
            "internal",
            "nearby_driver_geo_index_invalid",
          );
        }

        driverIds.add(driverId);
      }
    }
  } catch (error: unknown) {
    if (error instanceof HttpsError) {
      throw error;
    }

    throw failure(
      "unavailable",
      "nearby_driver_geo_query_failed",
    );
  }

  return Array.from(driverIds);
};

const loadProjectedCandidate = async (
  firestore: Firestore,
  driverId: string,
  now: Timestamp,
): Promise<{
  projection: NearbyDriverCandidateProjection;
  returnRouteId: string;
  returnRouteData: unknown;
} | null> => {
  try {
    const presence = await firestore
      .collection("driverLivePresences")
      .doc(driverId)
      .get();

    const activeReturnRoute = await firestore
      .collection("driverActiveReturnRoutes")
      .doc(driverId)
      .get();

    if (
      !presence.exists ||
      !activeReturnRoute.exists
    ) {
      return null;
    }

    const activeReturnRouteData =
      activeReturnRoute.data();

    const activeRecord =
      plainRecord(activeReturnRouteData);

    if (activeRecord === null) {
      return null;
    }

    const returnRouteId =
      activeRecord.routeId;

    if (!nonEmptyString(returnRouteId)) {
      return null;
    }

    const returnRoute = await firestore
      .collection("driverReturnRoutes")
      .doc(returnRouteId)
      .get();

    if (!returnRoute.exists) {
      return null;
    }

    const returnRouteData =
      returnRoute.data();

    const projection =
      projectNearbyDriverCandidate({
        driverId,
        returnRouteId,
        presenceData: presence.data(),
        activeReturnRouteData,
        returnRouteData,
        now,
      });

    if (projection === null) {
      return null;
    }

    return {
      projection,
      returnRouteId,
      returnRouteData,
    };
  } catch (error: unknown) {
    if (error instanceof HttpsError) {
      throw error;
    }

    throw failure(
      "unavailable",
      "nearby_driver_candidate_read_failed",
    );
  }
};

export const discoverNearbyPassengerDriversForPassenger =
  async (
    dependencies:
      NearbyPassengerDiscoveryDependencies,
    passengerId: string,
    rawInput: unknown,
  ): Promise<NearbyDriverCandidateProjection[]> => {
    if (!nonEmptyString(passengerId)) {
      throw new HttpsError(
        "unauthenticated",
        "Yakındaki sürücüler için giriş yapmalısınız.",
      );
    }

    validateEmptyPayload(rawInput);

    const now =
      dependencies.now?.() ??
      Timestamp.now();

    const context =
      await loadPassengerDiscoveryContext(
        dependencies.firestore,
        passengerId,
      );

    const driverIds =
      await loadCompleteGeoIndexDriverIds(
        dependencies.firestore,
        context.pickup,
      );

    const candidates = [];

    for (const driverId of driverIds) {
      const candidate =
        await loadProjectedCandidate(
          dependencies.firestore,
          driverId,
          now,
        );

      if (candidate === null) {
        continue;
      }

      let measurement:
        RideMatchMeasurement | null;

      try {
        measurement =
          await dependencies.measureCompatibility({
            passengerRideId:
              context.rideId,
            passengerPickup:
              context.pickup,
            passengerDropoff:
              context.dropoff,
            driverId,
            returnRouteId:
              candidate.returnRouteId,
            projection:
              candidate.projection,
            returnRouteData:
              candidate.returnRouteData,
          });
      } catch (error: unknown) {
        if (error instanceof HttpsError) {
          throw error;
        }

        throw failure(
          "unavailable",
          "nearby_driver_match_measurement_failed",
        );
      }

      if (measurement === null) {
        continue;
      }

      candidates.push({
        internalDriverId:
          driverId,
        projection:
          candidate.projection,
        measurement,
      });
    }

    return composeNearbyPassengerDiscovery(
      context.pickup,
      candidates,
    );
  };
