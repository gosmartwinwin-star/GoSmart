import assert from "node:assert/strict";
import test from "node:test";
import {Firestore} from "firebase-admin/firestore";
import {
  createFareQuoteProviderV1,
} from "./ride-fare-quote-provider-v1.js";
import {
  validateFareQuoteRequestV1,
} from "./ride-fare-quote-persistence-v1.js";
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

type QueryLog = {
  collection: string;
  field: string;
  operator: string;
  value: unknown;
  limit: number;
};

type FakeDoc = {
  id: string;
  data: () => Record<string, unknown>;
};

const quoteAtMillis = 1757000000000;
const quoteId = "server_quote_1234567890";

const request = () =>
  validateFareQuoteRequestV1({
    requestId: "quote_request_1234567890",
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

const tariff = (
  id = "ANK-2026-09",
): TariffVersionV1 => ({
  tariffVersionId: id,
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
});

const policy = (
  id = "FARE-V1-40PCT-2026-09",
): FarePolicyVersionV1 => ({
  farePolicyVersionId: id,
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
});

const doc = (
  id: string,
  value: object,
): FakeDoc => ({
  id,
  data: () => ({
    ...value,
  }),
});

const fakeFirestore = (
  tariffVersions: TariffVersionV1[],
  policies: FarePolicyVersionV1[],
): {
  firestore: Firestore;
  queries: QueryLog[];
} => {
  const queries: QueryLog[] = [];

  const firestore = {
    collection(collectionName: string) {
      return {
        where(
          field: string,
          operator: string,
          value: unknown,
        ) {
          return {
            limit(limit: number) {
              return {
                async get() {
                  queries.push({
                    collection:
                      collectionName,
                    field,
                    operator,
                    value,
                    limit,
                  });

                  if (
                    collectionName ===
                    "fareTariffs"
                  ) {
                    return {
                      docs: tariffVersions
                        .filter(
                          (item) =>
                            item.tariffZoneId ===
                            value,
                        )
                        .map(
                          (item) =>
                            doc(
                              item.tariffVersionId,
                              item,
                            ),
                        ),
                    };
                  }

                  if (
                    collectionName ===
                    "farePolicies"
                  ) {
                    return {
                      docs: policies
                        .filter(
                          (item) =>
                            item.pricingVersion ===
                            value,
                        )
                        .map(
                          (item) =>
                            doc(
                              item.farePolicyVersionId,
                              item,
                            ),
                        ),
                    };
                  }

                  throw new Error(
                    "unexpected collection",
                  );
                },
              };
            },
          };
        },
      };
    },
  } as unknown as Firestore;

  return {firestore, queries};
};

test(
  "provider resolves zone only through trusted dependency",
  async () => {
    const fake = fakeFirestore(
      [tariff()],
      [policy()],
    );
    const input = request();
    const resolverCalls: Array<{
      input: typeof input;
      quoteAtMillis: number;
    }> = [];

    const provider =
      createFareQuoteProviderV1({
        firestore: fake.firestore,
        resolveTariffZone: async (
          received,
          receivedQuoteAt,
        ) => {
          resolverCalls.push({
            input: received,
            quoteAtMillis:
              receivedQuoteAt,
          });
          return "TR-ANKARA-METRO";
        },
        computeRoute: async () => ({
          distanceMeters: 18200,
          durationSeconds: 2400,
        }),
      });

    await provider(
      input,
      quoteId,
      quoteAtMillis,
    );

    assert.equal(
      resolverCalls.length,
      1,
    );
    assert.deepEqual(
      resolverCalls[0],
      {
        input,
        quoteAtMillis,
      },
    );
  },
);

test(
  "provider uses approved tariff and policy repositories",
  async () => {
    const fake = fakeFirestore(
      [tariff()],
      [policy()],
    );

    const provider =
      createFareQuoteProviderV1({
        firestore: fake.firestore,
        resolveTariffZone:
          async () =>
            "TR-ANKARA-METRO",
        computeRoute: async () => ({
          distanceMeters: 18200,
          durationSeconds: 2400,
        }),
      });

    await provider(
      request(),
      quoteId,
      quoteAtMillis,
    );

    assert.deepEqual(
      fake.queries,
      [
        {
          collection: "fareTariffs",
          field: "tariffZoneId",
          operator: "==",
          value: "TR-ANKARA-METRO",
          limit: 101,
        },
        {
          collection: "farePolicies",
          field: "pricingVersion",
          operator: "==",
          value: PRICING_FARE_V1,
          limit: 101,
        },
      ],
    );
  },
);

test(
  "provider builds frozen fare snapshot from server route",
  async () => {
    const fake = fakeFirestore(
      [tariff()],
      [policy()],
    );
    const input = request();
    const routeCalls: unknown[] = [];

    const provider =
      createFareQuoteProviderV1({
        firestore: fake.firestore,
        resolveTariffZone:
          async () =>
            "TR-ANKARA-METRO",
        computeRoute: async (
          pickup,
          dropoff,
        ) => {
          routeCalls.push({
            pickup,
            dropoff,
          });
          return {
            distanceMeters: 18200,
            durationSeconds: 2400,
          };
        },
      });

    const result = await provider(
      input,
      quoteId,
      quoteAtMillis,
    );

    assert.deepEqual(
      routeCalls,
      [{
        pickup: input.pickup,
        dropoff: input.dropoff,
      }],
    );
    assert.equal(
      result.quoteId,
      quoteId,
    );
    assert.equal(
      result.tariffZoneId,
      "TR-ANKARA-METRO",
    );
    assert.equal(
      result.referenceEstimatedFareMinor,
      68700,
    );
    assert.equal(
      result.yoldaalFareMinor,
      27480,
    );
    assert.equal(
      result.savingMinor,
      41220,
    );
    assert.equal(
      result.plannedDistanceMeters,
      18200,
    );
    assert.equal(
      result.plannedDurationSeconds,
      2400,
    );
  },
);

test(
  "route duration cannot alter monetary result",
  async () => {
    const makeProvider = (
      durationSeconds: number,
    ) => {
      const fake = fakeFirestore(
        [tariff()],
        [policy()],
      );
      return createFareQuoteProviderV1({
        firestore: fake.firestore,
        resolveTariffZone:
          async () =>
            "TR-ANKARA-METRO",
        computeRoute: async () => ({
          distanceMeters: 18200,
          durationSeconds,
        }),
      });
    };

    const first = await makeProvider(1)(
      request(),
      quoteId,
      quoteAtMillis,
    );
    const second =
      await makeProvider(99999)(
        request(),
        quoteId,
        quoteAtMillis,
      );

    assert.equal(
      first.yoldaalFareMinor,
      second.yoldaalFareMinor,
    );
    assert.equal(
      first.referenceEstimatedFareMinor,
      second.referenceEstimatedFareMinor,
    );
  },
);

test(
  "missing approved tariff fails closed",
  async () => {
    const fake = fakeFirestore(
      [],
      [policy()],
    );
    const provider =
      createFareQuoteProviderV1({
        firestore: fake.firestore,
        resolveTariffZone:
          async () =>
            "TR-ANKARA-METRO",
        computeRoute: async () => ({
          distanceMeters: 18200,
          durationSeconds: 2400,
        }),
      });

    await assert.rejects(
      () => provider(
        request(),
        quoteId,
        quoteAtMillis,
      ),
      RangeError,
    );
  },
);

test(
  "overlapping approved tariffs fail closed",
  async () => {
    const fake = fakeFirestore(
      [
        tariff("ANK-2026-09-A"),
        tariff("ANK-2026-09-B"),
      ],
      [policy()],
    );
    const provider =
      createFareQuoteProviderV1({
        firestore: fake.firestore,
        resolveTariffZone:
          async () =>
            "TR-ANKARA-METRO",
        computeRoute: async () => ({
          distanceMeters: 18200,
          durationSeconds: 2400,
        }),
      });

    await assert.rejects(
      () => provider(
        request(),
        quoteId,
        quoteAtMillis,
      ),
      RangeError,
    );
  },
);

test(
  "missing approved fare policy fails closed",
  async () => {
    const fake = fakeFirestore(
      [tariff()],
      [],
    );
    const provider =
      createFareQuoteProviderV1({
        firestore: fake.firestore,
        resolveTariffZone:
          async () =>
            "TR-ANKARA-METRO",
        computeRoute: async () => ({
          distanceMeters: 18200,
          durationSeconds: 2400,
        }),
      });

    await assert.rejects(
      () => provider(
        request(),
        quoteId,
        quoteAtMillis,
      ),
      RangeError,
    );
  },
);

test(
  "overlapping approved policies fail closed",
  async () => {
    const fake = fakeFirestore(
      [tariff()],
      [
        policy("FARE-A"),
        policy("FARE-B"),
      ],
    );
    const provider =
      createFareQuoteProviderV1({
        firestore: fake.firestore,
        resolveTariffZone:
          async () =>
            "TR-ANKARA-METRO",
        computeRoute: async () => ({
          distanceMeters: 18200,
          durationSeconds: 2400,
        }),
      });

    await assert.rejects(
      () => provider(
        request(),
        quoteId,
        quoteAtMillis,
      ),
      RangeError,
    );
  },
);

test(
  "provider carries no client zone or monetary authority",
  async () => {
    const input =
      request() as Record<
        string,
        unknown
      >;

    for (const key of [
      "tariffZoneId",
      "tariffVersionId",
      "farePolicyVersionId",
      "referenceEstimatedFareMinor",
      "yoldaalFareMinor",
      "savingMinor",
      "passengerFareBasisPoints",
    ]) {
      assert.equal(
        key in input,
        false,
      );
    }
  },
);

test(
  "provider invents no quote expiry or fee inputs",
  async () => {
    const fake = fakeFirestore(
      [tariff()],
      [policy()],
    );
    const provider =
      createFareQuoteProviderV1({
        firestore: fake.firestore,
        resolveTariffZone:
          async () =>
            "TR-ANKARA-METRO",
        computeRoute: async () => ({
          distanceMeters: 18200,
          durationSeconds: 2400,
        }),
      });

    const result = await provider(
      request(),
      quoteId,
      quoteAtMillis,
    );

    for (const key of [
      "expiresAtMillis",
      "waitingFareMinor",
      "tollFareMinor",
      "parkingFareMinor",
    ]) {
      assert.equal(
        key in result,
        false,
      );
    }
  },
);
