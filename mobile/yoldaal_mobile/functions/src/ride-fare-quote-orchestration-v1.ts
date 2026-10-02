import {
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  FareQuoteSnapshotV1,
} from "./ride-fare-quote-v1.js";
import {
  buildPersistedFareQuoteV1,
  CREATE_FARE_QUOTE_CALLABLE_NAME,
  fareQuoteOperationIdV1,
  FareQuoteRequestV1,
  fareQuoteRequestDigestV1,
  replayFareQuoteOperationV1,
  validateFareQuoteRequestV1,
} from "./ride-fare-quote-persistence-v1.js";

export const FARE_QUOTES_COLLECTION = "fareQuotes" as const;

export type FareQuoteProviderV1 = (
  input: FareQuoteRequestV1,
  quoteId: string,
  quotedAtMillis: number,
) => Promise<FareQuoteSnapshotV1>;

export type FareQuoteOrchestrationDependenciesV1 = {
  firestore: Firestore;
  computeQuote: FareQuoteProviderV1;
  now?: () => Timestamp;
};

const error = (
  code: "aborted" |
    "failed-precondition" |
    "internal" |
    "unavailable",
  reason: string,
): HttpsError =>
  new HttpsError(
    code,
    "Fiyat teklifi islemi tamamlanamadi.",
    {reason},
  );

const replayOperation = (
  raw: unknown,
  digest: string,
): Record<string, unknown> => {
  try {
    return replayFareQuoteOperationV1(
      raw,
      digest,
    );
  } catch (caught: unknown) {
    if (caught instanceof RangeError) {
      if (
        caught.message ===
        "idempotency_payload_mismatch"
      ) {
        throw error(
          "failed-precondition",
          "idempotency_payload_mismatch",
        );
      }
      if (
        caught.message ===
        "fare_quote_operation_in_progress"
      ) {
        throw error(
          "aborted",
          "fare_quote_operation_in_progress",
        );
      }
    }
    throw error(
      "internal",
      "fare_quote_operation_invalid",
    );
  }
};

const requireReplayStorage = (
  result: Record<string, unknown>,
  quoteExists: boolean,
  rawQuote: Record<string, unknown> | undefined,
  passengerId: string,
  digest: string,
  quoteId: string,
): void => {
  if (
    result.quoteId !== quoteId ||
    !quoteExists ||
    rawQuote === undefined ||
    rawQuote.quoteId !== quoteId ||
    rawQuote.passengerId !== passengerId ||
    rawQuote.requestDigest !== digest
  ) {
    throw error(
      "failed-precondition",
      "fare_quote_storage_inconsistent",
    );
  }
};

export const createFareQuoteForPassengerV1 = async (
  dependencies: FareQuoteOrchestrationDependenciesV1,
  passengerId: string,
  rawInput: unknown,
): Promise<Record<string, unknown>> => {
  const input =
    validateFareQuoteRequestV1(rawInput);
  const {firestore} = dependencies;
  const quoteId = fareQuoteOperationIdV1(
    passengerId,
    input.requestId,
  );
  const digest =
    fareQuoteRequestDigestV1(input);
  const operationRef = firestore
    .collection("rideOperations")
    .doc(quoteId);
  const quoteRef = firestore
    .collection(FARE_QUOTES_COLLECTION)
    .doc(quoteId);

  let existingOperation;
  let existingQuote;
  try {
    [existingOperation, existingQuote] =
      await Promise.all([
        operationRef.get(),
        quoteRef.get(),
      ]);
  } catch (_caught: unknown) {
    throw error(
      "unavailable",
      "fare_quote_persistence_unavailable",
    );
  }

  if (existingOperation.exists) {
    const result = replayOperation(
      existingOperation.data() ?? {},
      digest,
    );
    requireReplayStorage(
      result,
      existingQuote.exists,
      existingQuote.data(),
      passengerId,
      digest,
      quoteId,
    );
    return result;
  }

  if (existingQuote.exists) {
    throw error(
      "failed-precondition",
      "fare_quote_storage_inconsistent",
    );
  }

  const now =
    dependencies.now?.() ?? Timestamp.now();
  const quotedAtMillis = now.toMillis();

  let quote: FareQuoteSnapshotV1;
  try {
    quote = await dependencies.computeQuote(
      input,
      quoteId,
      quotedAtMillis,
    );
  } catch (caught: unknown) {
    if (caught instanceof HttpsError) {
      throw caught;
    }
    throw error(
      "unavailable",
      "fare_quote_computation_failed",
    );
  }

  if (
    quote.quoteId !== quoteId ||
    quote.quotedAtMillis !== quotedAtMillis
  ) {
    throw error(
      "internal",
      "fare_quote_provider_contract_invalid",
    );
  }

  const persisted = buildPersistedFareQuoteV1(
    passengerId,
    input,
    quote,
  );
  const result = {quoteId};

  try {
    return await firestore.runTransaction(
      async (transaction) => {
        const [operation, storedQuote] =
          await Promise.all([
            transaction.get(operationRef),
            transaction.get(quoteRef),
          ]);

        if (operation.exists) {
          const replay = replayOperation(
            operation.data() ?? {},
            digest,
          );
          requireReplayStorage(
            replay,
            storedQuote.exists,
            storedQuote.data(),
            passengerId,
            digest,
            quoteId,
          );
          return replay;
        }

        if (storedQuote.exists) {
          throw error(
            "failed-precondition",
            "fare_quote_storage_inconsistent",
          );
        }

        transaction.create(
          quoteRef,
          persisted,
        );
        transaction.create(
          operationRef,
          {
            actorUid: passengerId,
            callableName:
              CREATE_FARE_QUOTE_CALLABLE_NAME,
            requestDigest: digest,
            status: "completed",
            result,
            createdAt: now,
            updatedAt: now,
          },
        );
        return result;
      },
    );
  } catch (caught: unknown) {
    if (caught instanceof HttpsError) {
      throw caught;
    }
    throw error(
      "unavailable",
      "fare_quote_persistence_failed",
    );
  }
};
