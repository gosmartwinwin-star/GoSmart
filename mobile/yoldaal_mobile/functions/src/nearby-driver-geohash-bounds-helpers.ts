export type NearbyDriverGeoHashCellBounds = {
  latitudeMinimum: number;
  latitudeMaximum: number;
  longitudeMinimum: number;
  longitudeMaximum: number;
};

const GEOHASH_BASE32 =
  "0123456789bcdefghjkmnpqrstuvwxyz";

const GEOHASH_BITS =
  [16, 8, 4, 2, 1] as const;

const MAX_GEOHASH_LENGTH = 12;

const requireCanonicalGeoHash = (
  value: unknown,
): string => {
  if (
    typeof value !== "string" ||
    value.length < 1 ||
    value.length > MAX_GEOHASH_LENGTH
  ) {
    throw new TypeError(
      "Invalid canonical geohash.",
    );
  }

  for (const character of value) {
    if (
      GEOHASH_BASE32.indexOf(
        character,
      ) < 0
    ) {
      throw new TypeError(
        "Invalid canonical geohash.",
      );
    }
  }

  return value;
};

export const decodeNearbyDriverGeoHashCellBounds = (
  geohashValue: string,
): NearbyDriverGeoHashCellBounds => {
  const geohash =
    requireCanonicalGeoHash(
      geohashValue,
    );

  let latitudeMinimum = -90;
  let latitudeMaximum = 90;
  let longitudeMinimum = -180;
  let longitudeMaximum = 180;
  let longitudeTurn = true;

  for (const character of geohash) {
    const characterValue =
      GEOHASH_BASE32.indexOf(
        character,
      );

    for (const bit of GEOHASH_BITS) {
      const bitIsSet =
        (characterValue & bit) !== 0;

      if (longitudeTurn) {
        const midpoint =
          (
            longitudeMinimum +
            longitudeMaximum
          ) / 2;

        if (bitIsSet) {
          longitudeMinimum =
            midpoint;
        } else {
          longitudeMaximum =
            midpoint;
        }
      } else {
        const midpoint =
          (
            latitudeMinimum +
            latitudeMaximum
          ) / 2;

        if (bitIsSet) {
          latitudeMinimum =
            midpoint;
        } else {
          latitudeMaximum =
            midpoint;
        }
      }

      longitudeTurn =
        !longitudeTurn;
    }
  }

  return {
    latitudeMinimum,
    latitudeMaximum,
    longitudeMinimum,
    longitudeMaximum,
  };
};
