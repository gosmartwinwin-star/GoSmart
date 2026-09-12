import assert from "node:assert/strict";
import test from "node:test";

import {
  selectNearbyDriverGeoPrecision,
} from "./nearby-driver-geohash-precision-selection-helpers.js";

test(
  "selects the finest precision satisfying caller supplied caps",
  () => {
    const selected =
      selectNearbyDriverGeoPrecision(
        [
          {
            precision: 4,
            rangeCount: 9,
            overfetchAreaRatio: 20,
          },
          {
            precision: 5,
            rangeCount: 16,
            overfetchAreaRatio: 4,
          },
          {
            precision: 6,
            rangeCount: 108,
            overfetchAreaRatio: 1.5,
          },
        ],
        {
          maxRangeCount: 20,
          maxOverfetchAreaRatio: 5,
        },
      );

    assert.deepEqual(
      selected,
      {
        precision: 5,
        rangeCount: 16,
        overfetchAreaRatio: 4,
      },
    );
  },
);

test(
  "does not assume measurements are ordered by precision",
  () => {
    const selected =
      selectNearbyDriverGeoPrecision(
        [
          {
            precision: 6,
            rangeCount: 100,
            overfetchAreaRatio: 1.5,
          },
          {
            precision: 4,
            rangeCount: 8,
            overfetchAreaRatio: 10,
          },
          {
            precision: 5,
            rangeCount: 16,
            overfetchAreaRatio: 3,
          },
        ],
        {
          maxRangeCount: 20,
          maxOverfetchAreaRatio: 5,
        },
      );

    assert.equal(
      selected?.precision,
      5,
    );
  },
);

test(
  "returns null when no precision satisfies both caps",
  () => {
    const selected =
      selectNearbyDriverGeoPrecision(
        [
          {
            precision: 4,
            rangeCount: 9,
            overfetchAreaRatio: 20,
          },
          {
            precision: 5,
            rangeCount: 16,
            overfetchAreaRatio: 4,
          },
        ],
        {
          maxRangeCount: 8,
          maxOverfetchAreaRatio: 3,
        },
      );

    assert.equal(
      selected,
      null,
    );
  },
);

test(
  "returns null for an empty measurement set",
  () => {
    assert.equal(
      selectNearbyDriverGeoPrecision(
        [],
        {
          maxRangeCount: 10,
          maxOverfetchAreaRatio: 2,
        },
      ),
      null,
    );
  },
);

test(
  "requires both range and overfetch caps to pass",
  () => {
    const selected =
      selectNearbyDriverGeoPrecision(
        [
          {
            precision: 5,
            rangeCount: 10,
            overfetchAreaRatio: 8,
          },
          {
            precision: 6,
            rangeCount: 40,
            overfetchAreaRatio: 2,
          },
        ],
        {
          maxRangeCount: 20,
          maxOverfetchAreaRatio: 4,
        },
      );

    assert.equal(
      selected,
      null,
    );
  },
);

test(
  "accepts values exactly on both inclusive caps",
  () => {
    const selected =
      selectNearbyDriverGeoPrecision(
        [
          {
            precision: 7,
            rangeCount: 24,
            overfetchAreaRatio: 3,
          },
        ],
        {
          maxRangeCount: 24,
          maxOverfetchAreaRatio: 3,
        },
      );

    assert.equal(
      selected?.precision,
      7,
    );
  },
);

test(
  "rejects invalid caller supplied caps fail closed",
  () => {
    const measurements = [
      {
        precision: 5,
        rangeCount: 10,
        overfetchAreaRatio: 2,
      },
    ];

    assert.throws(
      () =>
        selectNearbyDriverGeoPrecision(
          measurements,
          {
            maxRangeCount: 0,
            maxOverfetchAreaRatio: 2,
          },
        ),
      TypeError,
    );

    assert.throws(
      () =>
        selectNearbyDriverGeoPrecision(
          measurements,
          {
            maxRangeCount: 10,
            maxOverfetchAreaRatio: 0.5,
          },
        ),
      TypeError,
    );
  },
);

test(
  "rejects invalid precision measurements fail closed",
  () => {
    assert.throws(
      () =>
        selectNearbyDriverGeoPrecision(
          [
            {
              precision: 13,
              rangeCount: 10,
              overfetchAreaRatio: 2,
            },
          ],
          {
            maxRangeCount: 20,
            maxOverfetchAreaRatio: 4,
          },
        ),
      TypeError,
    );

    assert.throws(
      () =>
        selectNearbyDriverGeoPrecision(
          [
            {
              precision: 5,
              rangeCount: 0,
              overfetchAreaRatio: 2,
            },
          ],
          {
            maxRangeCount: 20,
            maxOverfetchAreaRatio: 4,
          },
        ),
      TypeError,
    );
  },
);

test(
  "rejects duplicate precision measurements",
  () => {
    assert.throws(
      () =>
        selectNearbyDriverGeoPrecision(
          [
            {
              precision: 5,
              rangeCount: 10,
              overfetchAreaRatio: 2,
            },
            {
              precision: 5,
              rangeCount: 12,
              overfetchAreaRatio: 3,
            },
          ],
          {
            maxRangeCount: 20,
            maxOverfetchAreaRatio: 4,
          },
        ),
      TypeError,
    );
  },
);

test(
  "does not mutate caller measurements",
  () => {
    const measurements = [
      {
        precision: 4,
        rangeCount: 9,
        overfetchAreaRatio: 10,
      },
      {
        precision: 5,
        rangeCount: 16,
        overfetchAreaRatio: 3,
      },
    ];

    const before =
      JSON.stringify(
        measurements,
      );

    selectNearbyDriverGeoPrecision(
      measurements,
      {
        maxRangeCount: 20,
        maxOverfetchAreaRatio: 5,
      },
    );

    assert.equal(
      JSON.stringify(
        measurements,
      ),
      before,
    );
  },
);

test(
  "returns a copy rather than caller owned measurement",
  () => {
    const measurement = {
      precision: 5,
      rangeCount: 16,
      overfetchAreaRatio: 3,
    };

    const selected =
      selectNearbyDriverGeoPrecision(
        [
          measurement,
        ],
        {
          maxRangeCount: 20,
          maxOverfetchAreaRatio: 5,
        },
      );

    assert.notEqual(
      selected,
      measurement,
    );

    assert.deepEqual(
      selected,
      measurement,
    );
  },
);
