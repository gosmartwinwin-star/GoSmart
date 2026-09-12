import type {
  NearbyDriverCandidateProjection,
} from "./nearby-driver-discovery-helpers.js";

import {
  quantizeNearbyDriverLocation,
} from "./nearby-driver-location-privacy-helpers.js";

import {
  isRideMatchMeasurementEligible,
} from "./ride-match-offer-helpers.js";

import type {
  RideMatchMeasurement,
} from "./ride-match-offer-helpers.js";

import {
  geoDistanceMeters,
} from "./ride-route-geometry.js";

import type {
  RouteCoordinate,
} from "./ride-route-geometry.js";

export const PASSENGER_DISCOVERY_RADIUS_METERS =
  3000;

export const PASSENGER_DISCOVERY_MAX_RESULTS =
  8;

export type NearbyPassengerDiscoveryCandidate = {
  internalDriverId: string;
  projection: NearbyDriverCandidateProjection;
  measurement: RideMatchMeasurement;
};

type EvaluatedNearbyPassengerDiscoveryCandidate = {
  internalDriverId: string;
  projection: NearbyDriverCandidateProjection;
  distanceMeters: number;
};

const validInternalDriverId = (
  value: string,
): boolean =>
  value.trim().length > 0;

const validProjectedFreshness = (
  value: number,
): boolean =>
  Number.isFinite(value);

export const composeNearbyPassengerDiscovery = (
  pickup: RouteCoordinate,
  candidates: readonly NearbyPassengerDiscoveryCandidate[],
): NearbyDriverCandidateProjection[] => {
  const evaluated:
    EvaluatedNearbyPassengerDiscoveryCandidate[] =
      [];

  for (const candidate of candidates) {
    if (
      !validInternalDriverId(
        candidate.internalDriverId,
      ) ||
      !validProjectedFreshness(
        candidate.projection.updatedAtMillis,
      ) ||
      !isRideMatchMeasurementEligible(
        candidate.measurement,
      )
    ) {
      continue;
    }

    const distanceMeters =
      geoDistanceMeters(
        pickup,
        {
          latitude:
            candidate.projection.latitude,
          longitude:
            candidate.projection.longitude,
        },
      );

    if (
      distanceMeters >
      PASSENGER_DISCOVERY_RADIUS_METERS
    ) {
      continue;
    }

    evaluated.push({
      internalDriverId:
        candidate.internalDriverId,
      projection:
        candidate.projection,
      distanceMeters,
    });
  }

  evaluated.sort(
    (
      first,
      second,
    ) => {
      if (
        first.distanceMeters !==
        second.distanceMeters
      ) {
        return (
          first.distanceMeters -
          second.distanceMeters
        );
      }

      if (
        first.projection.updatedAtMillis !==
        second.projection.updatedAtMillis
      ) {
        return (
          second.projection.updatedAtMillis -
          first.projection.updatedAtMillis
        );
      }

      if (
        first.internalDriverId <
        second.internalDriverId
      ) {
        return -1;
      }

      if (
        first.internalDriverId >
        second.internalDriverId
      ) {
        return 1;
      }

      return 0;
    },
  );

  return evaluated
    .slice(
      0,
      PASSENGER_DISCOVERY_MAX_RESULTS,
    )
    .map(
      (candidate) => {
        const approximate =
          quantizeNearbyDriverLocation(
            candidate.projection.latitude,
            candidate.projection.longitude,
          );

        return {
          latitude:
            approximate.latitude,
          longitude:
            approximate.longitude,
          updatedAtMillis:
            candidate.projection.updatedAtMillis,
        };
      },
    );
};
