import assert from "node:assert/strict";
import test from "node:test";
import {
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  FarePolicyVersionV1,
} from "./ride-fare-policy-v1.js";
import {
  FARE_QUOTES_COLLECTION,
  createFareQuoteForPassengerV1,
} from "./ride-fare-quote-orchestration-v1.js";
import {
  buildPersistedFareQuoteV1,
  fareQuoteOperationIdV1,
  fareQuoteRequestDigestV1,
  validateFareQuoteRequestV1,
} from "./ride-fare-quote-persistence-v1.js";
import {
  buildFareQuoteSnapshotV1,
} from "./ride-fare-quote-v1.js";
import {
  PRICING_FARE_V1,
  YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS,
} from "./ride-pricing-fare-v1.js";
import {
  TariffVersionV1,
} from "./ride-tariff-v1.js";

type StoredRecord = Record<string, unknown>;

type FakeState = {
  docs: Map<string, StoredRecord>;
  transactionCount: number;
  createCount: number;
  beforeTransaction: (() => void) | null;
  failTransaction: boolean;
};

type FakeRef = {
  id: string;
  path: string;
  get: () => Promise<{
    exists: boolean;
    data: () => StoredRecord | undefined;
  }>;
};

const snapshot = (
  state: FakeState,
  path: string,
) => ({
  exists: state.docs.has(path),
  data: () => state.docs.get(path),
});

const fakeFirestore = (): {
  firestore: Firestore;
  state: FakeState;
} => {
  const state: FakeState = {
    docs: new Map<string, StoredRecord>(),
    transactionCount: 0,
    createCount: 0,
    beforeTransaction: null,
    failTransaction: false,
  };

  const makeRef = (
    collection: string,
    id: string,
  ): FakeRef => {
    const path = `${collection}/${id}`;
    return {
      id,
      path,
      get: async () => snapshot(state, path),
    };
  };

  const firestore = {
    collection(name: string) {
      return {
        doc(id: string) {
          return makeRef(name, id);
        },
      };
    },
    async runTransaction<T>(
      callback: (
        transaction: {
          get: (
            ref: FakeRef,
          ) => Promise<{
            exists: boolean;
            data: () =>
              StoredRecord | undefined;
          }>;
          create: (
            ref: FakeRef,
            data: StoredRecord,
          ) => void;
        },
      ) => Promise<T>,
    ): Promise<T> {
      state.transactionCount += 1;
      if (state.beforeTransaction !== null) {
        const hook = state.beforeTransaction;
        state.beforeTransaction = null;
        hook();
      }
      if (state.failTransaction) {
        throw new Error("transaction failure");
      }

      const staged: Array<{
        ref: FakeRef;
        data: StoredRecord;
      }> = [];

      const transaction = {
        get: async (ref: FakeRef) =>
          snapshot(state, ref.path),
        create: (
          ref: FakeRef,
          data: StoredRecord,
        ) => {
          if (
            state.docs.has(ref.path) ||
            staged.some(
              (entry) =>
                entry.ref.path === ref.path,
            )
          ) {
            throw new Error("already exists");
          }
          staged.push({ref, data});
        },
      };

      const value =
        await callback(transaction);
      for (const entry of staged) {
        state.docs.set(
          entry.ref.path,
          entry.data,
        );
        state.createCount += 1;
      }
      return value;
    },
  } as unknown as Firestore;

  return {firestore, state};
};

const requestId =
  "quote_request_1234567890";
const passengerId = "passenger-1";
const quotedAtMillis = 1757000000000;

const rawRequest = (
  latitude = 39.92077,
) => ({
  requestId,
  pickup: {
    latitude,
    longitude: 32.85411,
    addressLabel: "Pickup",
  },
  dropoff: {
    latitude: 39.95,
    longitude: 32.88,
    addressLabel: "Dropoff",
  },
});

const tariff: TariffVersionV1 = {
  tariffVersionId: "ANK-2026-09",
  tariffZoneId: "TR-ANKARA-METRO",
  approvalStatus: "approved",
  active: true,
  currency: "TRY",
  authorityType: "ukome",
  authorityName: "Example Official Authority",
  sourceUrl:
    "https://example.gov.tr/tariff.pdf",
  decisionReference: "EXAMPLE-2026-09",
  publishedAtMillis: 1756684800000,
  effectiveFromMillis: 1756684800000,
  effectiveUntilMillis: null,
  verifiedAtMillis: 1756688400000,
  approvedAtMillis: 1756689000000,
  openingFeeMinor: 5000,
  distanceRateMinorPerKm: 3500,
  minimumFareMinor: 15000,
};

const policy: FarePolicyVersionV1 = {
  farePolicyVersionId:
    "FARE-V1-40PCT-2026-09",
  approvalStatus: "approved",
  active: true,
  pricingVersion: PRICING_FARE_V1,
  currency: "TRY",
  passengerFareBasisPoints:
    YOLDAAL_FARE_MULTIPLIER_BASIS_POINTS,
  policyReference:
    "YOLDAAL-FARE-V1-40PCT",
  effectiveFromMillis: 1756684800000,
  effectiveUntilMillis: null,
  approvedAtMillis: 1756689000000,
};

const provider = (
  calls: {value: number},
) => async (
  _input: ReturnType<
    typeof validateFareQuoteRequestV1
  >,
  quoteId: string,
  quoteTime: number,
) => {
  calls.value += 1;
  return buildFareQuoteSnapshotV1({
    quoteId,
    tariff,
    farePolicy: policy,
    plannedDistanceMeters: 18200,
    plannedDurationSeconds: 2400,
    quotedAtMillis: quoteTime,
  });
};

const reasonOf = (
  caught: unknown,
): string | undefined => {
  if (!(caught instanceof HttpsError)) {
    return undefined;
  }
  if (
    typeof caught.details !== "object" ||
    caught.details === null ||
    !("reason" in caught.details)
  ) {
    return undefined;
  }
  return (
    caught.details as {reason?: string}
  ).reason;
};

const expectReason = async (
  action: () => Promise<unknown>,
  reason: string,
): Promise<void> => {
  await assert.rejects(
    action,
    (caught: unknown) =>
      reasonOf(caught) === reason,
  );
};

test(
  "quote orchestration creates quote and operation atomically",
  async () => {
    const {firestore, state} =
      fakeFirestore();
    const calls = {value: 0};

    const result =
      await createFareQuoteForPassengerV1(
        {
          firestore,
          computeQuote: provider(calls),
          now: () =>
            Timestamp.fromMillis(
              quotedAtMillis,
            ),
        },
        passengerId,
        rawRequest(),
      );

    const quoteId =
      fareQuoteOperationIdV1(
        passengerId,
        requestId,
      );
    const quote = state.docs.get(
      `${FARE_QUOTES_COLLECTION}/${quoteId}`,
    );
    const operation = state.docs.get(
      `rideOperations/${quoteId}`,
    );

    assert.deepEqual(
      result,
      {quoteId},
    );
    assert.equal(calls.value, 1);
    assert.equal(state.transactionCount, 1);
    assert.equal(state.createCount, 2);
    assert.equal(
      quote?.passengerId,
      passengerId,
    );
    assert.equal(
      quote?.yoldaalFareMinor,
      27480,
    );
    assert.equal(
      operation?.callableName,
      "createFareQuote",
    );
    assert.deepEqual(
      operation?.result,
      {quoteId},
    );
  },
);

test(
  "preflight replay skips provider and second transaction",
  async () => {
    const {firestore, state} =
      fakeFirestore();
    const calls = {value: 0};
    const dependencies = {
      firestore,
      computeQuote: provider(calls),
      now: () =>
        Timestamp.fromMillis(
          quotedAtMillis,
        ),
    };

    const first =
      await createFareQuoteForPassengerV1(
        dependencies,
        passengerId,
        rawRequest(),
      );
    const second =
      await createFareQuoteForPassengerV1(
        dependencies,
        passengerId,
        rawRequest(),
      );

    assert.deepEqual(second, first);
    assert.equal(calls.value, 1);
    assert.equal(state.transactionCount, 1);
  },
);

test(
  "same request id with changed payload fails before provider",
  async () => {
    const {firestore} = fakeFirestore();
    const calls = {value: 0};
    const dependencies = {
      firestore,
      computeQuote: provider(calls),
      now: () =>
        Timestamp.fromMillis(
          quotedAtMillis,
        ),
    };

    await createFareQuoteForPassengerV1(
      dependencies,
      passengerId,
      rawRequest(),
    );

    await expectReason(
      () => createFareQuoteForPassengerV1(
        dependencies,
        passengerId,
        rawRequest(39.921),
      ),
      "idempotency_payload_mismatch",
    );
    assert.equal(calls.value, 1);
  },
);

test(
  "transaction race replays concurrent winner",
  async () => {
    const {firestore, state} =
      fakeFirestore();
    const calls = {value: 0};
    const input =
      validateFareQuoteRequestV1(
        rawRequest(),
      );
    const quoteId =
      fareQuoteOperationIdV1(
        passengerId,
        requestId,
      );
    const digest =
      fareQuoteRequestDigestV1(input);
    const winningQuote =
      buildFareQuoteSnapshotV1({
        quoteId,
        tariff,
        farePolicy: policy,
        plannedDistanceMeters: 18200,
        plannedDurationSeconds: 2400,
        quotedAtMillis,
      });
    const persisted =
      buildPersistedFareQuoteV1(
        passengerId,
        input,
        winningQuote,
      );

    state.beforeTransaction = () => {
      state.docs.set(
        `${FARE_QUOTES_COLLECTION}/${quoteId}`,
        persisted,
      );
      state.docs.set(
        `rideOperations/${quoteId}`,
        {
          actorUid: passengerId,
          callableName: "createFareQuote",
          requestDigest: digest,
          status: "completed",
          result: {quoteId},
          createdAt:
            Timestamp.fromMillis(
              quotedAtMillis,
            ),
          updatedAt:
            Timestamp.fromMillis(
              quotedAtMillis,
            ),
        },
      );
    };

    const result =
      await createFareQuoteForPassengerV1(
        {
          firestore,
          computeQuote: provider(calls),
          now: () =>
            Timestamp.fromMillis(
              quotedAtMillis,
            ),
        },
        passengerId,
        rawRequest(),
      );

    assert.deepEqual(result, {quoteId});
    assert.equal(calls.value, 1);
    assert.equal(state.createCount, 0);
  },
);

test(
  "dangling quote without operation fails closed",
  async () => {
    const {firestore, state} =
      fakeFirestore();
    const quoteId =
      fareQuoteOperationIdV1(
        passengerId,
        requestId,
      );

    state.docs.set(
      `${FARE_QUOTES_COLLECTION}/${quoteId}`,
      {quoteId},
    );

    await expectReason(
      () => createFareQuoteForPassengerV1(
        {
          firestore,
          computeQuote: provider({value: 0}),
        },
        passengerId,
        rawRequest(),
      ),
      "fare_quote_storage_inconsistent",
    );
  },
);

test(
  "completed operation without quote fails closed",
  async () => {
    const {firestore, state} =
      fakeFirestore();
    const input =
      validateFareQuoteRequestV1(
        rawRequest(),
      );
    const quoteId =
      fareQuoteOperationIdV1(
        passengerId,
        requestId,
      );
    const digest =
      fareQuoteRequestDigestV1(input);

    state.docs.set(
      `rideOperations/${quoteId}`,
      {
        requestDigest: digest,
        status: "completed",
        result: {quoteId},
      },
    );

    await expectReason(
      () => createFareQuoteForPassengerV1(
        {
          firestore,
          computeQuote: provider({value: 0}),
        },
        passengerId,
        rawRequest(),
      ),
      "fare_quote_storage_inconsistent",
    );
  },
);

test(
  "provider must preserve server quote identity and time",
  async () => {
    const {firestore, state} =
      fakeFirestore();

    await expectReason(
      () => createFareQuoteForPassengerV1(
        {
          firestore,
          computeQuote: async (
            _input,
            _quoteId,
            quoteTime,
          ) =>
            buildFareQuoteSnapshotV1({
              quoteId: "wrong_quote_id",
              tariff,
              farePolicy: policy,
              plannedDistanceMeters: 18200,
              plannedDurationSeconds: 2400,
              quotedAtMillis: quoteTime,
            }),
          now: () =>
            Timestamp.fromMillis(
              quotedAtMillis,
            ),
        },
        passengerId,
        rawRequest(),
      ),
      "fare_quote_provider_contract_invalid",
    );

    assert.equal(state.transactionCount, 0);
  },
);

test(
  "unknown provider failure is sanitized",
  async () => {
    const {firestore} = fakeFirestore();

    await expectReason(
      () => createFareQuoteForPassengerV1(
        {
          firestore,
          computeQuote: async () => {
            throw new Error("secret detail");
          },
        },
        passengerId,
        rawRequest(),
      ),
      "fare_quote_computation_failed",
    );
  },
);

test(
  "transaction failure is sanitized and creates nothing",
  async () => {
    const {firestore, state} =
      fakeFirestore();
    state.failTransaction = true;

    await expectReason(
      () => createFareQuoteForPassengerV1(
        {
          firestore,
          computeQuote: provider({value: 0}),
          now: () =>
            Timestamp.fromMillis(
              quotedAtMillis,
            ),
        },
        passengerId,
        rawRequest(),
      ),
      "fare_quote_persistence_failed",
    );

    assert.equal(state.createCount, 0);
  },
);

test(
  "stored quote and operation contain no expiry authority",
  async () => {
    const {firestore, state} =
      fakeFirestore();
    await createFareQuoteForPassengerV1(
      {
        firestore,
        computeQuote: provider({value: 0}),
        now: () =>
          Timestamp.fromMillis(
            quotedAtMillis,
          ),
      },
      passengerId,
      rawRequest(),
    );

    const quoteId =
      fareQuoteOperationIdV1(
        passengerId,
        requestId,
      );
    const quote = state.docs.get(
      `${FARE_QUOTES_COLLECTION}/${quoteId}`,
    ) ?? {};
    const operation = state.docs.get(
      `rideOperations/${quoteId}`,
    ) ?? {};

    for (const key of [
      "expiresAtMillis",
      "quoteExpirySeconds",
      "consumedAtMillis",
    ]) {
      assert.equal(
        key in quote,
        false,
      );
      assert.equal(
        key in operation,
        false,
      );
    }
  },
);
