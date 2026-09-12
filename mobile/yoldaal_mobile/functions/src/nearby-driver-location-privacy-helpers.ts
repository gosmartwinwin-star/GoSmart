const earthRadiusMeters = 6_371_000;
const targetCellMeters = 100;
const twoPi = 2 * Math.PI;

const latitudeBandCount = Math.ceil(
  (Math.PI * earthRadiusMeters) /
    targetCellMeters,
);

const latitudeBandStepRadians =
  Math.PI / latitudeBandCount;

type NearbyDriverLatitudeBand = {
  centerRadians: number;
  longitudeCellCount: number;
  longitudeStepRadians: number;
};

export type NearbyDriverApproximateLocation = {
  latitude: number;
  longitude: number;
};

const degreesToRadians = (
  degrees: number,
): number =>
  (degrees * Math.PI) / 180;

const radiansToDegrees = (
  radians: number,
): number =>
  (radians * 180) / Math.PI;

const normalizeLongitudeRadians = (
  longitudeRadians: number,
): number => {
  let normalized =
    ((((longitudeRadians + Math.PI) % twoPi) +
      twoPi) %
      twoPi) -
    Math.PI;

  if (Object.is(normalized, -0)) {
    normalized = 0;
  }

  return normalized;
};

const buildLatitudeBand = (
  latitudeRadians: number,
): NearbyDriverLatitudeBand => {
  let latitudeBandIndex = Math.floor(
    (latitudeRadians + Math.PI / 2) /
      latitudeBandStepRadians,
  );

  latitudeBandIndex = Math.max(
    0,
    Math.min(
      latitudeBandCount - 1,
      latitudeBandIndex,
    ),
  );

  const minimumLatitudeRadians =
    -Math.PI / 2 +
    latitudeBandIndex *
      latitudeBandStepRadians;

  const maximumLatitudeRadians =
    minimumLatitudeRadians +
    latitudeBandStepRadians;

  const centerRadians =
    (minimumLatitudeRadians +
      maximumLatitudeRadians) /
    2;

  let minimumAbsoluteLatitudeRadians: number;

  if (
    minimumLatitudeRadians <= 0 &&
    maximumLatitudeRadians >= 0
  ) {
    minimumAbsoluteLatitudeRadians = 0;
  } else {
    minimumAbsoluteLatitudeRadians = Math.min(
      Math.abs(minimumLatitudeRadians),
      Math.abs(maximumLatitudeRadians),
    );
  }

  const maximumCircumferenceMeters =
    twoPi *
    earthRadiusMeters *
    Math.cos(
      minimumAbsoluteLatitudeRadians,
    );

  const longitudeCellCount = Math.max(
    1,
    Math.ceil(
      maximumCircumferenceMeters /
        targetCellMeters,
    ),
  );

  return {
    centerRadians,
    longitudeCellCount,
    longitudeStepRadians:
      twoPi / longitudeCellCount,
  };
};

const validateCoordinate = (
  latitude: number,
  longitude: number,
): void => {
  if (
    !Number.isFinite(latitude) ||
    latitude < -90 ||
    latitude > 90
  ) {
    throw new TypeError(
      "latitude must be finite and within [-90, 90]",
    );
  }

  if (
    !Number.isFinite(longitude) ||
    longitude < -180 ||
    longitude > 180
  ) {
    throw new TypeError(
      "longitude must be finite and within [-180, 180]",
    );
  }
};

export const quantizeNearbyDriverLocation = (
  latitude: number,
  longitude: number,
): NearbyDriverApproximateLocation => {
  validateCoordinate(
    latitude,
    longitude,
  );

  const latitudeRadians =
    degreesToRadians(latitude);

  const band =
    buildLatitudeBand(
      latitudeRadians,
    );

  const longitudeRadians =
    normalizeLongitudeRadians(
      degreesToRadians(longitude),
    );

  let longitudeCellIndex = Math.floor(
    (longitudeRadians + Math.PI) /
      band.longitudeStepRadians,
  );

  longitudeCellIndex = Math.max(
    0,
    Math.min(
      band.longitudeCellCount - 1,
      longitudeCellIndex,
    ),
  );

  const quantizedLongitudeRadians =
    -Math.PI +
    (longitudeCellIndex + 0.5) *
      band.longitudeStepRadians;

  return {
    latitude:
      radiansToDegrees(
        band.centerRadians,
      ),
    longitude:
      radiansToDegrees(
        normalizeLongitudeRadians(
          quantizedLongitudeRadians,
        ),
      ),
  };
};
