import assert from "node:assert/strict";
import test from "node:test";

import {
  deriveNearbyDriverAdjacentGeoHash,
} from "./nearby-driver-geohash-adjacency-helpers.js";

test(
  "crosses the zero meridian reciprocally",
  () => {
    assert.equal(
      deriveNearbyDriverAdjacentGeoHash(
        "e",
        0,
        1,
      ),
      "s",
    );

    assert.equal(
      deriveNearbyDriverAdjacentGeoHash(
        "s",
        0,
        -1,
      ),
      "e",
    );
  },
);

test(
  "wraps east across the dateline",
  () => {
    assert.equal(
      deriveNearbyDriverAdjacentGeoHash(
        "z",
        0,
        1,
      ),
      "b",
    );
  },
);

test(
  "wraps west across the dateline",
  () => {
    assert.equal(
      deriveNearbyDriverAdjacentGeoHash(
        "0",
        0,
        -1,
      ),
      "p",
    );
  },
);

test(
  "fails closed beyond either pole",
  () => {
    assert.equal(
      deriveNearbyDriverAdjacentGeoHash(
        "z",
        1,
        0,
      ),
      null,
    );

    assert.equal(
      deriveNearbyDriverAdjacentGeoHash(
        "0",
        -1,
        0,
      ),
      null,
    );
  },
);

test(
  "preserves the caller geohash precision",
  () => {
    const source =
      "sxk973m6";

    const east =
      deriveNearbyDriverAdjacentGeoHash(
        source,
        0,
        1,
      );

    assert.equal(
      typeof east,
      "string",
    );

    assert.equal(
      east?.length,
      source.length,
    );
  },
);

test(
  "supports an explicit diagonal cell step without selecting a set",
  () => {
    const source =
      "sxk97";

    const northeast =
      deriveNearbyDriverAdjacentGeoHash(
        source,
        1,
        1,
      );

    assert.equal(
      typeof northeast,
      "string",
    );

    assert.equal(
      northeast?.length,
      source.length,
    );

    assert.notEqual(
      northeast,
      source,
    );
  },
);

test(
  "rejects the zero-zero non-adjacent step",
  () => {
    assert.throws(
      () =>
        deriveNearbyDriverAdjacentGeoHash(
          "sxk97",
          0,
          0,
        ),
      TypeError,
    );
  },
);

test(
  "rejects invalid cell deltas",
  () => {
    assert.throws(
      () =>
        deriveNearbyDriverAdjacentGeoHash(
          "sxk97",
          2 as 1,
          0,
        ),
      TypeError,
    );

    assert.throws(
      () =>
        deriveNearbyDriverAdjacentGeoHash(
          "sxk97",
          0,
          -2 as -1,
        ),
      TypeError,
    );
  },
);

test(
  "inherits canonical geohash validation from the bounds decoder",
  () => {
    assert.throws(
      () =>
        deriveNearbyDriverAdjacentGeoHash(
          "SXK97",
          0,
          1,
        ),
      TypeError,
    );

    assert.throws(
      () =>
        deriveNearbyDriverAdjacentGeoHash(
          "",
          0,
          1,
        ),
      TypeError,
    );
  },
);
