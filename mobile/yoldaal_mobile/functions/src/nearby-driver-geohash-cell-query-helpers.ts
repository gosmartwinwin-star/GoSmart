import {
  type NearbyDriverGeoHashCellDelta,
  deriveNearbyDriverAdjacentGeoHash,
} from "./nearby-driver-geohash-adjacency-helpers.js";

import {
  type NearbyDriverGeoHashPrefixRange,
  buildNearbyDriverGeoHashPrefixRange,
} from "./nearby-driver-geo-query-helpers.js";

export type NearbyDriverAdjacentCellQuery = {
  geohash: string;
  range: NearbyDriverGeoHashPrefixRange;
};

export const buildNearbyDriverAdjacentCellQuery = (
  sourceGeoHash: string,
  latitudeCellDelta: NearbyDriverGeoHashCellDelta,
  longitudeCellDelta: NearbyDriverGeoHashCellDelta,
): NearbyDriverAdjacentCellQuery | null => {
  const adjacentGeoHash =
    deriveNearbyDriverAdjacentGeoHash(
      sourceGeoHash,
      latitudeCellDelta,
      longitudeCellDelta,
    );

  if (adjacentGeoHash === null) {
    return null;
  }

  return {
    geohash: adjacentGeoHash,
    range:
      buildNearbyDriverGeoHashPrefixRange(
        adjacentGeoHash,
      ),
  };
};
