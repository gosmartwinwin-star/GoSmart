import {
  Timestamp,
} from "firebase-admin/firestore";
import {
  CreateRideRequestInput,
  RideRoute,
  buildInitialRide,
  serializeActiveRide,
} from "./ride-lifecycle-helpers.js";
import {
  RideFareBindingV1,
} from "./ride-fare-quote-ride-binding-v1.js";
import {
  embedRideFareV1,
  parseRideFareFromRecordV1,
} from "./ride-fare-ride-embedding-v1.js";
import {
  embedDriverOfferFareFromRideV1,
} from "./ride-fare-driver-offer-embedding-v1.js";

const fail = (reason: string): never => {
  throw new RangeError(reason);
};

const isRecord = (
  value: unknown,
): value is Record<string, unknown> =>
  typeof value === "object" &&
  value !== null &&
  !Array.isArray(value);

const requireBaseWithoutFare = (
  raw: unknown,
  reason: string,
): Record<string, unknown> => {
  if (
    !isRecord(raw) ||
    Object.prototype.hasOwnProperty.call(
      raw,
      "fare",
    )
  ) {
    return fail(reason);
  }

  return raw;
};

export const buildFareBoundInitialRideV1 = (
  passengerId: string,
  input: CreateRideRequestInput,
  route: RideRoute,
  now: Timestamp,
  binding: RideFareBindingV1,
): Record<string, unknown> =>
  embedRideFareV1(
    buildInitialRide(
      passengerId,
      input,
      route,
      now,
    ),
    binding,
  );

export const attachFareToCreateRideResultV1 = (
  rawBaseResult: unknown,
  rawPersistedRide: unknown,
): Record<string, unknown> => {
  const base =
    requireBaseWithoutFare(
      rawBaseResult,
      "create_ride_fare_result_invalid",
    );

  return {
    ...base,
    fare:
      parseRideFareFromRecordV1(
        rawPersistedRide,
      ),
  };
};

export const serializeFareBoundActiveRideV1 = (
  rideId: string,
  data: Record<string, unknown>,
): Record<string, unknown> => ({
  ...serializeActiveRide(
    rideId,
    data,
  ),
  fare:
    parseRideFareFromRecordV1(
      data,
    ),
});

export const attachFareToDriverOfferV1 = (
  rawBaseOffer: unknown,
  rawPersistedRide: unknown,
): Record<string, unknown> =>
  embedDriverOfferFareFromRideV1(
    rawBaseOffer,
    rawPersistedRide,
  );
