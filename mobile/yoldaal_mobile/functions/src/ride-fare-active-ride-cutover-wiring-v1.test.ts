/* eslint-disable max-len */
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";

const indexSource =
  readFileSync(
    "src/index.ts",
    "utf8",
  );

const passengerActiveRideSource = (() => {
  const start =
    indexSource.indexOf(
      "export const getMyActiveRide = onCall(",
    );
  const end =
    indexSource.indexOf(
      "export const getMyRideHistory = onCall(",
      start,
    );

  assert.ok(start >= 0);
  assert.ok(end > start);
  return indexSource.slice(start, end);
})();

const driverActiveRideSource = (() => {
  const start =
    indexSource.indexOf(
      "export const getMyActiveDriverRide = onCall(",
    );
  const end =
    indexSource.indexOf(
      "/* eslint-enable max-len */",
      start,
    );

  assert.ok(start >= 0);
  assert.ok(end > start);
  return indexSource.slice(start, end);
})();

test(
  "index imports fare-bound active ride serializer exactly once",
  () => {
    assert.equal(
      (
        indexSource.match(
          /serializeFareBoundActiveRideV1/gu,
        ) ?? []
      ).length,
      3,
    );
    assert.doesNotMatch(
      indexSource,
      /\bserializeActiveRide\b/u,
    );
  },
);

test(
  "passenger active ride returns fare-bound serialization",
  () => {
    assert.match(
      passengerActiveRideSource,
      /return \{activeRide: serializeFareBoundActiveRideV1\(ride\.id, data\)\};/u,
    );
    assert.match(
      passengerActiveRideSource,
      /passengerActiveRides/u,
    );
    assert.match(
      passengerActiveRideSource,
      /data\.passengerId !== passengerId/u,
    );
  },
);

test(
  "driver active ride returns fare-bound serialization",
  () => {
    assert.match(
      driverActiveRideSource,
      /return \{activeRide: serializeFareBoundActiveRideV1\(ride\.id, data\)\};/u,
    );
    assert.match(
      driverActiveRideSource,
      /driverActiveRides/u,
    );
    assert.match(
      driverActiveRideSource,
      /data\.driverId !== driverId/u,
    );
  },
);

test(
  "active ride cutover adds no client pricing authority",
  () => {
    const combined =
      passengerActiveRideSource +
      driverActiveRideSource;

    assert.doesNotMatch(
      combined,
      /quoteId|tariffZoneId|tariffVersionId|farePolicyVersionId|yoldaalFareMinor/u,
    );
  },
);

test(
  "active ride index wiring does not own driver offer fare projection",
  () => {
    assert.doesNotMatch(
      indexSource,
      /attachFareToDriverOfferV1/u,
    );
  },
);
