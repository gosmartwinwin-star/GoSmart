import assert from "node:assert/strict";
import test from "node:test";

import {
  buildNearbyDriverAdjacentCellQuery,
} from "./nearby-driver-geohash-cell-query-helpers.js";

test(
  "composes east of e into the s lexical range",
  () => {
    assert.deepEqual(
      buildNearbyDriverAdjacentCellQuery(
        "e",
        0,
        1,
      ),
      {
        geohash: "s",
        range: {
          startInclusive: "s",
          endExclusive: "t",
        },
      },
    );
  },
);

test(
  "composes a dateline-wrapped adjacent cell into its range",
  () => {
    assert.deepEqual(
      buildNearbyDriverAdjacentCellQuery(
        "z",
        0,
        1,
      ),
      {
        geohash: "b",
        range: {
          startInclusive: "b",
          endExclusive: "c",
        },
      },
    );
  },
);

test(
  "fails closed when the adjacent cell would cross a pole",
  () => {
    assert.equal(
      buildNearbyDriverAdjacentCellQuery(
        "z",
        1,
        0,
      ),
      null,
    );

    assert.equal(
      buildNearbyDriverAdjacentCellQuery(
        "0",
        -1,
        0,
      ),
      null,
    );
  },
);

test(
  "preserves source precision for an ordinary adjacent cell",
  () => {
    const source =
      "sxk97";

    const result =
      buildNearbyDriverAdjacentCellQuery(
        source,
        0,
        1,
      );

    assert.notEqual(
      result,
      null,
    );

    assert.equal(
      result?.geohash.length,
      source.length,
    );

    assert.equal(
      result?.range.startInclusive,
      result?.geohash,
    );

    assert.equal(
      typeof result?.range.endExclusive,
      "string",
    );
  },
);

test(
  "supports exactly one explicit diagonal cell step",
  () => {
    const result =
      buildNearbyDriverAdjacentCellQuery(
        "sxk97",
        1,
        1,
      );

    assert.notEqual(
      result,
      null,
    );

    assert.equal(
      result?.range.startInclusive,
      result?.geohash,
    );
  },
);

test(
  "inherits rejection of the zero-zero non-adjacent step",
  () => {
    assert.throws(
      () =>
        buildNearbyDriverAdjacentCellQuery(
          "sxk97",
          0,
          0,
        ),
      TypeError,
    );
  },
);

test(
  "inherits canonical geohash validation",
  () => {
    assert.throws(
      () =>
        buildNearbyDriverAdjacentCellQuery(
          "SXK97",
          0,
          1,
        ),
      TypeError,
    );

    assert.throws(
      () =>
        buildNearbyDriverAdjacentCellQuery(
          "",
          0,
          1,
        ),
      TypeError,
    );
  },
);

test(
  "output contains only one adjacent geohash and one lexical range",
  () => {
    const result =
      buildNearbyDriverAdjacentCellQuery(
        "sxk97",
        0,
        1,
      );

    assert.notEqual(
      result,
      null,
    );

    assert.deepEqual(
      Object.keys(result ?? {}).sort(),
      [
        "geohash",
        "range",
      ],
    );

    assert.deepEqual(
      Object.keys(result?.range ?? {}).sort(),
      [
        "endExclusive",
        "startInclusive",
      ],
    );

    for (const forbidden of [
      "neighbors",
      "radiusMeters",
      "resultLimit",
      "prefixLength",
      "latitude",
      "longitude",
      "driverId",
    ]) {
      assert.equal(
        forbidden in (result ?? {}),
        false,
      );
    }
  },
);
