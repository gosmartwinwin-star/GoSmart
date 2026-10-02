import assert from "node:assert/strict";
import test from "node:test";
import {
  Timestamp,
} from "firebase-admin/firestore";
import {
  CreateRideRequestInput,
  RideRoute,
} from "./ride-lifecycle-helpers.js";
import {
  RideFareBindingV1,
} from "./ride-fare-quote-ride-binding-v1.js";
import {
  attachFareToCreateRideResultV1,
  attachFareToDriverOfferV1,
  buildFareBoundInitialRideV1,
  serializeFareBoundActiveRideV1,
} from "./ride-fare-production-wiring-adapter-v1.js";

const quoteId = "d".repeat(64);
const now =
  Timestamp.fromMillis(
    1757000000000,
  );

const input: CreateRideRequestInput = {
  requestId:
    "shared_quote_ride_request_1234",
  pickup: {
    latitude: 39.92077,
    longitude: 32.85411,
    addressLabel: "Pickup",
  },
  dropoff: {
    latitude: 39.95,
    longitude: 32.88,
    addressLabel: "Dropoff",
  },
};

const route: RideRoute = {
  distanceMeters: 18200,
  durationSeconds: 2400,
  encodedPolyline: "encoded",
};

const binding = (
  amount = 27480,
): RideFareBindingV1 => ({
  quoteId,
  currency: "TRY",
  yoldaalFareMinor: amount,
});

const persistedRide = (
  amount = 27480,
) =>
  buildFareBoundInitialRideV1(
    "passenger-1",
    input,
    route,
    now,
    binding(amount),
  );

const createResult = () => ({
  rideId: "ride_1234",
  status: "matching",
  version: 1,
  createdAtMillis: now.toMillis(),
  distanceMeters:
    route.distanceMeters,
  durationSeconds:
    route.durationSeconds,
  encodedPolyline:
    route.encodedPolyline,
});

const offer = () => ({
  rideId: "ride_1234",
  rideVersion: 1,
  pickup: input.pickup,
  dropoff: input.dropoff,
  pickupDetourMeters: 120,
  pickupDetourSeconds: 40,
  dropoffDetourMeters: 80,
  dropoffDetourSeconds: 30,
  passengerTripDistanceMeters:
    route.distanceMeters,
  passengerTripDurationSeconds:
    route.durationSeconds,
  expiresAtMillis:
    now.toMillis() + 300000,
});

test(
  "initial ride composes tracked ride shape with canonical fare",
  () => {
    const ride = persistedRide();

    assert.equal(
      ride.passengerId,
      "passenger-1",
    );
    assert.equal(
      ride.status,
      "matching",
    );
    assert.deepEqual(
      ride.fare,
      binding(),
    );
  },
);

test(
  "initial ride keeps passenger comparison and provenance off top level",
  () => {
    const ride = persistedRide();

    for (const key of [
      "referenceEstimatedFareMinor",
      "savingMinor",
      "passengerFareBasisPoints",
      "tariffZoneId",
      "tariffVersionId",
      "farePolicyVersionId",
      "requestDigest",
    ]) {
      assert.equal(
        key in ride,
        false,
      );
    }
  },
);

test(
  "create result fare is derived from persisted ride",
  () => {
    const result =
      attachFareToCreateRideResultV1(
        createResult(),
        persistedRide(),
      );

    assert.deepEqual(
      result.fare,
      binding(),
    );
  },
);

test(
  "create result adapter preserves base and rejects conflict",
  () => {
    const base = createResult();
    const before =
      structuredClone(base);

    attachFareToCreateRideResultV1(
      base,
      persistedRide(),
    );

    assert.deepEqual(
      base,
      before,
    );
    assert.equal(
      "fare" in base,
      false,
    );

    assert.throws(
      () =>
        attachFareToCreateRideResultV1(
          {
            ...base,
            fare: binding(),
          },
          persistedRide(),
        ),
      /create_ride_fare_result_invalid/u,
    );
  },
);

test(
  "active ride serialization includes canonical fare",
  () => {
    const result =
      serializeFareBoundActiveRideV1(
        "ride_1234",
        persistedRide(),
      );

    assert.deepEqual(
      result.fare,
      binding(),
    );
    assert.equal(
      result.rideId,
      "ride_1234",
    );
    assert.equal(
      result.status,
      "matching",
    );
  },
);

test(
  "create and active serialization fail closed without fare",
  () => {
    const noFare = {
      ...persistedRide(),
    };
    delete noFare.fare;

    assert.throws(
      () =>
        attachFareToCreateRideResultV1(
          createResult(),
          noFare,
        ),
      /ride_fare_required/u,
    );

    assert.throws(
      () =>
        serializeFareBoundActiveRideV1(
          "ride_1234",
          noFare,
        ),
      /ride_fare_required/u,
    );
  },
);

test(
  "driver public offer receives only driver-safe fare",
  () => {
    const result =
      attachFareToDriverOfferV1(
        offer(),
        persistedRide(),
      );

    assert.deepEqual(
      result.fare,
      {
        currency: "TRY",
        yoldaalFareMinor: 27480,
      },
    );
    assert.equal(
      "quoteId" in
        (result.fare as Record<string, unknown>),
      false,
    );
  },
);

test(
  "driver offer adapter preserves base offer",
  () => {
    const base = offer();
    const before =
      structuredClone(base);

    attachFareToDriverOfferV1(
      base,
      persistedRide(),
    );

    assert.deepEqual(
      base,
      before,
    );
    assert.equal(
      "fare" in base,
      false,
    );
  },
);

test(
  "zero fixed fare remains structurally valid across adapter",
  () => {
    const ride = persistedRide(0);
    const active =
      serializeFareBoundActiveRideV1(
        "ride_1234",
        ride,
      );
    const driver =
      attachFareToDriverOfferV1(
        offer(),
        ride,
      );

    assert.equal(
      (active.fare as Record<string, unknown>)
        .yoldaalFareMinor,
      0,
    );
    assert.equal(
      (driver.fare as Record<string, unknown>)
        .yoldaalFareMinor,
      0,
    );
  },
);

test(
  "adapter invents no comparison fee expiry or consumption authority",
  () => {
    const ride = persistedRide();
    const create =
      attachFareToCreateRideResultV1(
        createResult(),
        ride,
      );
    const active =
      serializeFareBoundActiveRideV1(
        "ride_1234",
        ride,
      );
    const driver =
      attachFareToDriverOfferV1(
        offer(),
        ride,
      );

    for (const value of [
      create,
      active,
      driver,
    ]) {
      for (const key of [
        "referenceEstimatedFareMinor",
        "savingMinor",
        "waitingFeeMinor",
        "tollFeeMinor",
        "parkingFeeMinor",
        "fareConsumedAtMillis",
      ]) {
        assert.equal(
          key in value,
          false,
        );
      }
    }
  },
);
