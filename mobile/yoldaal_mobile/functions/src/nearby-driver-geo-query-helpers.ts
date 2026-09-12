export type NearbyDriverGeoHashPrefixRange = {
  startInclusive: string;
  endExclusive: string;
};

const GEOHASH_ALPHABET_PATTERN =
  /^[0123456789bcdefghjkmnpqrstuvwxyz]+$/u;

const MAX_GEOHASH_LENGTH = 12;

const requireCanonicalGeoHash = (
  value: unknown,
): string => {
  if (
    typeof value !== "string" ||
    value.length < 1 ||
    value.length > MAX_GEOHASH_LENGTH ||
    !GEOHASH_ALPHABET_PATTERN.test(value)
  ) {
    throw new TypeError(
      "Invalid canonical geohash.",
    );
  }

  return value;
};

const requirePrefixLength = (
  value: unknown,
  maximum: number,
): number => {
  if (
    typeof value !== "number" ||
    !Number.isInteger(value) ||
    value < 1 ||
    value > maximum
  ) {
    throw new TypeError(
      "Invalid geohash prefix length.",
    );
  }

  return value;
};

export const deriveNearbyDriverGeoHashPrefix = (
  geohashValue: string,
  prefixLengthValue: number,
): string => {
  const geohash =
    requireCanonicalGeoHash(geohashValue);

  const prefixLength =
    requirePrefixLength(
      prefixLengthValue,
      geohash.length,
    );

  return geohash.slice(
    0,
    prefixLength,
  );
};

export const buildNearbyDriverGeoHashPrefixRange = (
  prefixValue: string,
): NearbyDriverGeoHashPrefixRange => {
  const prefix =
    requireCanonicalGeoHash(prefixValue);

  const lastIndex =
    prefix.length - 1;

  const lastCharacterCode =
    prefix.charCodeAt(lastIndex);

  const endExclusive =
    prefix.slice(0, lastIndex) +
    String.fromCharCode(
      lastCharacterCode + 1,
    );

  return {
    startInclusive: prefix,
    endExclusive,
  };
};
