import assert from "node:assert/strict";
import test from "node:test";

import {
  RETURN_ROUTE_CORRIDOR_ROOT_PREFIX,
  buildReturnRouteCorridorPrefixes,
  buildReturnRoutePickupQueryTerms,
  coarsenReturnRouteCorridorPrefixes,
} from "./return-route-corridor-prefix-helpers.js";

const prefixCovers = (
  original: string,
  covering: string,
): boolean =>
  covering ===
    RETURN_ROUTE_CORRIDOR_ROOT_PREFIX ||
  original.startsWith(covering);

test(
  "pickup query contains root plus all 12 ancestors",
  () => {
    const terms =
      buildReturnRoutePickupQueryTerms({
        latitude: 41.015,
        longitude: 28.979,
      });

    assert.equal(
      terms.length,
      13,
    );

    assert.equal(
      terms[0],
      RETURN_ROUTE_CORRIDOR_ROOT_PREFIX,
    );

    const leaf =
      terms[terms.length - 1];

    assert.equal(
      leaf.length,
      12,
    );

    assert.equal(
      new Set(terms).size,
      13,
    );

    for (
      let index = 1;
      index < terms.length;
      index += 1
    ) {
      assert.equal(
        terms[index],
        leaf.slice(
          0,
          index,
        ),
      );
    }
  },
);

test(
  "normalization removes duplicates and descendants",
  () => {
    assert.deepEqual(
      coarsenReturnRouteCorridorPrefixes(
        [
          "u1x",
          "u1x",
          "u1xj",
          "u1y",
        ],
        8,
      ),
      [
        "u1x",
        "u1y",
      ],
    );
  },
);

test(
  "root prefix subsumes every ordinary prefix",
  () => {
    assert.deepEqual(
      coarsenReturnRouteCorridorPrefixes(
        [
          "u1x",
          "*",
          "sxk",
        ],
        8,
      ),
      ["*"],
    );
  },
);

test(
  "coarsening obeys hard cap for disjoint prefixes",
  () => {
    assert.deepEqual(
      coarsenReturnRouteCorridorPrefixes(
        [
          "u1xj4d",
          "sxk9zz",
          "ezs42p",
        ],
        1,
      ),
      ["*"],
    );
  },
);

test(
  "coarsening preserves superset coverage",
  () => {
    const original = [
      "u1xj4d",
      "u1xj4e",
      "sxk9zz",
      "ezs42p",
    ];

    const result =
      coarsenReturnRouteCorridorPrefixes(
        original,
        2,
      );

    assert.ok(
      result.length <= 2,
    );

    for (const prefix of original) {
      assert.ok(
        result.some(
          (covering) =>
            prefixCovers(
              prefix,
              covering,
            ),
        ),
      );
    }
  },
);

test(
  "coarsening is deterministic independent of input order",
  () => {
    const values = [
      "u1xj4d",
      "u1xj4e",
      "u1xj5b",
      "sxk9zz",
      "ezs42p",
    ];

    const forward =
      coarsenReturnRouteCorridorPrefixes(
        values,
        3,
      );

    const reverse =
      coarsenReturnRouteCorridorPrefixes(
        [...values].reverse(),
        3,
      );

    assert.deepEqual(
      forward,
      reverse,
    );
  },
);

test(
  "corridor builder returns bounded non-empty superset",
  () => {
    const prefixes =
      buildReturnRouteCorridorPrefixes({
        routePoints: [
          {
            latitude: 41.015,
            longitude: 28.979,
          },
          {
            latitude: 41.020,
            longitude: 29.030,
          },
        ],
        radiusMeters: 3000,
        initialPrecision: 6,
        maxPrefixCount: 8,
      });

    assert.ok(
      prefixes.length >= 1,
    );

    assert.ok(
      prefixes.length <= 8,
    );
  },
);

test(
  "polar coverage failure falls back to root superset",
  () => {
    const prefixes =
      buildReturnRouteCorridorPrefixes({
        routePoints: [
          {
            latitude: 89.999,
            longitude: 0,
          },
          {
            latitude: 89.998,
            longitude: 1,
          },
        ],
        radiusMeters: 3000,
        initialPrecision: 6,
        maxPrefixCount: 24,
      });

    assert.deepEqual(
      prefixes,
      ["*"],
    );
  },
);

test(
  "corridor builder rejects fewer than two route points",
  () => {
    assert.throws(
      () =>
        buildReturnRouteCorridorPrefixes({
          routePoints: [
            {
              latitude: 41,
              longitude: 29,
            },
          ],
          radiusMeters: 3000,
          initialPrecision: 6,
          maxPrefixCount: 24,
        }),
      TypeError,
    );
  },
);

test(
  "corridor helper rejects invalid cap and precision",
  () => {
    assert.throws(
      () =>
        coarsenReturnRouteCorridorPrefixes(
          ["u1x"],
          0,
        ),
      TypeError,
    );

    assert.throws(
      () =>
        buildReturnRouteCorridorPrefixes({
          routePoints: [
            {
              latitude: 41,
              longitude: 29,
            },
            {
              latitude: 41.1,
              longitude: 29.1,
            },
          ],
          radiusMeters: 3000,
          initialPrecision: 13,
          maxPrefixCount: 24,
        }),
      TypeError,
    );
  },
);
