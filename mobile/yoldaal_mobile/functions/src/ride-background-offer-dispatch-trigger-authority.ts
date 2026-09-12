import {
  buildRideOfferHintInitialDispatchEnvelope,
} from "./ride-background-offer-dispatch-policy.js";
import type {
  RideOfferHintInitialDispatchEnvelope,
} from "./ride-background-offer-dispatch-policy.js";
import {
  classifyRideBackgroundOfferHint,
} from "./ride-background-offer-hint-helpers.js";

export type RideBackgroundOfferInitialDispatchPlanInput =
  Readonly<{
    beforeValue: unknown;
    afterValue: unknown;
    eventId: unknown;
    eventTime: unknown;
    rideId: unknown;
  }>;

export type RideBackgroundOfferInitialDispatchPlan =
  RideOfferHintInitialDispatchEnvelope;

const plainRecord = (
  value: unknown,
): Record<string, unknown> | null => {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value) ||
    Object.getPrototypeOf(value) !==
      Object.prototype
  ) {
    return null;
  }

  return value as Record<string, unknown>;
};

export const planRideBackgroundOfferInitialDispatch = (
  input: RideBackgroundOfferInitialDispatchPlanInput,
): RideBackgroundOfferInitialDispatchPlan | null => {
  const hint =
    classifyRideBackgroundOfferHint(
      input.beforeValue,
      input.afterValue,
    );

  if (hint === null) {
    return null;
  }

  const after =
    plainRecord(
      input.afterValue,
    );

  if (after === null) {
    return null;
  }

  return buildRideOfferHintInitialDispatchEnvelope({
    eventId:
      input.eventId,
    eventTime:
      input.eventTime,
    rideId:
      input.rideId,
    matchRound:
      after.matchRound,
  });
};
