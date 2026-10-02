import assert from "node:assert/strict";
import test from "node:test";
import type {
  Firestore,
} from "firebase-admin/firestore";
import {
  HttpsError,
} from "firebase-functions/v2/https";
import {
  createFareQuoteRuntimeProviderV1,
  readPassengerFareQuoteViewV1,
} from "./ride-fare-quote-runtime-v1.js";

const quoteId = "a".repeat(64);
const requestDigest = "b".repeat(64);
const passengerId = "passenger-1";

const canonicalQuote = (
  overrides: Record<string, unknown> = {},
): Record<string, unknown> => ({
  quoteId,
  pricingVersion: "fare-v1",
  tariffZoneId: "TR-TEST-ZONE",
  tariffVersionId: "TARIFF-V1",
  farePolicyVersionId:
    "FARE-V1-40PCT-2026-09",
  currency: "TRY",
  authorityType: "test-authority",
  authorityName: "Test Authority",
  sourceUrl:
    "https://example.invalid/tariff",
  decisionReference: "TEST-DECISION",
  tariffPublishedAtMillis: 1000,
  tariffEffectiveFromMillis: 1000,
  tariffEffectiveUntilMillis: null,
  tariffVerifiedAtMillis: 1200,
  openingFeeMinor: 5000,
  distanceRateMinorPerKm: 3500,
  minimumFareMinor: 15000,
  plannedDistanceMeters: 18200,
  plannedDurationSeconds: 2400,
  referenceEstimatedFareMinor: 68700,
  passengerFareBasisPoints: 4000,
  yoldaalFareMinor: 27480,
  savingMinor: 41220,
  quotedAtMillis: 1500,
  passengerId,
  requestDigest,
  ...overrides,
});

const fakeFirestore = (
  options: {
    exists?: boolean;
    data?: Record<string, unknown>;
    rejectRead?: boolean;
  } = {},
) => {
  const calls: unknown[] = [];

  const firestore = {
    collection(name: string) {
      calls.push({
        kind: "collection",
        name,
      });
      return {
        doc(id: string) {
          calls.push({
            kind: "doc",
            id,
          });
          return {
            async get() {
              calls.push({kind: "get"});
              if (options.rejectRead) {
                throw new Error(
                  "private firestore detail",
                );
              }
              return {
                exists:
                  options.exists ?? true,
                data: () =>
                  options.data ??
                  canonicalQuote(),
              };
            },
          };
        },
      };
    },
  };

  return {
    firestore:
      firestore as unknown as Firestore,
    calls,
  };
};

const expectHttpsError = async (
  action: () => Promise<unknown>,
  code: string,
  reason: string,
): Promise<void> => {
  await assert.rejects(
    action,
    (caught: unknown) => {
      assert.ok(
        caught instanceof HttpsError,
      );
      assert.equal(caught.code, code);
      assert.deepEqual(
        caught.details,
        {reason},
      );
      return true;
    },
  );
};

test(
  "runtime provider validates Google key before runtime use",
  () => {
    const fake = fakeFirestore();
    assert.throws(
      () =>
        createFareQuoteRuntimeProviderV1({
          firestore: fake.firestore,
          googleGeocodingApiKey: " ",
          fetch: async () => {
            throw new Error(
              "must not run",
            );
          },
          computeRoute: async () => ({
            distanceMeters: 1,
            durationSeconds: 1,
          }),
        }),
      /google_geocoding_v4_api_key_invalid/u,
    );
    assert.equal(
      fake.calls.length,
      0,
    );
  },
);

test(
  "runtime provider composes zone policy geocoding and quote provider",
  () => {
    const source =
      createFareQuoteRuntimeProviderV1
        .toString();

    for (const required of [
      "createFirestoreTariffZonePolicyResolverV1",
      "createTariffZoneRuntimeResolverV1",
      "createFareQuoteProviderV1",
    ]) {
      assert.equal(
        source.includes(required),
        true,
      );
    }
  },
);

test(
  "passenger view reads exact fareQuotes document",
  async () => {
    const fake = fakeFirestore();

    const view =
      await readPassengerFareQuoteViewV1(
        fake.firestore,
        passengerId,
        quoteId,
      );

    assert.deepEqual(
      fake.calls,
      [
        {
          kind: "collection",
          name: "fareQuotes",
        },
        {
          kind: "doc",
          id: quoteId,
        },
        {kind: "get"},
      ],
    );
    assert.equal(
      view.quoteId,
      quoteId,
    );
    assert.equal(
      view.yoldaalFareMinor,
      27480,
    );
  },
);

test(
  "passenger response is exact privacy-minimal DTO",
  async () => {
    const fake = fakeFirestore();

    const view =
      await readPassengerFareQuoteViewV1(
        fake.firestore,
        passengerId,
        quoteId,
      );

    assert.deepEqual(
      Object.keys(view).sort(),
      [
        "currency",
        "plannedDistanceMeters",
        "plannedDurationSeconds",
        "pricingVersion",
        "quoteId",
        "quotedAtMillis",
        "referenceEstimatedFareMinor",
        "savingMinor",
        "yoldaalFareMinor",
      ].sort(),
    );

    for (const forbidden of [
      "passengerId",
      "requestDigest",
      "tariffZoneId",
      "tariffVersionId",
      "farePolicyVersionId",
      "authorityName",
      "sourceUrl",
      "decisionReference",
    ]) {
      assert.equal(
        Object.prototype.hasOwnProperty.call(
          view,
          forbidden,
        ),
        false,
      );
    }
  },
);

test(
  "missing quote fails closed as storage inconsistency",
  async () => {
    const fake =
      fakeFirestore({exists: false});

    await expectHttpsError(
      () =>
        readPassengerFareQuoteViewV1(
          fake.firestore,
          passengerId,
          quoteId,
        ),
      "failed-precondition",
      "fare_quote_storage_inconsistent",
    );
  },
);

test(
  "Firestore read failure is sanitized",
  async () => {
    const fake =
      fakeFirestore({rejectRead: true});

    await expectHttpsError(
      () =>
        readPassengerFareQuoteViewV1(
          fake.firestore,
          passengerId,
          quoteId,
        ),
      "unavailable",
      "fare_quote_view_read_unavailable",
    );
  },
);

test(
  "foreign passenger and tampered quote are sanitized",
  async () => {
    const foreign =
      fakeFirestore({
        data: canonicalQuote({
          passengerId: "other-passenger",
        }),
      });

    await expectHttpsError(
      () =>
        readPassengerFareQuoteViewV1(
          foreign.firestore,
          passengerId,
          quoteId,
        ),
      "internal",
      "fare_quote_view_invalid",
    );

    const tampered =
      fakeFirestore({
        data: canonicalQuote({
          yoldaalFareMinor: 27481,
        }),
      });

    await expectHttpsError(
      () =>
        readPassengerFareQuoteViewV1(
          tampered.firestore,
          passengerId,
          quoteId,
        ),
      "internal",
      "fare_quote_view_invalid",
    );
  },
);

test(
  "invalid quote id fails before Firestore read",
  async () => {
    const fake = fakeFirestore();

    await expectHttpsError(
      () =>
        readPassengerFareQuoteViewV1(
          fake.firestore,
          passengerId,
          "not-a-quote-id",
        ),
      "invalid-argument",
      "fare_quote_id_invalid",
    );

    assert.equal(
      fake.calls.length,
      0,
    );
  },
);

test(
  "invalid passenger id fails before Firestore read",
  async () => {
    const fake = fakeFirestore();

    await expectHttpsError(
      () =>
        readPassengerFareQuoteViewV1(
          fake.firestore,
          " ",
          quoteId,
        ),
      "invalid-argument",
      "fare_quote_passenger_id_invalid",
    );

    assert.equal(
      fake.calls.length,
      0,
    );
  },
);

test(
  "runtime composition adds no callable mapping expiry or fee authority",
  () => {
    const source = [
      createFareQuoteRuntimeProviderV1
        .toString(),
      readPassengerFareQuoteViewV1
        .toString(),
    ].join("\n");

    for (const forbidden of [
      "onCall",
      "defineSecret",
      "Ankara",
      "Cankaya",
      "UKOME",
      "quoteExpiry",
      "waitingFee",
      "tollFee",
      "parkingFee",
      "dropoffJurisdiction",
    ]) {
      assert.equal(
        source.includes(forbidden),
        false,
      );
    }
  },
);
