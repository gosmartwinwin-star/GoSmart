import {
  CreateRideRequestInput,
  rideOperationId,
  rideRequestDigest,
  validateCreateRideRequestPayload,
} from "./ride-lifecycle-helpers.js";
import {
  FareQuoteSnapshotV1,
} from "./ride-fare-quote-v1.js";

export const CREATE_FARE_QUOTE_CALLABLE_NAME =
  "createFareQuote" as const;

export type FareQuoteRequestV1 = CreateRideRequestInput;

export type PersistedFareQuoteV1 =
  FareQuoteSnapshotV1 & {
    passengerId: string;
    requestDigest: string;
  };

const fail = (reason: string): never => {
  throw new RangeError(reason);
};

const requireTrustedPassengerId = (
  value: string,
): string => {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > 128
  ) {
    return fail("fare_quote_passenger_id_invalid");
  }
  return value;
};

const requireDigest = (
  value: string,
): string => {
  if (
    typeof value !== "string" ||
    !/^[a-f0-9]{64}$/u.test(value)
  ) {
    return fail("fare_quote_request_digest_invalid");
  }
  return value;
};

export const validateFareQuoteRequestV1 = (
  raw: unknown,
): FareQuoteRequestV1 =>
  validateCreateRideRequestPayload(raw);

export const fareQuoteOperationIdV1 = (
  passengerId: string,
  requestId: string,
): string =>
  rideOperationId(
    requireTrustedPassengerId(passengerId),
    CREATE_FARE_QUOTE_CALLABLE_NAME,
    requestId,
  );

export const fareQuoteRequestDigestV1 = (
  input: FareQuoteRequestV1,
): string =>
  rideRequestDigest(
    CREATE_FARE_QUOTE_CALLABLE_NAME,
    input,
  );

export const buildPersistedFareQuoteV1 = (
  passengerIdRaw: string,
  input: FareQuoteRequestV1,
  quote: FareQuoteSnapshotV1,
): PersistedFareQuoteV1 => {
  const passengerId =
    requireTrustedPassengerId(passengerIdRaw);
  const requestDigest =
    fareQuoteRequestDigestV1(input);

  if (quote.quoteId.length === 0) {
    return fail("fare_quote_id_invalid");
  }

  return {
    ...quote,
    passengerId,
    requestDigest,
  };
};

export const replayFareQuoteOperationV1 = (
  raw: unknown,
  expectedDigestRaw: string,
): Record<string, unknown> => {
  const expectedDigest =
    requireDigest(expectedDigestRaw);

  if (
    typeof raw !== "object" ||
    raw === null ||
    Array.isArray(raw)
  ) {
    return fail("fare_quote_operation_invalid");
  }

  const operation =
    raw as Record<string, unknown>;

  if (operation.requestDigest !== expectedDigest) {
    return fail("idempotency_payload_mismatch");
  }

  if (
    operation.status !== "completed" ||
    typeof operation.result !== "object" ||
    operation.result === null ||
    Array.isArray(operation.result)
  ) {
    return fail("fare_quote_operation_in_progress");
  }

  return operation.result as Record<string, unknown>;
};
