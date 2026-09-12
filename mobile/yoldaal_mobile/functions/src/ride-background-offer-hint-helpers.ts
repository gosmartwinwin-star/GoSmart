export type RideBackgroundOfferHint = {
  type: "ride_offer_available";
};

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

const positiveInteger = (
  value: unknown,
): value is number =>
  typeof value === "number" &&
  Number.isInteger(value) &&
  value > 0;

export const classifyRideBackgroundOfferHint = (
  beforeValue: unknown,
  afterValue: unknown,
): RideBackgroundOfferHint | null => {
  const after =
    plainRecord(afterValue);

  if (
    after === null ||
    after.status !== "matching" ||
    after.driverId !== null ||
    !positiveInteger(
      after.matchRound,
    )
  ) {
    return null;
  }

  if (
    beforeValue === undefined ||
    beforeValue === null
  ) {
    return {
      type:
        "ride_offer_available",
    };
  }

  const before =
    plainRecord(beforeValue);

  if (before === null) {
    return null;
  }

  if (
    before.status !== "matching" ||
    before.driverId !== null ||
    before.matchRound !==
      after.matchRound
  ) {
    return {
      type:
        "ride_offer_available",
    };
  }

  return null;
};
