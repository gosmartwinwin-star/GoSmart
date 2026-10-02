import assert from "node:assert/strict";
import test from "node:test";
import {
  buildRideParticipantFareV1,
  parseRideParticipantFareV1,
  projectDriverRideMatchOfferFareV1,
} from "./ride-fare-ride-offer-projection-v1.js";
import {
  RideFareBindingV1,
} from "./ride-fare-quote-ride-binding-v1.js";

const quoteId = "a".repeat(64);

const binding = (
  amount = 27480,
): RideFareBindingV1 => ({
  quoteId,
  currency: "TRY",
  yoldaalFareMinor: amount,
});

test(
  "canonical binding becomes exact participant ride fare",
  () => {
    assert.deepEqual(
      buildRideParticipantFareV1(
        binding(),
      ),
      {
        quoteId,
        currency: "TRY",
        yoldaalFareMinor: 27480,
      },
    );
  },
);

test(
  "participant ride fare parser is exact",
  () => {
    assert.throws(
      () =>
        parseRideParticipantFareV1({
          ...binding(),
          savingMinor: 41220,
        }),
      /ride_fare_projection_invalid/u,
    );
  },
);

test(
  "participant ride fare requires canonical quote id",
  () => {
    for (const invalidQuoteId of [
      "",
      "A".repeat(64),
      "a".repeat(63),
      "g".repeat(64),
    ]) {
      assert.throws(
        () =>
          parseRideParticipantFareV1({
            ...binding(),
            quoteId: invalidQuoteId,
          }),
        /ride_fare_projection_invalid/u,
      );
    }
  },
);

test(
  "participant ride fare freezes TRY",
  () => {
    assert.throws(
      () =>
        parseRideParticipantFareV1({
          ...binding(),
          currency: "USD",
        }),
      /ride_fare_projection_invalid/u,
    );
  },
);

test(
  "participant ride fare requires safe non-negative minor units",
  () => {
    for (const amount of [
      -1,
      1.5,
      Number.MAX_SAFE_INTEGER + 1,
      Number.NaN,
      Number.POSITIVE_INFINITY,
    ]) {
      assert.throws(
        () =>
          parseRideParticipantFareV1({
            ...binding(),
            yoldaalFareMinor: amount,
          }),
        /ride_fare_projection_invalid/u,
      );
    }

    assert.equal(
      parseRideParticipantFareV1(
        binding(0),
      ).yoldaalFareMinor,
      0,
    );
  },
);

test(
  "driver offer fare strips quote identity",
  () => {
    const projected =
      projectDriverRideMatchOfferFareV1(
        binding(),
      );

    assert.deepEqual(
      projected,
      {
        currency: "TRY",
        yoldaalFareMinor: 27480,
      },
    );

    assert.equal(
      "quoteId" in projected,
      false,
    );
  },
);

test(
  "driver offer contains no passenger comparison fields",
  () => {
    const projected =
      projectDriverRideMatchOfferFareV1(
        binding(),
      );
    const keys = Object.keys(projected);

    for (const key of [
      "referenceEstimatedFareMinor",
      "savingMinor",
      "passengerFareBasisPoints",
      "tariffZoneId",
      "tariffVersionId",
      "farePolicyVersionId",
    ]) {
      assert.equal(
        keys.includes(key),
        false,
      );
    }
  },
);

test(
  "driver offer contains no authority or identity metadata",
  () => {
    const projected =
      projectDriverRideMatchOfferFareV1(
        binding(),
      );
    const keys = Object.keys(projected);

    for (const key of [
      "authorityType",
      "authorityName",
      "sourceUrl",
      "decisionReference",
      "requestDigest",
      "passengerId",
      "quoteId",
    ]) {
      assert.equal(
        keys.includes(key),
        false,
      );
    }
  },
);

test(
  "driver projection fails closed on malformed ride fare",
  () => {
    assert.throws(
      () =>
        projectDriverRideMatchOfferFareV1({
          currency: "TRY",
          yoldaalFareMinor: 27480,
        }),
      /ride_fare_projection_invalid/u,
    );
  },
);

test(
  "projection invents no expiry or fee components",
  () => {
    const participant =
      buildRideParticipantFareV1(
        binding(),
      );
    const driver =
      projectDriverRideMatchOfferFareV1(
        participant,
      );

    for (const value of [
      participant,
      driver,
    ]) {
      for (const key of [
        "expiresAtMillis",
        "waitingFeeMinor",
        "tollFeeMinor",
        "parkingFeeMinor",
      ]) {
        assert.equal(
          key in value,
          false,
        );
      }
    }
  },
);
