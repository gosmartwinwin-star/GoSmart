/* eslint-disable max-len */
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";

const indexSource =
  readFileSync(
    "src/index.ts",
    "utf8",
  );

const callableSource = (
  name: string,
): string => {
  const marker =
    `export const ${name} = onCall`;

  const start =
    indexSource.indexOf(marker);

  assert.notEqual(start, -1);

  const next =
    indexSource.indexOf(
      "export const ",
      start + marker.length,
    );

  return next === -1 ?
    indexSource.slice(start) :
    indexSource.slice(start, next);
};

test(
  "ride match offer callable is authenticated regional and identity safe",
  () => {
    const callable =
      callableSource(
        "getMyRideMatchOffers",
      );

    assert.match(
      callable,
      /region: "europe-west1"/u,
    );

    assert.match(
      callable,
      /timeoutSeconds: 30/u,
    );

    assert.match(
      callable,
      /if \(!request\.auth\?\.uid\)/u,
    );

    assert.match(
      callable,
      /Object\.keys\(request\.data\)\.length !== 0/u,
    );

    assert.match(
      callable,
      /invalid_ride_match_offer_payload/u,
    );

    assert.match(
      callable,
      /discoverRideMatchOffersForDriver/u,
    );

    assert.match(
      callable,
      /request\.auth\.uid/u,
    );

    assert.match(
      callable,
      /measureDeviation:\s*computeRideMatchDeviation/u,
    );

    assert.doesNotMatch(
      callable,
      /request\.data\.(driverId|passengerId|uid|authUserId|returnRouteId|rideId)/u,
    );
  },
);

test(
  "production deviation adapter uses only server derived anchors",
  () => {
    const start =
      indexSource.indexOf(
        "const computeRideMatchDeviation",
      );

    const end =
      indexSource.indexOf(
        "const safePrecondition",
        start,
      );

    assert.ok(
      start >= 0 &&
      end > start,
    );

    const adapter =
      indexSource.slice(
        start,
        end,
      );

    assert.match(
      adapter,
      /Promise\.all/u,
    );

    assert.match(
      adapter,
      /computeDrivingMeasurement\(\s*input\.pickupAnchor,\s*input\.pickup/u,
    );

    assert.match(
      adapter,
      /computeDrivingMeasurement\(\s*input\.dropoff,\s*input\.dropoffAnchor/u,
    );

    assert.doesNotMatch(
      adapter,
      /request\.data|driverId|passengerId|returnRouteId/u,
    );
  },
);

test(
  "ride match offer documents are explicitly client inaccessible",
  () => {
    const rules =
      readFileSync(
        "../firestore.rules",
        "utf8",
      );

    assert.match(
      rules,
      /match \/driverRideMatchOffers\/\{offerId\}\s*\{\s*allow read, write: if false;\s*\}/u,
    );
  },
);
/* eslint-enable max-len */
