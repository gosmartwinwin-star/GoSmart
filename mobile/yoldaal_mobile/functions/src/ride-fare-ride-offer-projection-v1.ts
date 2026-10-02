import {
  RideFareBindingV1,
} from "./ride-fare-quote-ride-binding-v1.js";

export type RideParticipantFareV1 =
  RideFareBindingV1;

export type DriverRideMatchOfferFareV1 = {
  currency: "TRY";
  yoldaalFareMinor: number;
};

const RIDE_KEYS = [
  "quoteId",
  "currency",
  "yoldaalFareMinor",
] as const;

const fail = (reason: string): never => {
  throw new RangeError(reason);
};

const isRecord = (
  value: unknown,
): value is Record<string, unknown> =>
  typeof value === "object" &&
  value !== null &&
  !Array.isArray(value);

const exactRecord = (
  value: unknown,
): Record<string, unknown> => {
  if (!isRecord(value)) {
    return fail(
      "ride_fare_projection_invalid",
    );
  }

  const keys = Object.keys(value).sort();
  const expected = [...RIDE_KEYS].sort();

  if (
    keys.length !== expected.length ||
    keys.some(
      (key, index) =>
        key !== expected[index],
    )
  ) {
    return fail(
      "ride_fare_projection_invalid",
    );
  }

  return value;
};

const parseAmount = (
  value: unknown,
): number => {
  if (
    !Number.isSafeInteger(value) ||
    (value as number) < 0
  ) {
    return fail(
      "ride_fare_projection_invalid",
    );
  }

  return value as number;
};

const SHA256_HEX =
  /^[0-9a-f]{64}$/u;

export const parseRideParticipantFareV1 = (
  raw: unknown,
): RideParticipantFareV1 => {
  const value = exactRecord(raw);

  if (
    typeof value.quoteId !== "string" ||
    !SHA256_HEX.test(value.quoteId) ||
    value.currency !== "TRY"
  ) {
    return fail(
      "ride_fare_projection_invalid",
    );
  }

  return {
    quoteId: value.quoteId,
    currency: "TRY",
    yoldaalFareMinor:
      parseAmount(
        value.yoldaalFareMinor,
      ),
  };
};

export const buildRideParticipantFareV1 = (
  binding: RideFareBindingV1,
): RideParticipantFareV1 =>
  parseRideParticipantFareV1(binding);

export const projectDriverRideMatchOfferFareV1 = (
  rawRideFare: unknown,
): DriverRideMatchOfferFareV1 => {
  const rideFare =
    parseRideParticipantFareV1(
      rawRideFare,
    );

  return {
    currency: rideFare.currency,
    yoldaalFareMinor:
      rideFare.yoldaalFareMinor,
  };
};
