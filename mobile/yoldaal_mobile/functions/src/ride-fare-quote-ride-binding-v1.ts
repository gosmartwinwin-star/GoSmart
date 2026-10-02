import {
  CreateRideRequestInput,
} from "./ride-lifecycle-helpers.js";
import {
  fareQuoteOperationIdV1,
  fareQuoteRequestDigestV1,
  validateFareQuoteRequestV1,
} from "./ride-fare-quote-persistence-v1.js";
import {
  projectPassengerFareQuoteViewV1,
} from "./ride-fare-quote-passenger-view-v1.js";

export type RideFareBindingV1 = {
  quoteId: string;
  currency: "TRY";
  yoldaalFareMinor: number;
};

const fail = (reason: string): never => {
  throw new RangeError(reason);
};

const isRecord = (
  value: unknown,
): value is Record<string, unknown> =>
  typeof value === "object" &&
  value !== null &&
  !Array.isArray(value);

export const bindFareQuoteToCreateRideV1 = (
  passengerId: string,
  rawInput: CreateRideRequestInput,
  rawPersistedQuote: unknown,
): RideFareBindingV1 => {
  const input =
    validateFareQuoteRequestV1(rawInput);
  const expectedQuoteId =
    fareQuoteOperationIdV1(
      passengerId,
      input.requestId,
    );
  const expectedQuoteDigest =
    fareQuoteRequestDigestV1(input);

  const view =
    projectPassengerFareQuoteViewV1(
      rawPersistedQuote,
      passengerId,
      expectedQuoteId,
    );

  if (
    !isRecord(rawPersistedQuote) ||
    rawPersistedQuote.requestDigest !==
      expectedQuoteDigest
  ) {
    return fail(
      "fare_quote_request_binding_mismatch",
    );
  }

  return {
    quoteId: view.quoteId,
    currency: view.currency,
    yoldaalFareMinor:
      view.yoldaalFareMinor,
  };
};
