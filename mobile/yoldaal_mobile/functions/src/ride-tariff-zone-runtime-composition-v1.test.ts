import assert from "node:assert/strict";
import test from "node:test";
import type {
  FareQuoteRequestV1,
} from "./ride-fare-quote-persistence-v1.js";
import {
  GOOGLE_GEOCODING_V4_FIELD_MASK,
  GOOGLE_GEOCODING_V4_LOCATION_ENDPOINT,
} from "./ride-tariff-zone-google-geocoding-v4-v1.js";
import {
  createTariffZoneRuntimeResolverV1,
} from "./ride-tariff-zone-runtime-composition-v1.js";

const quoteAtMillis = 1757000000000;
const apiKey = "server-secret-api-key";

const request = (
  addressLabel = "Client label",
): FareQuoteRequestV1 => ({
  requestId:
    "shared_quote_ride_request_1234",
  pickup: {
    latitude: 39.92077,
    longitude: 32.85411,
    addressLabel,
  },
  dropoff: {
    latitude: 39.95,
    longitude: 32.88,
    addressLabel: "Dropoff",
  },
});

const googleBody = () => ({
  results: [{
    addressComponents: [
      {
        longText: "Ankara",
        shortText: "Ankara",
        types: [
          "administrative_area_level_1",
          "political",
        ],
        languageCode: "tr",
      },
      {
        longText: "Cankaya",
        shortText: "Cankaya",
        types: [
          "administrative_area_level_2",
          "political",
        ],
        languageCode: "tr",
      },
      {
        longText: "Turkiye",
        shortText: "TR",
        types: [
          "country",
          "political",
        ],
        languageCode: "tr",
      },
    ],
  }],
});

test(
  "composition returns zone from normalized Google-backed evidence",
  async () => {
    const resolver =
      createTariffZoneRuntimeResolverV1({
        googleGeocodingApiKey: apiKey,
        fetch: async () => ({
          ok: true,
          json: async () => googleBody(),
        }),
        resolveZoneFromEvidence:
          async () => "TR-TEST-ZONE",
      });

    assert.equal(
      await resolver(
        request(),
        quoteAtMillis,
      ),
      "TR-TEST-ZONE",
    );
  },
);

test(
  "Google transport receives pickup coordinates and narrow field mask",
  async () => {
    const calls: unknown[] = [];
    const resolver =
      createTariffZoneRuntimeResolverV1({
        googleGeocodingApiKey: apiKey,
        fetch: async (input, init) => {
          calls.push({input, init});
          return {
            ok: true,
            json: async () => googleBody(),
          };
        },
        resolveZoneFromEvidence:
          async () => "TR-TEST-ZONE",
      });

    await resolver(
      request(),
      quoteAtMillis,
    );

    assert.equal(calls.length, 1);
    const call = calls[0] as {
      input: string;
      init: {
        headers: Record<string, string>;
      };
    };

    const url = new URL(call.input);
    assert.equal(
      `${url.origin}${url.pathname}`,
      GOOGLE_GEOCODING_V4_LOCATION_ENDPOINT,
    );
    assert.equal(
      url.searchParams.get(
        "location.latitude",
      ),
      "39.92077",
    );
    assert.equal(
      url.searchParams.get(
        "location.longitude",
      ),
      "32.85411",
    );
    assert.equal(
      call.init.headers[
        "X-Goog-FieldMask"
      ],
      GOOGLE_GEOCODING_V4_FIELD_MASK,
    );
  },
);

test(
  "API key is used only by Google transport",
  async () => {
    let seenKey: string | null = null;
    let policyInput: unknown = null;

    const resolver =
      createTariffZoneRuntimeResolverV1({
        googleGeocodingApiKey: apiKey,
        fetch: async (_input, init) => {
          seenKey =
            init.headers["X-Goog-Api-Key"];
          return {
            ok: true,
            json: async () => googleBody(),
          };
        },
        resolveZoneFromEvidence:
          async (evidence) => {
            policyInput = evidence;
            return "TR-TEST-ZONE";
          },
      });

    await resolver(
      request(),
      quoteAtMillis,
    );

    assert.equal(seenKey, apiKey);
    assert.equal(
      JSON.stringify(policyInput)
        .includes(apiKey),
      false,
    );
  },
);

test(
  "zone policy receives only normalized evidence and quote time",
  async () => {
    const calls: unknown[] = [];

    const resolver =
      createTariffZoneRuntimeResolverV1({
        googleGeocodingApiKey: apiKey,
        fetch: async () => ({
          ok: true,
          json: async () => googleBody(),
        }),
        resolveZoneFromEvidence:
          async (evidence, at) => {
            calls.push({evidence, at});
            return "TR-TEST-ZONE";
          },
      });

    await resolver(
      request(),
      quoteAtMillis,
    );

    assert.deepEqual(
      calls,
      [{
        evidence: {
          source:
            "google-address-components-v1",
          countryCode: "TR",
          administrativeAreaLevel1: {
            longText: "Ankara",
            shortText: "Ankara",
          },
          administrativeAreaLevel2: {
            longText: "Cankaya",
            shortText: "Cankaya",
          },
          locality: null,
        },
        at: quoteAtMillis,
      }],
    );
  },
);

test(
  "changed client address label cannot alter zone-policy input",
  async () => {
    const seen: unknown[] = [];

    const resolver =
      createTariffZoneRuntimeResolverV1({
        googleGeocodingApiKey: apiKey,
        fetch: async () => ({
          ok: true,
          json: async () => googleBody(),
        }),
        resolveZoneFromEvidence:
          async (evidence, at) => {
            seen.push({evidence, at});
            return "TR-TEST-ZONE";
          },
      });

    await resolver(
      request("One"),
      quoteAtMillis,
    );
    await resolver(
      request("Two"),
      quoteAtMillis,
    );

    assert.deepEqual(
      seen[0],
      seen[1],
    );
  },
);

test(
  "client request id and dropoff never reach zone policy",
  async () => {
    let seen:
      Record<string, unknown> | null =
        null;

    const resolver =
      createTariffZoneRuntimeResolverV1({
        googleGeocodingApiKey: apiKey,
        fetch: async () => ({
          ok: true,
          json: async () => googleBody(),
        }),
        resolveZoneFromEvidence:
          async (evidence) => {
            seen =
              evidence as unknown as
                Record<string, unknown>;
            return "TR-TEST-ZONE";
          },
      });

    await resolver(
      request(),
      quoteAtMillis,
    );

    assert.ok(seen);
    for (const forbidden of [
      "requestId",
      "pickup",
      "dropoff",
      "addressLabel",
      "latitude",
      "longitude",
    ]) {
      assert.equal(
        forbidden in
          (seen as Record<string, unknown>),
        false,
      );
    }
  },
);

test(
  "Google transport failure becomes sanitized evidence unavailable",
  async () => {
    const resolver =
      createTariffZoneRuntimeResolverV1({
        googleGeocodingApiKey: apiKey,
        fetch: async () => {
          throw new Error(
            "transport detail",
          );
        },
        resolveZoneFromEvidence:
          async () => "TR-TEST-ZONE",
      });

    await assert.rejects(
      () =>
        resolver(
          request(),
          quoteAtMillis,
        ),
      /tariff_zone_jurisdiction_evidence_unavailable/u,
    );
  },
);

test(
  "conflicting Google jurisdiction becomes sanitized evidence unavailable",
  async () => {
    const resolver =
      createTariffZoneRuntimeResolverV1({
        googleGeocodingApiKey: apiKey,
        fetch: async () => ({
          ok: true,
          json: async () => ({
            results: [
              googleBody().results[0],
              {
                addressComponents: [
                  {
                    longText: "Konya",
                    shortText: "Konya",
                    types: [
                      "administrative_area_level_1",
                      "political",
                    ],
                  },
                  {
                    longText: "Turkiye",
                    shortText: "TR",
                    types: [
                      "country",
                      "political",
                    ],
                  },
                ],
              },
            ],
          }),
        }),
        resolveZoneFromEvidence:
          async () => "TR-TEST-ZONE",
      });

    await assert.rejects(
      () =>
        resolver(
          request(),
          quoteAtMillis,
        ),
      /tariff_zone_jurisdiction_evidence_unavailable/u,
    );
  },
);

test(
  "zone policy failure remains sanitized by resolver",
  async () => {
    const resolver =
      createTariffZoneRuntimeResolverV1({
        googleGeocodingApiKey: apiKey,
        fetch: async () => ({
          ok: true,
          json: async () => googleBody(),
        }),
        resolveZoneFromEvidence:
          async () => {
            throw new Error(
              "policy private detail",
            );
          },
      });

    await assert.rejects(
      () =>
        resolver(
          request(),
          quoteAtMillis,
        ),
      /tariff_zone_policy_unavailable/u,
    );
  },
);

test(
  "composition defines no concrete zone mapping or callable wiring",
  () => {
    const source =
      createTariffZoneRuntimeResolverV1
        .toString();

    for (const forbidden of [
      "TR-TEST-ZONE",
      "Ankara",
      "Cankaya",
      "UKOME",
      "onCall",
      "defineSecret",
    ]) {
      assert.equal(
        source.includes(forbidden),
        false,
      );
    }
  },
);
