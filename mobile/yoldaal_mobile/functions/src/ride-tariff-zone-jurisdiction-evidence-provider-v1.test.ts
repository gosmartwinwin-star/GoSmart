import assert from "node:assert/strict";
import test from "node:test";
import {
  FareQuoteRequestV1,
} from "./ride-fare-quote-persistence-v1.js";
import {
  createPickupJurisdictionEvidenceProviderV1,
} from "./ride-tariff-zone-jurisdiction-evidence-provider-v1.js";

const quoteAtMillis = 1757000000000;

const request = (
  pickupAddressLabel = "Kizilay, Ankara",
): FareQuoteRequestV1 => ({
  requestId:
    "shared_quote_ride_request_1234",
  pickup: {
    latitude: 39.92077,
    longitude: 32.85411,
    addressLabel: pickupAddressLabel,
  },
  dropoff: {
    latitude: 39.95,
    longitude: 32.88,
    addressLabel: "Dropoff",
  },
});

const components = () => [
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
];

test(
  "provider passes only pickup coordinates and quote time to lookup",
  async () => {
    const calls: unknown[] = [];
    const provider =
      createPickupJurisdictionEvidenceProviderV1({
        lookupAddressComponents:
          async (pickup, at) => {
            calls.push({pickup, at});
            return components();
          },
      });

    await provider(
      request(),
      quoteAtMillis,
    );

    assert.deepEqual(
      calls,
      [{
        pickup: {
          latitude: 39.92077,
          longitude: 32.85411,
        },
        at: quoteAtMillis,
      }],
    );
  },
);

test(
  "provider returns normalized Phase Q evidence",
  async () => {
    const provider =
      createPickupJurisdictionEvidenceProviderV1({
        lookupAddressComponents:
          async () => components(),
      });

    assert.deepEqual(
      await provider(
        request(),
        quoteAtMillis,
      ),
      {
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
    );
  },
);

test(
  "changed client address label cannot alter lookup authority",
  async () => {
    const calls: unknown[] = [];
    const provider =
      createPickupJurisdictionEvidenceProviderV1({
        lookupAddressComponents:
          async (pickup, at) => {
            calls.push({pickup, at});
            return components();
          },
      });

    const first =
      await provider(
        request("Client Label One"),
        quoteAtMillis,
      );
    const second =
      await provider(
        request("Client Label Two"),
        quoteAtMillis,
      );

    assert.deepEqual(
      calls[0],
      calls[1],
    );
    assert.deepEqual(
      first,
      second,
    );
  },
);

test(
  "dropoff and request id are not passed to lookup",
  async () => {
    let seen:
      Record<string, unknown> | null =
        null;

    const provider =
      createPickupJurisdictionEvidenceProviderV1({
        lookupAddressComponents:
          async (pickup) => {
            seen =
              pickup as unknown as
                Record<string, unknown>;
            return components();
          },
      });

    await provider(
      request(),
      quoteAtMillis,
    );

    assert.ok(seen);
    assert.deepEqual(
      Object.keys(
        seen as Record<string, unknown>,
      ).sort(),
      ["latitude", "longitude"],
    );
  },
);

test(
  "invalid quote time fails before lookup",
  async () => {
    let calls = 0;
    const provider =
      createPickupJurisdictionEvidenceProviderV1({
        lookupAddressComponents:
          async () => {
            calls += 1;
            return components();
          },
      });

    for (const invalid of [
      -1,
      1.5,
      Number.MAX_SAFE_INTEGER + 1,
    ]) {
      await assert.rejects(
        () =>
          provider(
            request(),
            invalid,
          ),
        /tariff_zone_jurisdiction_quote_time_invalid/u,
      );
    }

    assert.equal(calls, 0);
  },
);

test(
  "invalid fare quote request fails before lookup",
  async () => {
    let calls = 0;
    const provider =
      createPickupJurisdictionEvidenceProviderV1({
        lookupAddressComponents:
          async () => {
            calls += 1;
            return components();
          },
      });

    await assert.rejects(
      () =>
        provider(
          {
            ...request(),
            tariffZoneId:
              "client-injected",
          } as unknown as
            FareQuoteRequestV1,
          quoteAtMillis,
        ),
    );

    assert.equal(calls, 0);
  },
);

test(
  "lookup failure is sanitized",
  async () => {
    const provider =
      createPickupJurisdictionEvidenceProviderV1({
        lookupAddressComponents:
          async () => {
            throw new Error(
              "upstream secret detail",
            );
          },
      });

    await assert.rejects(
      () =>
        provider(
          request(),
          quoteAtMillis,
        ),
      /tariff_zone_jurisdiction_evidence_unavailable/u,
    );
  },
);

test(
  "malformed lookup data remains evidence invalid",
  async () => {
    const provider =
      createPickupJurisdictionEvidenceProviderV1({
        lookupAddressComponents:
          async () => [{
            longText: "Ankara",
            shortText: "Ankara",
            types: [
              "administrative_area_level_1",
            ],
          }],
      });

    await assert.rejects(
      () =>
        provider(
          request(),
          quoteAtMillis,
        ),
      /tariff_zone_jurisdiction_evidence_invalid/u,
    );
  },
);

test(
  "provider output contains no tariff zone or actor authority",
  async () => {
    const provider =
      createPickupJurisdictionEvidenceProviderV1({
        lookupAddressComponents:
          async () => components(),
      });

    const result =
      await provider(
        request(),
        quoteAtMillis,
      );
    const keys = Object.keys(result);

    for (const forbidden of [
      "tariffZoneId",
      "tariffVersionId",
      "farePolicyVersionId",
      "passengerId",
      "driverId",
      "addressLabel",
      "latitude",
      "longitude",
      "referenceEstimatedFareMinor",
      "yoldaalFareMinor",
    ]) {
      assert.equal(
        keys.includes(forbidden),
        false,
      );
    }
  },
);

test(
  "provider invents no network or cross-zone semantics",
  () => {
    const source =
      createPickupJurisdictionEvidenceProviderV1
        .toString();

    assert.equal(
      source.includes("fetch("),
      false,
    );
    assert.equal(
      source.includes("tariffZoneId"),
      false,
    );
    assert.equal(
      source.includes("dropoff"),
      false,
    );
  },
);
