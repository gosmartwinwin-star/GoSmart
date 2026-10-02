/* eslint-disable max-len */
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";

const discoverySource =
  readFileSync(
    "src/ride-match-offer-discovery.ts",
    "utf8",
  );

const indexSource =
  readFileSync(
    "src/index.ts",
    "utf8",
  );

test(
  "driver offer discovery owns fare projection through the production adapter",
  () => {
    assert.match(
      discoverySource,
      /attachFareToDriverOfferV1/u,
    );
    assert.match(
      discoverySource,
      /DriverRideMatchOfferFareV1/u,
    );
    assert.doesNotMatch(
      indexSource,
      /attachFareToDriverOfferV1/u,
    );
  },
);

test(
  "discovery result type requires a driver-safe nested fare",
  () => {
    assert.match(
      discoverySource,
      /export type FareBoundPublicDiscoveredRideOffer =[\s\S]{0,220}fare: DriverRideMatchOfferFareV1;/u,
    );
    assert.match(
      discoverySource,
      /offers: FareBoundPublicDiscoveredRideOffer\[\];/u,
    );
  },
);

test(
  "transaction preserves the exact re-read persisted ride for projection",
  () => {
    const capture =
      discoverySource.indexOf(
        "const persistedRide =",
      );
    const parse =
      discoverySource.indexOf(
        "parseMatchingRideCandidate(",
        capture,
      );
    const pointerRead =
      discoverySource.indexOf(
        ".collection(\n                  \"passengerActiveRides\",",
        capture,
      );
    const accepted =
      discoverySource.indexOf(
        "acceptedCandidates.push({",
        capture,
      );

    assert.ok(capture >= 0);
    assert.ok(parse > capture);
    assert.ok(pointerRead > parse);
    assert.ok(accepted > pointerRead);
    assert.match(
      discoverySource.slice(capture, accepted + 180),
      /acceptedCandidates\.push\(\{[\s\S]{0,120}persistedRide,/u,
    );
  },
);

test(
  "public offer fare derives from the same persisted ride re-read",
  () => {
    assert.match(
      discoverySource,
      /const publicOffer =[\s\S]{0,220}toPublicDiscoveredRideOffer\([\s\S]{0,260}attachFareToDriverOfferV1\(\s*publicOffer,\s*item\.persistedRide,\s*\)/u,
    );
  },
);

test(
  "internal driverRideMatchOffers record remains the existing authority shape",
  () => {
    assert.match(
      discoverySource,
      /transaction\.set\(\s*offerRef,\s*offer,\s*\);/u,
    );
    assert.doesNotMatch(
      discoverySource,
      /transaction\.set\(\s*offerRef,[\s\S]{0,180}attachFareToDriverOfferV1/u,
    );
  },
);

test(
  "driver offer cutover does not copy passenger comparison or quote identity",
  () => {
    const projectionStart =
      discoverySource.indexOf(
        "offers.push(\n            attachFareToDriverOfferV1(",
      );

    assert.ok(projectionStart >= 0);

    const projection =
      discoverySource.slice(
        projectionStart,
        projectionStart + 420,
      );

    assert.doesNotMatch(
      projection,
      /quoteId|referenceEstimatedFareMinor|savingMinor|tariffVersionId|farePolicyVersionId/u,
    );
  },
);
