import assert from "node:assert/strict";
import test from "node:test";

import {
  buildNearbyDriverGeoHashPrefixRange,
  deriveNearbyDriverGeoHashPrefix,
} from "./nearby-driver-geo-query-helpers.js";

test(
  "derives only a caller-selected geohash prefix length",
  () => {
    const geohash =
      "sxk973m6";

    assert.equal(
      deriveNearbyDriverGeoHashPrefix(
        geohash,
        5,
      ),
      "sxk97",
    );

    assert.equal(
      deriveNearbyDriverGeoHashPrefix(
        geohash,
        8,
      ),
      geohash,
    );
  },
);

test(
  "does not provide a default prefix length",
  () => {
    assert.throws(
      () =>
        deriveNearbyDriverGeoHashPrefix(
          "sxk973m6",
          0,
        ),
      TypeError,
    );

    assert.throws(
      () =>
        deriveNearbyDriverGeoHashPrefix(
          "sxk973m6",
          9,
        ),
      TypeError,
    );

    assert.throws(
      () =>
        deriveNearbyDriverGeoHashPrefix(
          "sxk973m6",
          1.5,
        ),
      TypeError,
    );
  },
);

test(
  "rejects non-canonical geohash text",
  () => {
    for (const geohash of [
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
          deriveNearbyDriverGeoHashPrefix(
            geohash,
            1,
          ),
        TypeError,
      );
    }
  },
);

test(
  "builds an exclusive lexical upper bound",
  () => {
    assert.deepEqual(
      buildNearbyDriverGeoHashPrefixRange(
        "sxk97",
      ),
      {
        startInclusive: "sxk97",
        endExclusive: "sxk98",
      },
    );

    assert.deepEqual(
      buildNearbyDriverGeoHashPrefixRange(
        "9",
      ),
      {
        startInclusive: "9",
        endExclusive: ":",
      },
    );

    assert.deepEqual(
      buildNearbyDriverGeoHashPrefixRange(
        "z",
      ),
      {
        startInclusive: "z",
        endExclusive: "{",
      },
    );
  },
);

test(
  "places canonical hashes with the prefix inside the range",
  () => {
    const range =
      buildNearbyDriverGeoHashPrefixRange(
        "sxk97",
      );

    for (const geohash of [
      "sxk97",
      "sxk970",
      "sxk973m6",
      "sxk97z",
    ]) {
      assert.equal(
        geohash >= range.startInclusive,
        true,
      );

      assert.equal(
        geohash < range.endExclusive,
        true,
      );
    }
  },
);

test(
  "keeps adjacent prefixes outside the range",
  () => {
    const range =
      buildNearbyDriverGeoHashPrefixRange(
        "sxk97",
      );

    assert.equal(
      "sxk96z" >= range.startInclusive,
      false,
    );

    assert.equal(
      "sxk98" < range.endExclusive,
      false,
    );
  },
);

test(
  "range output contains no radius limit or location data",
  () => {
    const range =
      buildNearbyDriverGeoHashPrefixRange(
        "sxk97",
      );

    assert.deepEqual(
      Object.keys(range).sort(),
      [
        "endExclusive",
        "startInclusive",
      ],
    );

    for (const forbidden of [
      "radiusMeters",
      "resultLimit",
      "latitude",
      "longitude",
      "driverId",
    ]) {
      assert.equal(
        forbidden in range,
        false,
      );
    }
  },
);
