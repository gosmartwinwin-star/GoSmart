import {
  Firestore,
  Transaction,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  CreateRideRequestInput,
} from "./ride-lifecycle-helpers.js";
import {
  FARE_QUOTES_COLLECTION,
} from "./ride-fare-quote-orchestration-v1.js";
import {
  fareQuoteOperationIdV1,
  validateFareQuoteRequestV1,
} from "./ride-fare-quote-persistence-v1.js";
import {
  bindFareQuoteToCreateRideV1,
  RideFareBindingV1,
} from "./ride-fare-quote-ride-binding-v1.js";

export type FareQuoteDocumentReaderV1 = (
  quoteId: string,
) => Promise<unknown | null>;

export type RideFareBindingLoaderDependenciesV1 = {
  readQuote: FareQuoteDocumentReaderV1;
};

const error = (
  code:
    | "failed-precondition"
    | "internal"
    | "unavailable",
  reason: string,
): HttpsError =>
  new HttpsError(
    code,
    "Fiyat teklifi yolculuga baglanamadi.",
    {reason},
  );

export const createFirestoreFareQuoteReaderV1 = (
  firestore: Firestore,
): FareQuoteDocumentReaderV1 =>
  async (quoteId) => {
    const snapshot = await firestore
      .collection(FARE_QUOTES_COLLECTION)
      .doc(quoteId)
      .get();

    if (!snapshot.exists) {
      return null;
    }
    return snapshot.data();
  };

export const createTransactionFareQuoteReaderV1 = (
  firestore: Firestore,
  transaction: Transaction,
): FareQuoteDocumentReaderV1 =>
  async (quoteId) => {
    const snapshot = await transaction.get(
      firestore
        .collection(FARE_QUOTES_COLLECTION)
        .doc(quoteId),
    );

    if (!snapshot.exists) {
      return null;
    }
    return snapshot.data();
  };

export const loadRideFareBindingV1 = async (
  dependencies:
    RideFareBindingLoaderDependenciesV1,
  passengerId: string,
  rawInput: CreateRideRequestInput,
): Promise<RideFareBindingV1> => {
  const input =
    validateFareQuoteRequestV1(rawInput);

  let expectedQuoteId: string;
  try {
    expectedQuoteId =
      fareQuoteOperationIdV1(
        passengerId,
        input.requestId,
      );
  } catch (_caught: unknown) {
    throw error(
      "internal",
      "fare_quote_binding_identity_invalid",
    );
  }

  let rawQuote: unknown | null;
  try {
    rawQuote =
      await dependencies.readQuote(
        expectedQuoteId,
      );
  } catch (_caught: unknown) {
    throw error(
      "unavailable",
      "fare_quote_read_unavailable",
    );
  }

  if (rawQuote === null) {
    throw error(
      "failed-precondition",
      "fare_quote_required",
    );
  }

  try {
    return bindFareQuoteToCreateRideV1(
      passengerId,
      input,
      rawQuote,
    );
  } catch (caught: unknown) {
    if (
      caught instanceof RangeError &&
      caught.message ===
        "fare_quote_request_binding_mismatch"
    ) {
      throw error(
        "failed-precondition",
        "fare_quote_binding_mismatch",
      );
    }

    throw error(
      "internal",
      "fare_quote_storage_invalid",
    );
  }
};
