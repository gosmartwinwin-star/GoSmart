import assert from "node:assert/strict";
import test from "node:test";
import {Timestamp} from "firebase-admin/firestore";

import {
  buildNearbyDriverGeoIndexRecord,
  encodeNearbyDriverGeoHash,
} from "./nearby-driver-geo-index-helpers.js";

test(
  "encodes standard geohash reference coordinates",
  () => {
    assert.equal(
      encodeNearbyDriverGeoHash(
        {
          latitude: 42.6,
          longitude: -5.6,
        },
        5,
      ),
      "ezs42",
    );

    assert.equal(
      encodeNearbyDriverGeoHash(
        {
          latitude: 57.64911,
          longitude: 10.40744,
        },
        11,
      ),
      "u4pruydqqvj",
    );
  },
);

test(
  "requires caller-selected precision with no default",
  () => {
    const coordinate = {
      latitude: 41.0082,
      longitude: 28.9784,
    };

    const coarse =
      encodeNearbyDriverGeoHash(
        coordinate,
        5,
      );

    const finer =
      encodeNearbyDriverGeoHash(
        coordinate,
        8,
      );

    assert.equal(
      coarse,
      "sxk97",
    );

    assert.equal(
      finer,
      "sxk973m6",
    );

    assert.equal(
      finer.startsWith(coarse),
      true,
    );
  },
);

test(
  "rejects invalid technical precision values",
  () => {
    const coordinate = {
      latitude: 41,
      longitude: 29,
    };

    for (const precision of [
      0,
      13,
      1.5,
      Number.NaN,
      Number.POSITIVE_INFINITY,
    ]) {
      assert.throws(
        () =>
          encodeNearbyDriverGeoHash(
            coordinate,
            precision,
          ),
        TypeError,
      );
    }
  },
);

test(
  "rejects invalid coordinates",
  () => {
    for (const coordinate of [
      {
        latitude: 91,
        longitude: 29,
      },
      {
        latitude: -91,
        longitude: 29,
      },
      {
        latitude: 41,
        longitude: 181,
      },
      {
        latitude: 41,
        longitude: -181,
      },
      {
        latitude: Number.NaN,
        longitude: 29,
      },
    ]) {
      assert.throws(
        () =>
          encodeNearbyDriverGeoHash(
            coordinate,
            8,
          ),
        TypeError,
      );
    }
  },
);

test(
  "accepts canonical coordinate boundaries",
  () => {
    assert.equal(
      encodeNearbyDriverGeoHash(
        {
          latitude: -90,
          longitude: -180,
        },
        1,
      ).length,
      1,
    );

    assert.equal(
      encodeNearbyDriverGeoHash(
        {
          latitude: 90,
          longitude: 180,
        },
        12,
      ).length,
      12,
    );
  },
);

test(
  "builds a minimal server-only derived index record",
  () => {
    const updatedAt =
      Timestamp.fromMillis(123456789);

    const record =
      buildNearbyDriverGeoIndexRecord(
        "driver-1",
        {
          latitude: 41.0082,
          longitude: 28.9784,
        },
        updatedAt,
        8,
      );

    assert.deepEqual(
      Object.keys(record).sort(),
      [
        "driverId",
        "geohash",
        "updatedAt",
      ],
    );

    assert.equal(
      record.driverId,
      "driver-1",
    );

    assert.equal(
      record.geohash,
      "sxk973m6",
    );

    assert.equal(
      record.updatedAt,
      updatedAt,
    );
  },
);

test(
  "derived record does not expose raw location or profile data",
  () => {
    const record =
      buildNearbyDriverGeoIndexRecord(
        "driver-1",
        {
          latitude: 41.0082,
          longitude: 28.9784,
        },
        Timestamp.fromMillis(123456789),
        8,
      );

    for (const forbidden of [
      "latitude",
      "longitude",
      "name",
      "displayName",
      "vehicle",
      "vehiclePlate",
      "plate",
      "rating",
    ]) {
      assert.equal(
        forbidden in record,
        false,
      );
    }
  },
);

test(
  "derived record contains no discovery radius or result limit",
  () => {
    const record =
      buildNearbyDriverGeoIndexRecord(
        "driver-1",
        {
          latitude: 41.0082,
          longitude: 28.9784,
        },
        Timestamp.fromMillis(123456789),
        8,
      );

    assert.equal(
      "radiusMeters" in record,
      false,
    );

    assert.equal(
      "resultLimit" in record,
      false,
    );
  },
);

test(
  "rejects invalid derived record identity or timestamp",
  () => {
    assert.throws(
      () =>
        buildNearbyDriverGeoIndexRecord(
          "",
          {
            latitude: 41,
            longitude: 29,
          },
          Timestamp.fromMillis(1),
          8,
        ),
      TypeError,
    );

    assert.throws(
      () =>
        buildNearbyDriverGeoIndexRecord(
          "driver-1",
          {
            latitude: 41,
            longitude: 29,
          },
          {} as Timestamp,
          8,
        ),
      TypeError,
    );
  },
);
