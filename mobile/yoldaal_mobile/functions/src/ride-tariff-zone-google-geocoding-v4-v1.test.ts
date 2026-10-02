import assert from "node:assert/strict";
import test from "node:test";
import {
  GOOGLE_GEOCODING_V4_FIELD_MASK,
  GOOGLE_GEOCODING_V4_LOCATION_ENDPOINT,
  createGoogleGeocodingV4AddressComponentsLookupV1,
} from "./ride-tariff-zone-google-geocoding-v4-v1.js";
import {
  parsePickupJurisdictionEvidenceV1,
} from "./ride-tariff-zone-jurisdiction-evidence-v1.js";

const apiKey = "server-secret-api-key";
const quoteAtMillis = 1757000000000;

const result = (
  level1 = "Ankara",
  level2: string | null = "Cankaya",
  locality: string | null = "Ankara",
) => {
  const addressComponents:
    Record<string, unknown>[] = [
      {
        longText: level1,
        shortText: level1,
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
    ];

  if (level2 !== null) {
    addressComponents.push({
      longText: level2,
      shortText: level2,
      types: [
        "administrative_area_level_2",
        "political",
      ],
    });
  }

  if (locality !== null) {
    addressComponents.push({
      longText: locality,
      shortText: locality,
      types: [
        "locality",
        "political",
      ],
    });
  }

  return {addressComponents};
};

test(
  "request uses v4 location endpoint and pickup coordinates",
  async () => {
    const calls: unknown[] = [];
    const lookup =
      createGoogleGeocodingV4AddressComponentsLookupV1({
        apiKey,
        fetch: async (input, init) => {
          calls.push({input, init});
          return {
            ok: true,
            json: async () => ({
              results: [result()],
            }),
          };
        },
      });

    await lookup(
      {
        latitude: 39.92077,
        longitude: 32.85411,
      },
      quoteAtMillis,
    );

    assert.equal(calls.length, 1);
    const call =
      calls[0] as {
        input: string;
        init: {
          method: string;
          headers:
            Record<string, string>;
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
      url.searchParams.get(
        "languageCode",
      ),
      "tr",
    );
  },
);

test(
  "request keeps key in header and field masks response",
  async () => {
    let seenHeaders:
      Record<string, string> | null =
        null;

    const lookup =
      createGoogleGeocodingV4AddressComponentsLookupV1({
        apiKey,
        fetch: async (_input, init) => {
          seenHeaders = {
            ...init.headers,
          };
          return {
            ok: true,
            json: async () => ({
              results: [result()],
            }),
          };
        },
      });

    await lookup(
      {
        latitude: 39.9,
        longitude: 32.8,
      },
      quoteAtMillis,
    );

    assert.ok(seenHeaders);
    assert.equal(
      (seenHeaders as Record<string, string>)[
        "X-Goog-Api-Key"
      ],
      apiKey,
    );
    assert.equal(
      (seenHeaders as Record<string, string>)[
        "X-Goog-FieldMask"
      ],
      GOOGLE_GEOCODING_V4_FIELD_MASK,
    );
  },
);

test(
  "single usable result becomes Phase Q compatible components",
  async () => {
    const lookup =
      createGoogleGeocodingV4AddressComponentsLookupV1({
        apiKey,
        fetch: async () => ({
          ok: true,
          json: async () => ({
            results: [result()],
          }),
        }),
      });

    const raw = await lookup(
      {
        latitude: 39.9,
        longitude: 32.8,
      },
      quoteAtMillis,
    );

    const evidence =
      parsePickupJurisdictionEvidenceV1(
        raw,
      );

    assert.equal(
      evidence.countryCode,
      "TR",
    );
    assert.equal(
      evidence.administrativeAreaLevel1
        .shortText,
      "Ankara",
    );
    assert.equal(
      evidence.administrativeAreaLevel2
        ?.shortText,
      "Cankaya",
    );
  },
);

test(
  "multiple consistent results merge optional evidence",
  async () => {
    const lookup =
      createGoogleGeocodingV4AddressComponentsLookupV1({
        apiKey,
        fetch: async () => ({
          ok: true,
          json: async () => ({
            results: [
              result(
                "Ankara",
                null,
                "Ankara",
              ),
              result(
                "Ankara",
                "Cankaya",
                null,
              ),
            ],
          }),
        }),
      });

    const evidence =
      parsePickupJurisdictionEvidenceV1(
        await lookup(
          {
            latitude: 39.9,
            longitude: 32.8,
          },
          quoteAtMillis,
        ),
      );

    assert.equal(
      evidence.administrativeAreaLevel2
        ?.shortText,
      "Cankaya",
    );
    assert.equal(
      evidence.locality?.shortText,
      "Ankara",
    );
  },
);

test(
  "conflicting jurisdiction results fail closed",
  async () => {
    const lookup =
      createGoogleGeocodingV4AddressComponentsLookupV1({
        apiKey,
        fetch: async () => ({
          ok: true,
          json: async () => ({
            results: [
              result("Ankara"),
              result("Konya"),
            ],
          }),
        }),
      });

    await assert.rejects(
      () =>
        lookup(
          {
            latitude: 39.9,
            longitude: 32.8,
          },
          quoteAtMillis,
        ),
      /google_geocoding_v4_jurisdiction_ambiguous/u,
    );
  },
);

test(
  "results without usable Turkish jurisdiction fail closed",
  async () => {
    const lookup =
      createGoogleGeocodingV4AddressComponentsLookupV1({
        apiKey,
        fetch: async () => ({
          ok: true,
          json: async () => ({
            results: [{
              addressComponents: [{
                longText: "Street",
                shortText: "Street",
                types: ["route"],
              }],
            }],
          }),
        }),
      });

    await assert.rejects(
      () =>
        lookup(
          {
            latitude: 39.9,
            longitude: 32.8,
          },
          quoteAtMillis,
        ),
      /google_geocoding_v4_jurisdiction_missing/u,
    );
  },
);

test(
  "transport and http failures are sanitized",
  async () => {
    const throwing =
      createGoogleGeocodingV4AddressComponentsLookupV1({
        apiKey,
        fetch: async () => {
          throw new Error(
            "network secret detail",
          );
        },
      });

    await assert.rejects(
      () =>
        throwing(
          {
            latitude: 39.9,
            longitude: 32.8,
          },
          quoteAtMillis,
        ),
      /google_geocoding_v4_unavailable/u,
    );

    const httpFailure =
      createGoogleGeocodingV4AddressComponentsLookupV1({
        apiKey,
        fetch: async () => ({
          ok: false,
          json: async () => ({
            privateError: "hidden",
          }),
        }),
      });

    await assert.rejects(
      () =>
        httpFailure(
          {
            latitude: 39.9,
            longitude: 32.8,
          },
          quoteAtMillis,
        ),
      /google_geocoding_v4_unavailable/u,
    );
  },
);

test(
  "malformed json response fails closed",
  async () => {
    const badJson =
      createGoogleGeocodingV4AddressComponentsLookupV1({
        apiKey,
        fetch: async () => ({
          ok: true,
          json: async () => {
            throw new SyntaxError(
              "bad json",
            );
          },
        }),
      });

    await assert.rejects(
      () =>
        badJson(
          {
            latitude: 39.9,
            longitude: 32.8,
          },
          quoteAtMillis,
        ),
      /google_geocoding_v4_response_invalid/u,
    );
  },
);

test(
  "invalid key and coordinates fail before fetch",
  async () => {
    let calls = 0;

    assert.throws(
      () =>
        createGoogleGeocodingV4AddressComponentsLookupV1({
          apiKey: " ",
          fetch: async () => {
            calls += 1;
            return {
              ok: true,
              json: async () => ({}),
            };
          },
        }),
      /google_geocoding_v4_api_key_invalid/u,
    );

    const lookup =
      createGoogleGeocodingV4AddressComponentsLookupV1({
        apiKey,
        fetch: async () => {
          calls += 1;
          return {
            ok: true,
            json: async () => ({}),
          };
        },
      });

    await assert.rejects(
      () =>
        lookup(
          {
            latitude: 91,
            longitude: 32.8,
          },
          quoteAtMillis,
        ),
      /google_geocoding_v4_coordinate_invalid/u,
    );

    assert.equal(calls, 0);
  },
);

test(
  "lookup exposes no tariff zone mapping or monetary authority",
  () => {
    const source =
      createGoogleGeocodingV4AddressComponentsLookupV1
        .toString();

    for (const forbidden of [
      "tariffZoneId",
      "yoldaalFareMinor",
      "referenceEstimatedFareMinor",
      "Ankara",
      "Cankaya",
      "UKOME",
    ]) {
      assert.equal(
        source.includes(forbidden),
        false,
      );
    }
  },
);
