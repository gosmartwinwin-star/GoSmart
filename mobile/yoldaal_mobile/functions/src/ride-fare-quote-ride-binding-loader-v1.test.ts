import assert from "node:assert/strict";
import test from "node:test";
import {
  Firestore,
  Transaction,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  createFirestoreFareQuoteReaderV1,
  createTransactionFareQuoteReaderV1,
  loadRideFareBindingV1,
} from "./ride-fare-quote-ride-binding-loader-v1.js";
import {
  buildPersistedFareQuoteV1,
  fareQuoteOperationIdV1,
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
  FarePolicyVersionV1,
} from "./ride-fare-policy-v1.js";
import {
  TariffVersionV1,
} from "./ride-tariff-v1.js";

const passengerId = "passenger-1";
const requestId =
  "quote_ride_loader_request_1234";
const quotedAtMillis = 1757000000000;

const tariff: TariffVersionV1 = {
  tariffVersionId: "ANK-2026-09",
  tariffZoneId: "TR-ANKARA-METRO",
  approvalStatus: "approved",
  active: true,
  currency: "TRY",
  authorityType: "ukome",
  authorityName:
    "Example Official Authority",
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

const input = () =>
  validateFareQuoteRequestV1({
    requestId,
    pickup: {
      latitude: 39.92077,
      longitude: 32.85411,
      addressLabel: "Pickup",
    },
    dropoff: {
      latitude: 39.95,
      longitude: 32.88,
      addressLabel: "Dropoff",
    },
  });

const persisted = (
  rideInput = input(),
) => {
  const quoteId =
    fareQuoteOperationIdV1(
      passengerId,
      rideInput.requestId,
    );

  return buildPersistedFareQuoteV1(
    passengerId,
    rideInput,
    buildFareQuoteSnapshotV1({
      quoteId,
      tariff,
      farePolicy: policy,
      plannedDistanceMeters: 18200,
      plannedDurationSeconds: 2400,
      quotedAtMillis,
    }),
  );
};

const reason = (
  expectedCode: string,
  expectedReason: string,
) =>
  (caught: unknown): boolean => {
    assert.ok(
      caught instanceof HttpsError,
    );
    assert.equal(
      caught.code,
      expectedCode,
    );
    assert.deepEqual(
      caught.details,
      {reason: expectedReason},
    );
    return true;
  };

test(
  "loader derives quote id before reader call",
  async () => {
    const rideInput = input();
    const quote = persisted(rideInput);
    const reads: string[] = [];

    const result =
      await loadRideFareBindingV1(
        {
          readQuote: async (
            quoteId,
          ) => {
            reads.push(quoteId);
            return quote;
          },
        },
        passengerId,
        rideInput,
      );

    assert.deepEqual(
      reads,
      [
        fareQuoteOperationIdV1(
          passengerId,
          requestId,
        ),
      ],
    );
    assert.deepEqual(
      result,
      {
        quoteId: reads[0],
        currency: "TRY",
        yoldaalFareMinor: 27480,
      },
    );
  },
);

test(
  "missing quote fails closed",
  async () => {
    await assert.rejects(
      () =>
        loadRideFareBindingV1(
          {
            readQuote:
              async () => null,
          },
          passengerId,
          input(),
        ),
      reason(
        "failed-precondition",
        "fare_quote_required",
      ),
    );
  },
);

test(
  "changed pickup fails binding",
  async () => {
    const original = input();
    const changed = {
      ...original,
      pickup: {
        ...original.pickup,
        latitude: 39.921,
      },
    };

    await assert.rejects(
      () =>
        loadRideFareBindingV1(
          {
            readQuote:
              async () =>
                persisted(original),
          },
          passengerId,
          changed,
        ),
      reason(
        "failed-precondition",
        "fare_quote_binding_mismatch",
      ),
    );
  },
);

test(
  "malformed stored quote is internal",
  async () => {
    await assert.rejects(
      () =>
        loadRideFareBindingV1(
          {
            readQuote:
              async () => ({
                quoteId: "bad",
              }),
          },
          passengerId,
          input(),
        ),
      reason(
        "internal",
        "fare_quote_storage_invalid",
      ),
    );
  },
);

test(
  "reader failure is unavailable",
  async () => {
    await assert.rejects(
      () =>
        loadRideFareBindingV1(
          {
            readQuote:
              async () => {
                throw new Error(
                  "raw firestore detail",
                );
              },
          },
          passengerId,
          input(),
        ),
      reason(
        "unavailable",
        "fare_quote_read_unavailable",
      ),
    );
  },
);

test(
  "invalid createRide input fails before read",
  async () => {
    let reads = 0;

    await assert.rejects(
      () =>
        loadRideFareBindingV1(
          {
            readQuote: async () => {
              reads += 1;
              return null;
            },
          },
          passengerId,
          {
            ...input(),
            quoteId: "client-authority",
          } as never,
        ),
      (caught: unknown) => {
        assert.ok(
          caught instanceof HttpsError,
        );
        assert.equal(
          caught.code,
          "invalid-argument",
        );
        return true;
      },
    );

    assert.equal(reads, 0);
  },
);

test(
  "firestore reader uses exact fareQuotes document",
  async () => {
    const accesses: string[] = [];
    const quote = persisted();

    const firestore = {
      collection(name: string) {
        accesses.push(
          `collection:${name}`,
        );
        return {
          doc(id: string) {
            accesses.push(
              `doc:${id}`,
            );
            return {
              async get() {
                accesses.push("get");
                return {
                  exists: true,
                  data: () => quote,
                };
              },
            };
          },
        };
      },
    } as unknown as Firestore;

    const quoteId =
      fareQuoteOperationIdV1(
        passengerId,
        requestId,
      );
    const reader =
      createFirestoreFareQuoteReaderV1(
        firestore,
      );

    assert.deepEqual(
      await reader(quoteId),
      quote,
    );
    assert.deepEqual(
      accesses,
      [
        "collection:fareQuotes",
        `doc:${quoteId}`,
        "get",
      ],
    );
  },
);

test(
  "transaction reader uses transaction get",
  async () => {
    const accesses: string[] = [];
    const quote = persisted();

    const firestore = {
      collection(name: string) {
        accesses.push(
          `collection:${name}`,
        );
        return {
          doc(id: string) {
            accesses.push(
              `doc:${id}`,
            );
            return {id};
          },
        };
      },
    } as unknown as Firestore;

    const transaction = {
      async get(
        ref: {id: string},
      ) {
        accesses.push(
          `transaction.get:${ref.id}`,
        );
        return {
          exists: true,
          data: () => quote,
        };
      },
    } as unknown as Transaction;

    const quoteId =
      fareQuoteOperationIdV1(
        passengerId,
        requestId,
      );
    const reader =
      createTransactionFareQuoteReaderV1(
        firestore,
        transaction,
      );

    assert.deepEqual(
      await reader(quoteId),
      quote,
    );
    assert.deepEqual(
      accesses,
      [
        "collection:fareQuotes",
        `doc:${quoteId}`,
        `transaction.get:${quoteId}`,
      ],
    );
  },
);

test(
  "document readers return null only when missing",
  async () => {
    const firestore = {
      collection() {
        return {
          doc() {
            return {
              async get() {
                return {
                  exists: false,
                  data: () => {
                    throw new Error(
                      "must not read data",
                    );
                  },
                };
              },
            };
          },
        };
      },
    } as unknown as Firestore;

    const reader =
      createFirestoreFareQuoteReaderV1(
        firestore,
      );
    assert.equal(
      await reader("a".repeat(64)),
      null,
    );
  },
);

test(
  "loader carries no expiry or consumption authority",
  async () => {
    const rideInput = input();
    const result =
      await loadRideFareBindingV1(
        {
          readQuote:
            async () =>
              persisted(rideInput),
        },
        passengerId,
        rideInput,
      );

    for (const key of [
      "expiresAtMillis",
      "consumedAtMillis",
      "rideId",
      "referenceEstimatedFareMinor",
      "savingMinor",
    ]) {
      assert.equal(
        key in result,
        false,
      );
    }
  },
);
