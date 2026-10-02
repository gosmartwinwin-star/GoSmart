import assert from "node:assert/strict";
import test from "node:test";
import {
  RIDE_FARE_FIELD_V1,
  embedRideFareV1,
  parseRideFareFromRecordV1,
  projectDriverOfferFareFromRideV1,
} from "./ride-fare-ride-embedding-v1.js";
import {
  RideFareBindingV1,
} from "./ride-fare-quote-ride-binding-v1.js";

const quoteId = "b".repeat(64);

const binding = (
  amount = 27480,
): RideFareBindingV1 => ({
  quoteId,
  currency: "TRY",
  yoldaalFareMinor: amount,
});

const baseRide = () => ({
  passengerId: "passenger-1",
  status: "matching",
  version: 1,
  pickup: {
    latitude: 39.92,
    longitude: 32.85,
    addressLabel: "Pickup",
  },
  dropoff: {
    latitude: 39.95,
    longitude: 32.88,
    addressLabel: "Dropoff",
  },
});

test(
  "embedding adds one canonical nested fare field",
  () => {
    const base = baseRide();
    const result =
      embedRideFareV1(
        base,
        binding(),
      );

    assert.deepEqual(
      result.fare,
      {
        quoteId,
        currency: "TRY",
        yoldaalFareMinor: 27480,
      },
    );

    assert.deepEqual(
      Object.keys(result)
        .filter(
          (key) =>
            !(key in base),
        ),
      [RIDE_FARE_FIELD_V1],
    );
  },
);

test(
  "embedding does not mutate caller base ride",
  () => {
    const base = baseRide();
    const before =
      structuredClone(base);

    embedRideFareV1(
      base,
      binding(),
    );

    assert.deepEqual(
      base,
      before,
    );
    assert.equal(
      RIDE_FARE_FIELD_V1 in base,
      false,
    );
  },
);

test(
  "embedding rejects non-record and existing fare",
  () => {
    for (const raw of [
      null,
      [],
      "ride",
    ]) {
      assert.throws(
        () =>
          embedRideFareV1(
            raw,
            binding(),
          ),
        /ride_fare_embedding_invalid/u,
      );
    }

    assert.throws(
      () =>
        embedRideFareV1(
          {
            ...baseRide(),
            fare: binding(),
          },
          binding(),
        ),
      /ride_fare_embedding_conflict/u,
    );
  },
);

test(
  "embedding rejects passenger comparison leakage at top level",
  () => {
    for (const leaked of [
      {
        referenceEstimatedFareMinor:
          68700,
      },
      {
        savingMinor: 41220,
      },
      {
        passengerFareBasisPoints:
          4000,
      },
    ]) {
      assert.throws(
        () =>
          embedRideFareV1(
            {
              ...baseRide(),
              ...leaked,
            },
            binding(),
          ),
        /ride_fare_embedding_leak/u,
      );
    }
  },
);

test(
  "embedding rejects quote provenance leakage at top level",
  () => {
    for (const leaked of [
      {tariffZoneId: "zone"},
      {tariffVersionId: "tariff"},
      {farePolicyVersionId: "policy"},
      {requestDigest: "a".repeat(64)},
      {authorityName: "authority"},
    ]) {
      assert.throws(
        () =>
          embedRideFareV1(
            {
              ...baseRide(),
              ...leaked,
            },
            binding(),
          ),
        /ride_fare_embedding_leak/u,
      );
    }
  },
);

test(
  "nested fare is extracted through exact parser",
  () => {
    const ride =
      embedRideFareV1(
        baseRide(),
        binding(),
      );

    assert.deepEqual(
      parseRideFareFromRecordV1(
        ride,
      ),
      binding(),
    );
  },
);

test(
  "missing or malformed nested fare fails closed",
  () => {
    assert.throws(
      () =>
        parseRideFareFromRecordV1(
          baseRide(),
        ),
      /ride_fare_required/u,
    );

    assert.throws(
      () =>
        parseRideFareFromRecordV1({
          ...baseRide(),
          fare: {
            ...binding(),
            savingMinor: 41220,
          },
        }),
      /ride_fare_projection_invalid/u,
    );
  },
);

test(
  "driver offer projection comes only from nested fare",
  () => {
    const ride =
      embedRideFareV1(
        baseRide(),
        binding(),
      );

    assert.deepEqual(
      projectDriverOfferFareFromRideV1(
        ride,
      ),
      {
        currency: "TRY",
        yoldaalFareMinor: 27480,
      },
    );
  },
);

test(
  "driver projection exposes no quote or passenger comparison",
  () => {
    const ride =
      embedRideFareV1(
        baseRide(),
        binding(),
      );
    const projected =
      projectDriverOfferFareFromRideV1(
        ride,
      );
    const keys =
      Object.keys(projected);

    for (const key of [
      "quoteId",
      "referenceEstimatedFareMinor",
      "savingMinor",
      "passengerFareBasisPoints",
      "tariffVersionId",
      "farePolicyVersionId",
      "requestDigest",
    ]) {
      assert.equal(
        keys.includes(key),
        false,
      );
    }
  },
);

test(
  "embedding invents no expiry or fee components",
  () => {
    const ride =
      embedRideFareV1(
        baseRide(),
        binding(0),
      );

    for (const key of [
      "expiresAtMillis",
      "waitingFeeMinor",
      "tollFeeMinor",
      "parkingFeeMinor",
    ]) {
      assert.equal(
        key in ride,
        false,
      );
      assert.equal(
        key in ride.fare,
        false,
      );
    }

    assert.equal(
      ride.fare.yoldaalFareMinor,
      0,
    );
  },
);
