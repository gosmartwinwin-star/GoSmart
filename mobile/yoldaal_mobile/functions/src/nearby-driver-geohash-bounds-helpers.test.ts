import assert from "node:assert/strict";
import test from "node:test";

import {
  decodeNearbyDriverGeoHashCellBounds,
} from "./nearby-driver-geohash-bounds-helpers.js";

test(
  "decodes first-character cells around longitude zero",
  () => {
    assert.deepEqual(
      decodeNearbyDriverGeoHashCellBounds(
        "e",
      ),
      {
        latitudeMinimum: 0,
        latitudeMaximum: 45,
        longitudeMinimum: -45,
        longitudeMaximum: 0,
      },
    );

    assert.deepEqual(
      decodeNearbyDriverGeoHashCellBounds(
        "s",
      ),
      {
        latitudeMinimum: 0,
        latitudeMaximum: 45,
        longitudeMinimum: 0,
        longitudeMaximum: 45,
      },
    );
  },
);

test(
  "boundary hashes from R57 touch at longitude zero",
  () => {
    const west =
      decodeNearbyDriverGeoHashCellBounds(
        "ebpbpbpb",
      );

    const east =
      decodeNearbyDriverGeoHashCellBounds(
        "s0000000",
      );

    assert.equal(
      west.longitudeMaximum,
      0,
    );

    assert.equal(
      east.longitudeMinimum,
      0,
    );

    assert.equal(
      west.longitudeMaximum,
      east.longitudeMinimum,
    );
  },
);

test(
  "known reference coordinate lies inside its decoded cell",
  () => {
    const bounds =
      decodeNearbyDriverGeoHashCellBounds(
        "ezs42",
      );

    assert.equal(
      bounds.latitudeMinimum <= 42.6,
      true,
    );

    assert.equal(
      42.6 < bounds.latitudeMaximum,
      true,
    );

    assert.equal(
      bounds.longitudeMinimum <= -5.6,
      true,
    );

    assert.equal(
      -5.6 < bounds.longitudeMaximum,
      true,
    );
  },
);

test(
  "a longer prefix remains inside its parent prefix cell",
  () => {
    const parent =
      decodeNearbyDriverGeoHashCellBounds(
        "sxk97",
      );

    const child =
      decodeNearbyDriverGeoHashCellBounds(
        "sxk973m6",
      );

    assert.equal(
      child.latitudeMinimum >=
        parent.latitudeMinimum,
      true,
    );

    assert.equal(
      child.latitudeMaximum <=
        parent.latitudeMaximum,
      true,
    );

    assert.equal(
      child.longitudeMinimum >=
        parent.longitudeMinimum,
      true,
    );

    assert.equal(
      child.longitudeMaximum <=
        parent.longitudeMaximum,
      true,
    );
  },
);

test(
  "decodes canonical world-edge cells",
  () => {
    assert.deepEqual(
      decodeNearbyDriverGeoHashCellBounds(
        "0",
      ),
      {
        latitudeMinimum: -90,
        latitudeMaximum: -45,
        longitudeMinimum: -180,
        longitudeMaximum: -135,
      },
    );

    assert.deepEqual(
      decodeNearbyDriverGeoHashCellBounds(
        "z",
      ),
      {
        latitudeMinimum: 45,
        latitudeMaximum: 90,
        longitudeMinimum: 135,
        longitudeMaximum: 180,
      },
    );
  },
);

test(
  "rejects non-canonical geohash values",
  () => {
    for (const value of [
      "",
      "SXK97",
      "sxka7",
      "sxki7",
      "sxkl7",
      "sxko7",
      "sxk97!",
      "0123456789012",
    ]) {
      assert.throws(
        () =>
          decodeNearbyDriverGeoHashCellBounds(
            value,
          ),
        TypeError,
      );
    }
  },
);

test(
  "bounds output contains geometry only",
  () => {
    const bounds =
      decodeNearbyDriverGeoHashCellBounds(
        "sxk97",
      );

    assert.deepEqual(
      Object.keys(bounds).sort(),
      [
        "latitudeMaximum",
        "latitudeMinimum",
        "longitudeMaximum",
        "longitudeMinimum",
      ],
    );

    for (const forbidden of [
      "driverId",
      "geohash",
      "radiusMeters",
      "resultLimit",
      "prefixLength",
    ]) {
      assert.equal(
        forbidden in bounds,
        false,
      );
    }
  },
);
