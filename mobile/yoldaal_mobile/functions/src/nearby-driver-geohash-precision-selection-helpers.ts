export type NearbyDriverGeoPrecisionMeasurement = {
  precision: number;
  rangeCount: number;
  overfetchAreaRatio: number;
};

export type NearbyDriverGeoPrecisionSelectionCaps = {
  maxRangeCount: number;
  maxOverfetchAreaRatio: number;
};

const requirePrecision = (
  value: number,
): number => {
  if (
    !Number.isInteger(value) ||
    value < 1 ||
    value > 12
  ) {
    throw new TypeError(
      "precision must be an integer within [1, 12]",
    );
  }

  return value;
};

const requireRangeCount = (
  value: number,
): number => {
  if (
    !Number.isInteger(value) ||
    value < 1
  ) {
    throw new TypeError(
      "rangeCount must be a positive integer",
    );
  }

  return value;
};

const requireOverfetchAreaRatio = (
  value: number,
): number => {
  if (
    !Number.isFinite(value) ||
    value < 1
  ) {
    throw new TypeError(
      "overfetchAreaRatio must be finite and at least 1",
    );
  }

  return value;
};

const requireCaps = (
  value: NearbyDriverGeoPrecisionSelectionCaps,
): NearbyDriverGeoPrecisionSelectionCaps => ({
  maxRangeCount:
    requireRangeCount(
      value.maxRangeCount,
    ),
  maxOverfetchAreaRatio:
    requireOverfetchAreaRatio(
      value.maxOverfetchAreaRatio,
    ),
});

const requireMeasurement = (
  value: NearbyDriverGeoPrecisionMeasurement,
): NearbyDriverGeoPrecisionMeasurement => ({
  precision:
    requirePrecision(
      value.precision,
    ),
  rangeCount:
    requireRangeCount(
      value.rangeCount,
    ),
  overfetchAreaRatio:
    requireOverfetchAreaRatio(
      value.overfetchAreaRatio,
    ),
});

export const selectNearbyDriverGeoPrecision = (
  measurements:
    readonly NearbyDriverGeoPrecisionMeasurement[],
  caps: NearbyDriverGeoPrecisionSelectionCaps,
): NearbyDriverGeoPrecisionMeasurement | null => {
  const validatedCaps =
    requireCaps(caps);

  const seenPrecisions =
    new Set<number>();

  let selected:
    NearbyDriverGeoPrecisionMeasurement |
    null =
      null;

  for (const rawMeasurement of measurements) {
    const measurement =
      requireMeasurement(
        rawMeasurement,
      );

    if (
      seenPrecisions.has(
        measurement.precision,
      )
    ) {
      throw new TypeError(
        "Duplicate geohash precision measurement.",
      );
    }

    seenPrecisions.add(
      measurement.precision,
    );

    if (
      measurement.rangeCount >
        validatedCaps.maxRangeCount ||
      measurement.overfetchAreaRatio >
        validatedCaps.maxOverfetchAreaRatio
    ) {
      continue;
    }

    if (
      selected === null ||
      measurement.precision >
        selected.precision
    ) {
      selected =
        measurement;
    }
  }

  if (selected === null) {
    return null;
  }

  return {
    precision:
      selected.precision,
    rangeCount:
      selected.rangeCount,
    overfetchAreaRatio:
      selected.overfetchAreaRatio,
  };
};
