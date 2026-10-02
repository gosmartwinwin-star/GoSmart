import {
  HttpsError,
} from "firebase-functions/v2/https";
import {
  createFareQuoteForPassengerV1,
} from "./ride-fare-quote-orchestration-v1.js";
import type {
  PassengerFareQuoteViewV1,
} from "./ride-fare-quote-passenger-view-v1.js";
import {
  createFareQuoteRuntimeProviderV1,
  readPassengerFareQuoteViewV1,
} from "./ride-fare-quote-runtime-v1.js";
import type {
  FareQuoteRuntimeDependenciesV1,
} from "./ride-fare-quote-runtime-v1.js";

export type FareQuoteCallableCreateV1 = (
  passengerId: string,
  rawInput: unknown,
) => Promise<Record<string, unknown>>;

export type FareQuoteCallableReadViewV1 = (
  passengerId: string,
  quoteId: string,
) => Promise<PassengerFareQuoteViewV1>;

export type FareQuoteCallableExecutionDependenciesV1 = {
  createQuoteForPassenger:
    FareQuoteCallableCreateV1;
  readPassengerView:
    FareQuoteCallableReadViewV1;
};

export type FareQuoteCallableHandlerV1 = (
  passengerId: string,
  rawInput: unknown,
) => Promise<PassengerFareQuoteViewV1>;

const SHA256_HEX =
  /^[0-9a-f]{64}$/u;

const hasAsciiControlCharacter = (
  value: string,
): boolean =>
  value.split("").some((character) => {
    const codeUnit = character.charCodeAt(0);
    return codeUnit <= 31 || codeUnit === 127;
  });

const requireTrustedPassengerId = (
  value: string,
): string => {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > 128 ||
    hasAsciiControlCharacter(value)
  ) {
    throw new HttpsError(
      "unauthenticated",
      "Fare quote requires authentication.",
      {reason: "fare_quote_auth_invalid"},
    );
  }
  return value;
};

const requireExactQuoteIdResult = (
  raw: unknown,
): string => {
  if (
    typeof raw !== "object" ||
    raw === null ||
    Array.isArray(raw) ||
    Object.getPrototypeOf(raw) !==
      Object.prototype
  ) {
    throw new HttpsError(
      "internal",
      "Fare quote result is invalid.",
      {reason: "fare_quote_callable_result_invalid"},
    );
  }

  const result =
    raw as Record<string, unknown>;
  const keys = Object.keys(result);
  const quoteId = result.quoteId;

  if (
    keys.length !== 1 ||
    keys[0] !== "quoteId" ||
    typeof quoteId !== "string" ||
    !SHA256_HEX.test(quoteId)
  ) {
    throw new HttpsError(
      "internal",
      "Fare quote result is invalid.",
      {reason: "fare_quote_callable_result_invalid"},
    );
  }

  return quoteId;
};

export const executePassengerFareQuoteCallableV1 =
  async (
    dependencies:
      FareQuoteCallableExecutionDependenciesV1,
    passengerIdRaw: string,
    rawInput: unknown,
  ): Promise<PassengerFareQuoteViewV1> => {
    const passengerId =
      requireTrustedPassengerId(
        passengerIdRaw,
      );

    let rawResult: Record<string, unknown>;
    try {
      rawResult =
        await dependencies
          .createQuoteForPassenger(
            passengerId,
            rawInput,
          );
    } catch (caught: unknown) {
      if (caught instanceof HttpsError) {
        throw caught;
      }
      throw new HttpsError(
        "unavailable",
        "Fare quote could not be created.",
        {
          reason:
            "fare_quote_callable_create_unavailable",
        },
      );
    }

    const quoteId =
      requireExactQuoteIdResult(rawResult);

    try {
      return await dependencies
        .readPassengerView(
          passengerId,
          quoteId,
        );
    } catch (caught: unknown) {
      if (caught instanceof HttpsError) {
        throw caught;
      }
      throw new HttpsError(
        "internal",
        "Fare quote could not be verified.",
        {
          reason:
            "fare_quote_callable_view_invalid",
        },
      );
    }
  };

export const createPassengerFareQuoteCallableV1 =
  (
    runtimeDependencies:
      FareQuoteRuntimeDependenciesV1,
  ): FareQuoteCallableHandlerV1 => {
    const computeQuote =
      createFareQuoteRuntimeProviderV1(
        runtimeDependencies,
      );

    const executionDependencies:
      FareQuoteCallableExecutionDependenciesV1 = {
        createQuoteForPassenger:
          (
            passengerId,
            rawInput,
          ) =>
            createFareQuoteForPassengerV1(
              {
                firestore:
                  runtimeDependencies.firestore,
                computeQuote,
              },
              passengerId,
              rawInput,
            ),
        readPassengerView:
          (
            passengerId,
            quoteId,
          ) =>
            readPassengerFareQuoteViewV1(
              runtimeDependencies.firestore,
              passengerId,
              quoteId,
            ),
      };

    return (
      passengerId,
      rawInput,
    ) =>
      executePassengerFareQuoteCallableV1(
        executionDependencies,
        passengerId,
        rawInput,
      );
  };
