import {
  encodeNearbyDriverGeoHash,
} from "./nearby-driver-geo-index-helpers.js";

import type {
  NearbyDriverGeoCoordinate,
} from "./nearby-driver-geo-index-helpers.js";

import {
  deriveNearbyDriverGeoHashPrefix,
} from "./nearby-driver-geo-query-helpers.js";

import {
  buildNearbyDriverGeoHashCoveragePlan,
} from "./nearby-driver-geohash-coverage-plan-helpers.js";

export const RETURN_ROUTE_CORRIDOR_ROOT_PREFIX =
  "*";

export const RETURN_ROUTE_CORRIDOR_MAX_GEOHASH_DEPTH =
  12;

const GEOHASH_ALPHABET_PATTERN =
  /^[0123456789bcdefghjkmnpqrstuvwxyz]+$/u;

const requirePositiveInteger = (
  value: number,
  field: string,
): number => {
  if (
    !Number.isInteger(value) ||
    value < 1
  ) {
    throw new TypeError(
      `${field} must be a positive integer.`,
    );
  }

  return value;
};

const requirePrecision = (
  value: number,
): number => {
  const precision =
    requirePositiveInteger(
      value,
      "initialPrecision",
    );

  if (
    precision >
    RETURN_ROUTE_CORRIDOR_MAX_GEOHASH_DEPTH
  ) {
    throw new TypeError(
      "initialPrecision must be within [1, 12].",
    );
  }

  return precision;
};

const requireRadiusMeters = (
  value: number,
): number => {
  if (
    !Number.isFinite(value) ||
    value <= 0
  ) {
    throw new TypeError(
      "radiusMeters must be finite and positive.",
    );
  }

  return value;
};

const requirePrefix = (
  value: unknown,
): string => {
  if (
    value ===
    RETURN_ROUTE_CORRIDOR_ROOT_PREFIX
  ) {
    return value;
  }

  if (
    typeof value !== "string" ||
    value.length < 1 ||
    value.length >
      RETURN_ROUTE_CORRIDOR_MAX_GEOHASH_DEPTH ||
    !GEOHASH_ALPHABET_PATTERN.test(value)
  ) {
    throw new TypeError(
      "Invalid return-route corridor prefix.",
    );
  }

  return value;
};

const parentPrefix = (
  prefix: string,
): string => {
  if (
    prefix ===
    RETURN_ROUTE_CORRIDOR_ROOT_PREFIX ||
    prefix.length === 1
  ) {
    return RETURN_ROUTE_CORRIDOR_ROOT_PREFIX;
  }

  return prefix.slice(
    0,
    prefix.length - 1,
  );
};

const normalizePrefixes = (
  values: readonly string[],
): string[] => {
  const validated =
    values.map(requirePrefix);

  if (
    validated.includes(
      RETURN_ROUTE_CORRIDOR_ROOT_PREFIX,
    )
  ) {
    return [
      RETURN_ROUTE_CORRIDOR_ROOT_PREFIX,
    ];
  }

  const ordered =
    Array.from(
      new Set(validated),
    ).sort(
      (left, right) =>
        left.length - right.length ||
        left.localeCompare(right),
    );

  const selected: string[] = [];

  for (const candidate of ordered) {
    if (
      selected.some(
        (prefix) =>
          candidate.startsWith(prefix),
      )
    ) {
      continue;
    }

    selected.push(candidate);
  }

  return selected.sort();
};

const promotionDescendantCount = (
  prefixes: readonly string[],
  parent: string,
): number => {
  if (
    parent ===
    RETURN_ROUTE_CORRIDOR_ROOT_PREFIX
  ) {
    return prefixes.length;
  }

  return prefixes.filter(
    (prefix) =>
      prefix.startsWith(parent),
  ).length;
};

export const coarsenReturnRouteCorridorPrefixes = (
  values: readonly string[],
  maxPrefixCountValue: number,
): string[] => {
  const maxPrefixCount =
    requirePositiveInteger(
      maxPrefixCountValue,
      "maxPrefixCount",
    );

  let selected =
    normalizePrefixes(values);

  if (selected.length === 0) {
    return [];
  }

  while (
    selected.length >
    maxPrefixCount
  ) {
    let bestParent: string | null = null;
    let bestDescendantCount = -1;
    let bestDepth = -1;

    for (const prefix of selected) {
      const candidateParent =
        parentPrefix(prefix);

      const descendantCount =
        promotionDescendantCount(
          selected,
          candidateParent,
        );

      const depth =
        candidateParent ===
          RETURN_ROUTE_CORRIDOR_ROOT_PREFIX ?
          0 :
          candidateParent.length;

      const better =
        descendantCount >
          bestDescendantCount ||
        (
          descendantCount ===
            bestDescendantCount &&
          depth > bestDepth
        ) ||
        (
          descendantCount ===
            bestDescendantCount &&
          depth === bestDepth &&
          (
            bestParent === null ||
            candidateParent < bestParent
          )
        );

      if (!better) {
        continue;
      }

      bestParent = candidateParent;
      bestDescendantCount =
        descendantCount;
      bestDepth = depth;
    }

    if (bestParent === null) {
      throw new Error(
        "Unable to coarsen corridor prefixes.",
      );
    }

    if (
      bestParent ===
      RETURN_ROUTE_CORRIDOR_ROOT_PREFIX
    ) {
      return [
        RETURN_ROUTE_CORRIDOR_ROOT_PREFIX,
      ];
    }

    selected =
      normalizePrefixes([
        ...selected.filter(
          (prefix) =>
            !prefix.startsWith(bestParent),
        ),
        bestParent,
      ]);
  }

  return selected;
};

export const buildReturnRoutePickupQueryTerms = (
  pickup: NearbyDriverGeoCoordinate,
): string[] => {
  const geohash =
    encodeNearbyDriverGeoHash(
      pickup,
      RETURN_ROUTE_CORRIDOR_MAX_GEOHASH_DEPTH,
    );

  const terms = [
    RETURN_ROUTE_CORRIDOR_ROOT_PREFIX,
  ];

  for (
    let length = 1;
    length <= geohash.length;
    length += 1
  ) {
    terms.push(
      deriveNearbyDriverGeoHashPrefix(
        geohash,
        length,
      ),
    );
  }

  return terms;
};

export type ReturnRouteCorridorPrefixBuildInput = {
  routePoints:
    readonly NearbyDriverGeoCoordinate[];
  radiusMeters: number;
  initialPrecision: number;
  maxPrefixCount: number;
};

export const buildReturnRouteCorridorPrefixes = (
  input: ReturnRouteCorridorPrefixBuildInput,
): string[] => {
  if (
    !Array.isArray(input.routePoints) ||
    input.routePoints.length < 2
  ) {
    throw new TypeError(
      "Calculated route requires at least two points.",
    );
  }

  const radiusMeters =
    requireRadiusMeters(
      input.radiusMeters,
    );

  const initialPrecision =
    requirePrecision(
      input.initialPrecision,
    );

  const maxPrefixCount =
    requirePositiveInteger(
      input.maxPrefixCount,
      "maxPrefixCount",
    );

  const initialPrefixes: string[] = [];

  for (const routePoint of input.routePoints) {
    const plan =
      buildNearbyDriverGeoHashCoveragePlan(
        routePoint,
        radiusMeters,
        initialPrecision,
      );

    if (
      plan === null ||
      plan.cells.length === 0
    ) {
      return [
        RETURN_ROUTE_CORRIDOR_ROOT_PREFIX,
      ];
    }

    for (const cell of plan.cells) {
      initialPrefixes.push(
        cell.geohash,
      );
    }
  }

  return coarsenReturnRouteCorridorPrefixes(
    initialPrefixes,
    maxPrefixCount,
  );
};
