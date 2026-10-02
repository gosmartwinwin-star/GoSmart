import assert from "node:assert/strict";
import test from "node:test";
import {
  DRIVER_OFFER_FARE_FIELD_V1,
  embedDriverOfferFareFromRideV1,
  parseDriverOfferFareFromRecordV1,
  parseDriverPublicOfferFareV1,
} from "./ride-fare-driver-offer-embedding-v1.js";

const quoteId = "c".repeat(64);

const ride = (
  amount = 27480,
) => ({
  passengerId: "passenger-1",
  status: "matching",
  version: 1,
  fare: {
    quoteId,
    currency: "TRY",
    yoldaalFareMinor: amount,
  },
});

const offer = () => ({
  rideId: "ride_1234",
  rideVersion: 1,
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
  pickupDetourMeters: 120,
  pickupDetourSeconds: 40,
  dropoffDetourMeters: 80,
  dropoffDetourSeconds: 30,
  passengerTripDistanceMeters: 18200,
  passengerTripDurationSeconds: 2400,
  expiresAtMillis: 1757000300000,
});

test(
  "embedding adds one nested driver fare field",
  () => {
    const base = offer();
    const result =
      embedDriverOfferFareFromRideV1(
        base,
        ride(),
      );

    assert.deepEqual(
      result.fare,
      {
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
      [DRIVER_OFFER_FARE_FIELD_V1],
    );
  },
);

test(
  "driver offer embedding preserves caller base offer",
  () => {
    const base = offer();
    const before =
      structuredClone(base);

    embedDriverOfferFareFromRideV1(
      base,
      ride(),
    );

    assert.deepEqual(
      base,
      before,
    );
    assert.equal(
      DRIVER_OFFER_FARE_FIELD_V1 in base,
      false,
    );
  },
);

test(
  "driver fare strips quote identity",
  () => {
    const result =
      embedDriverOfferFareFromRideV1(
        offer(),
        ride(),
      );

    assert.equal(
      "quoteId" in result.fare,
      false,
    );
  },
);

test(
  "driver offer rejects existing fare field",
  () => {
    assert.throws(
      () =>
        embedDriverOfferFareFromRideV1(
          {
            ...offer(),
            fare: {
              currency: "TRY",
              yoldaalFareMinor: 27480,
            },
          },
          ride(),
        ),
      /driver_offer_embedding_conflict/u,
    );
  },
);

test(
  "driver offer rejects top-level monetary leakage",
  () => {
    for (const leaked of [
      {yoldaalFareMinor: 27480},
      {referenceEstimatedFareMinor: 68700},
      {savingMinor: 41220},
      {passengerFareBasisPoints: 4000},
    ]) {
      assert.throws(
        () =>
          embedDriverOfferFareFromRideV1(
            {
              ...offer(),
              ...leaked,
            },
            ride(),
          ),
        /driver_offer_embedding_leak/u,
      );
    }
  },
);

test(
  "driver offer rejects top-level provenance leakage",
  () => {
    for (const leaked of [
      {quoteId},
      {tariffZoneId: "zone"},
      {tariffVersionId: "tariff"},
      {farePolicyVersionId: "policy"},
      {requestDigest: "a".repeat(64)},
      {authorityName: "authority"},
    ]) {
      assert.throws(
        () =>
          embedDriverOfferFareFromRideV1(
            {
              ...offer(),
              ...leaked,
            },
            ride(),
          ),
        /driver_offer_embedding_leak/u,
      );
    }
  },
);

test(
  "driver fare parser is exact",
  () => {
    assert.deepEqual(
      parseDriverPublicOfferFareV1({
        currency: "TRY",
        yoldaalFareMinor: 27480,
      }),
      {
        currency: "TRY",
        yoldaalFareMinor: 27480,
      },
    );

    assert.throws(
      () =>
        parseDriverPublicOfferFareV1({
          currency: "TRY",
          yoldaalFareMinor: 27480,
          quoteId,
        }),
      /driver_offer_fare_invalid/u,
    );
  },
);

test(
  "driver fare parser rejects invalid currency and amount",
  () => {
    for (const raw of [
      {
        currency: "USD",
        yoldaalFareMinor: 27480,
      },
      {
        currency: "TRY",
        yoldaalFareMinor: -1,
      },
      {
        currency: "TRY",
        yoldaalFareMinor: 1.5,
      },
      {
        currency: "TRY",
        yoldaalFareMinor:
          Number.MAX_SAFE_INTEGER + 1,
      },
    ]) {
      assert.throws(
        () =>
          parseDriverPublicOfferFareV1(
            raw,
          ),
        /driver_offer_fare_invalid/u,
      );
    }
  },
);

test(
  "driver fare extraction requires canonical nested fare",
  () => {
    const result =
      embedDriverOfferFareFromRideV1(
        offer(),
        ride(0),
      );

    assert.equal(
      parseDriverOfferFareFromRecordV1(
        result,
      ).yoldaalFareMinor,
      0,
    );

    assert.throws(
      () =>
        parseDriverOfferFareFromRecordV1(
          offer(),
        ),
      /driver_offer_fare_required/u,
    );
  },
);

test(
  "embedding fails closed when ride fare is missing or malformed",
  () => {
    assert.throws(
      () =>
        embedDriverOfferFareFromRideV1(
          offer(),
          {
            passengerId: "passenger-1",
          },
        ),
      /ride_fare_required/u,
    );

    assert.throws(
      () =>
        embedDriverOfferFareFromRideV1(
          offer(),
          {
            ...ride(),
            fare: {
              ...ride().fare,
              savingMinor: 41220,
            },
          },
        ),
      /ride_fare_projection_invalid/u,
    );
  },
);
