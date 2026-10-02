import assert from "node:assert/strict";
import test from "node:test";
import {
  HttpsError,
} from "firebase-functions/v2/https";
import {
  createPassengerFareQuoteCallableV1,
  executePassengerFareQuoteCallableV1,
} from "./ride-fare-quote-callable-authority-v1.js";
import type {
  FareQuoteCallableExecutionDependenciesV1,
} from "./ride-fare-quote-callable-authority-v1.js";
import type {
  PassengerFareQuoteViewV1,
} from "./ride-fare-quote-passenger-view-v1.js";
import type {
  FareQuoteRuntimeDependenciesV1,
} from "./ride-fare-quote-runtime-v1.js";

const passengerId = "passenger-1";
const quoteId = "a".repeat(64);

const input = {
  requestId:
    "request_1234567890",
  pickup: {
    latitude: 39.9208,
    longitude: 32.8541,
    addressLabel: "Pickup",
  },
  dropoff: {
    latitude: 39.9308,
    longitude: 32.8641,
    addressLabel: "Dropoff",
  },
};

const view = (
  overrides:
    Partial<PassengerFareQuoteViewV1> = {},
): PassengerFareQuoteViewV1 => ({
  quoteId,
  pricingVersion: "fare-v1",
  currency: "TRY",
  plannedDistanceMeters: 10000,
  plannedDurationSeconds: 1200,
  referenceEstimatedFareMinor: 50000,
  yoldaalFareMinor: 20000,
  savingMinor: 30000,
  quotedAtMillis: 1000,
  ...overrides,
});

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
  "successful callable flow creates then reads exact passenger view",
  async () => {
    const calls: unknown[] = [];
    const expectedView = view();

    const dependencies:
      FareQuoteCallableExecutionDependenciesV1 = {
        async createQuoteForPassenger(
          actor,
          rawInput,
        ) {
          calls.push({
            kind: "create",
            actor,
            rawInput,
          });
          return {quoteId};
        },
        async readPassengerView(
          actor,
          resolvedQuoteId,
        ) {
          calls.push({
            kind: "read",
            actor,
            resolvedQuoteId,
          });
          return expectedView;
        },
      };

    const result =
      await executePassengerFareQuoteCallableV1(
        dependencies,
        passengerId,
        input,
      );

    assert.equal(result, expectedView);
    assert.deepEqual(
      calls,
      [
        {
          kind: "create",
          actor: passengerId,
          rawInput: input,
        },
        {
          kind: "read",
          actor: passengerId,
          resolvedQuoteId: quoteId,
        },
      ],
    );
  },
);

test(
  "passenger id is server-side input and invalid identity fails before create",
  async () => {
    let createCalls = 0;

    const dependencies:
      FareQuoteCallableExecutionDependenciesV1 = {
        async createQuoteForPassenger() {
          createCalls += 1;
          return {quoteId};
        },
        async readPassengerView() {
          return view();
        },
      };

    await expectHttpsError(
      () =>
        executePassengerFareQuoteCallableV1(
          dependencies,
          "",
          input,
        ),
      "unauthenticated",
      "fare_quote_auth_invalid",
    );

    assert.equal(createCalls, 0);
  },
);

test(
  "callable result must be exact quoteId-only object",
  async () => {
    let readCalls = 0;

    const dependencies:
      FareQuoteCallableExecutionDependenciesV1 = {
        async createQuoteForPassenger() {
          return {
            quoteId,
            passengerId,
          };
        },
        async readPassengerView() {
          readCalls += 1;
          return view();
        },
      };

    await expectHttpsError(
      () =>
        executePassengerFareQuoteCallableV1(
          dependencies,
          passengerId,
          input,
        ),
      "internal",
      "fare_quote_callable_result_invalid",
    );

    assert.equal(readCalls, 0);
  },
);

test(
  "malformed quote id fails before passenger view read",
  async () => {
    let readCalls = 0;

    const dependencies:
      FareQuoteCallableExecutionDependenciesV1 = {
        async createQuoteForPassenger() {
          return {
            quoteId: "not-a-quote-id",
          };
        },
        async readPassengerView() {
          readCalls += 1;
          return view();
        },
      };

    await expectHttpsError(
      () =>
        executePassengerFareQuoteCallableV1(
          dependencies,
          passengerId,
          input,
        ),
      "internal",
      "fare_quote_callable_result_invalid",
    );

    assert.equal(readCalls, 0);
  },
);

test(
  "HttpsError from quote creation is preserved",
  async () => {
    const expected =
      new HttpsError(
        "invalid-argument",
        "invalid",
        {reason: "invalid_create_ride_payload"},
      );

    const dependencies:
      FareQuoteCallableExecutionDependenciesV1 = {
        async createQuoteForPassenger() {
          throw expected;
        },
        async readPassengerView() {
          return view();
        },
      };

    await assert.rejects(
      () =>
        executePassengerFareQuoteCallableV1(
          dependencies,
          passengerId,
          input,
        ),
      (caught: unknown) =>
        caught === expected,
    );
  },
);

test(
  "unknown quote creation failure is sanitized",
  async () => {
    const dependencies:
      FareQuoteCallableExecutionDependenciesV1 = {
        async createQuoteForPassenger() {
          throw new Error(
            "private create detail",
          );
        },
        async readPassengerView() {
          return view();
        },
      };

    await expectHttpsError(
      () =>
        executePassengerFareQuoteCallableV1(
          dependencies,
          passengerId,
          input,
        ),
      "unavailable",
      "fare_quote_callable_create_unavailable",
    );
  },
);

test(
  "HttpsError from passenger view is preserved",
  async () => {
    const expected =
      new HttpsError(
        "failed-precondition",
        "invalid",
        {
          reason:
            "fare_quote_storage_inconsistent",
        },
      );

    const dependencies:
      FareQuoteCallableExecutionDependenciesV1 = {
        async createQuoteForPassenger() {
          return {quoteId};
        },
        async readPassengerView() {
          throw expected;
        },
      };

    await assert.rejects(
      () =>
        executePassengerFareQuoteCallableV1(
          dependencies,
          passengerId,
          input,
        ),
      (caught: unknown) =>
        caught === expected,
    );
  },
);

test(
  "unknown passenger view failure is sanitized",
  async () => {
    const dependencies:
      FareQuoteCallableExecutionDependenciesV1 = {
        async createQuoteForPassenger() {
          return {quoteId};
        },
        async readPassengerView() {
          throw new Error(
            "private view detail",
          );
        },
      };

    await expectHttpsError(
      () =>
        executePassengerFareQuoteCallableV1(
          dependencies,
          passengerId,
          input,
        ),
      "internal",
      "fare_quote_callable_view_invalid",
    );
  },
);

test(
  "runtime factory composes provider orchestration and passenger projector",
  () => {
    const source =
      createPassengerFareQuoteCallableV1
        .toString();

    for (const required of [
      "createFareQuoteRuntimeProviderV1",
      "createFareQuoteForPassengerV1",
      "readPassengerFareQuoteViewV1",
      "executePassengerFareQuoteCallableV1",
    ]) {
      assert.equal(
        source.includes(required),
        true,
      );
    }
  },
);

test(
  "phase Y remains dormant without onCall secret mapping or UI authority",
  () => {
    const source = [
      createPassengerFareQuoteCallableV1
        .toString(),
      executePassengerFareQuoteCallableV1
        .toString(),
    ].join("\n");

    for (const forbidden of [
      "onCall",
      "defineSecret",
      "enforceAppCheck",
      "Ankara",
      "Cankaya",
      "UKOME",
      "quoteExpiry",
      "waitingFee",
      "tollFee",
      "parkingFee",
      "dropoffJurisdiction",
      "FirebaseFunctions",
    ]) {
      assert.equal(
        source.includes(forbidden),
        false,
      );
    }
  },
);

test(
  "runtime factory rejects blank injected geocoding key",
  () => {
    const runtimeDependencies:
      FareQuoteRuntimeDependenciesV1 = {
        firestore:
          {} as FareQuoteRuntimeDependenciesV1[
            "firestore"
          ],
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
      };

    assert.throws(
      () =>
        createPassengerFareQuoteCallableV1(
          runtimeDependencies,
        ),
      /google_geocoding_v4_api_key_invalid/u,
    );
  },
);
