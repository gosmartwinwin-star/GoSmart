import assert from "node:assert/strict";
import test from "node:test";
import {
  readFileSync,
} from "node:fs";

const source = readFileSync(
  "src/index.ts",
  "utf8",
);

const segment = (
  start: string,
  end: string,
): string => {
  const startIndex =
    source.indexOf(start);
  const endIndex =
    source.indexOf(
      end,
      startIndex + start.length,
    );

  assert.notEqual(
    startIndex,
    -1,
  );
  assert.notEqual(
    endIndex,
    -1,
  );
  assert.ok(
    endIndex > startIndex,
  );

  return source.slice(
    startIndex,
    endIndex,
  );
};

test(
  "index imports quote callable authority exactly once",
  () => {
    const matches =
      source.match(
        /createPassengerFareQuoteCallableV1/g,
      ) ?? [];

    assert.equal(
      matches.length,
      2,
    );
    assert.match(
      source,
      /from "\.\/ride-fare-quote-callable-authority-v1\.js";/u,
    );
  },
);

test(
  "index declares a dedicated geocoding secret",
  () => {
    assert.match(
      source,
      /defineSecret\(\s*"GOOGLE_GEOCODING_API_KEY"\s*,?\s*\)/u,
    );
  },
);

test(
  "quote callable enforces App Check and binds only geocoding secret",
  () => {
    const quote = segment(
      "export const createFareQuote = onCall(",
      "export const createRideRequest = onCall(",
    );

    assert.match(
      quote,
      /enforceAppCheck:\s*true/u,
    );
    assert.match(
      quote,
      /secrets:\s*\[googleGeocodingApiKey\]/u,
    );
    assert.doesNotMatch(
      quote,
      /secrets:\s*\[googlePlacesApiKey\]/u,
    );
  },
);

test(
  "quote callable requires authenticated server actor",
  () => {
    const quote = segment(
      "export const createFareQuote = onCall(",
      "export const createRideRequest = onCall(",
    );

    assert.match(
      quote,
      /if \(!request\.auth\?\.uid\)/u,
    );
    assert.match(
      quote,
      /request\.auth\.uid/u,
    );
    assert.doesNotMatch(
      quote,
      /request\.data\.(uid|passengerId|actorUid)/u,
    );
  },
);

test(
  "quote callable composes server Firestore route and geocoding dependencies",
  () => {
    const quote = segment(
      "export const createFareQuote = onCall(",
      "export const createRideRequest = onCall(",
    );

    assert.match(
      quote,
      /createPassengerFareQuoteCallableV1/u,
    );
    assert.match(
      quote,
      /firestore/u,
    );
    assert.match(
      quote,
      /googleGeocodingApiKey\.value\(\)/u,
    );
    assert.match(
      quote,
      /fetch/u,
    );
    assert.match(
      quote,
      /computeRoute:\s*computePublishedRoute/u,
    );
  },
);

test(
  "quote callable delegates exact client payload without money authority",
  () => {
    const quote = segment(
      "export const createFareQuote = onCall(",
      "export const createRideRequest = onCall(",
    );

    assert.match(
      quote,
      /handler\(\s*request\.auth\.uid,\s*request\.data,\s*\)/u,
    );

    for (const forbidden of [
      "fareMinor",
      "amountMinor",
      "tariffZoneId",
      "tariffVersionId",
      "passengerFareBasisPoints",
    ]) {
      assert.equal(
        quote.includes(forbidden),
        false,
      );
    }
  },
);

test(
  "existing Places secret remains separate",
  () => {
    assert.match(
      source,
      /defineSecret\(\s*"GOOGLE_PLACES_API_KEY"\s*,?\s*\)/u,
    );

    assert.notEqual(
      source.indexOf(
        "\"GOOGLE_PLACES_API_KEY\"",
      ),
      source.indexOf(
        "\"GOOGLE_GEOCODING_API_KEY\"",
      ),
    );
  },
);

test(
  "index wiring does not add tariff data mapping or Flutter authority",
  () => {
    const quote = segment(
      "export const createFareQuote = onCall(",
      "export const createRideRequest = onCall(",
    );

    for (const forbidden of [
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
        quote.includes(forbidden),
        false,
      );
    }
  },
);
