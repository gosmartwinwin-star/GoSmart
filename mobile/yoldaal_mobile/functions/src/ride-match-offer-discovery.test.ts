import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {
  parseMatchingRideCandidate,
  RIDE_MATCH_DISCOVERY_CANDIDATE_LIMIT,
  RIDE_MATCH_DISCOVERY_OFFER_LIMIT,
  toPublicDiscoveredRideOffer,
} from "./ride-match-offer-discovery.js";
import {
  buildRideMatchOffer,
} from "./ride-match-offer-helpers.js";

const candidateData = () => ({
  passengerId: "passenger-1",
  driverId: null,
  status: "matching",
  version: 1,
  pickup: {
    latitude: 41.0082,
    longitude: 28.9784,
    addressLabel: " Pickup ",
  },
  dropoff: {
    latitude: 41.0151,
    longitude: 28.9795,
    addressLabel: "Dropoff",
  },
});

test(
  "matching ride candidate requires canonical unassigned shape",
  () => {
    const candidate =
      parseMatchingRideCandidate(
        "ride-1",
        candidateData(),
      );

    assert.ok(candidate);

    assert.equal(
      candidate.passengerId,
      "passenger-1",
    );

    assert.equal(
      candidate.version,
      1,
    );

    assert.equal(
      candidate.pickup.addressLabel,
      "Pickup",
    );

    assert.equal(
      candidate.dropoff.addressLabel,
      "Dropoff",
    );
  },
);

test(
  "assigned malformed and non-matching rides are rejected",
  () => {
    assert.equal(
      parseMatchingRideCandidate(
        "ride-1",
        {
          ...candidateData(),
          driverId: "driver-1",
        },
      ),
      null,
    );

    assert.equal(
      parseMatchingRideCandidate(
        "ride-1",
        {
          ...candidateData(),
          status: "driverEnRoute",
        },
      ),
      null,
    );

    assert.equal(
      parseMatchingRideCandidate(
        "ride-1",
        {
          ...candidateData(),
          version: 0,
        },
      ),
      null,
    );

    assert.equal(
      parseMatchingRideCandidate(
        "ride-1",
        {
          ...candidateData(),
          pickup: {
            latitude: 91,
            longitude: 29,
            addressLabel: "Invalid",
          },
        },
      ),
      null,
    );
  },
);

test(
  "public discovered offer omits identity route and measurement internals",
  () => {
    const candidate =
      parseMatchingRideCandidate(
        "ride-1",
        candidateData(),
      );

    assert.ok(candidate);

    const now =
      Timestamp.fromMillis(
        1_800_000_000_000,
      );

    const offer =
      buildRideMatchOffer({
        driverId: "driver-1",
        rideId: "ride-1",
        rideVersion: 1,
        returnRouteId: "route-1",
        routeExpiresAt:
          Timestamp.fromMillis(
            now.toMillis() + 600_000,
          ),
        now,
        measurement: {
          pickupRouteIndex: 1,
          dropoffRouteIndex: 4,
          pickupDetourMeters: 1000,
          pickupDetourSeconds: 200,
          dropoffDetourMeters: 1200,
          dropoffDetourSeconds: 240,
        },
      });

    const publicOffer =
      toPublicDiscoveredRideOffer(
        candidate,
        offer,
      );

    const serialized =
      JSON.stringify(publicOffer);

    assert.equal(
      publicOffer.rideId,
      "ride-1",
    );

    assert.equal(
      publicOffer.rideVersion,
      1,
    );

    for (const forbidden of [
      "passengerId",
      "driverId",
      "returnRouteId",
      "measurement",
      "policyVersion",
      "consumedAt",
    ]) {
      assert.equal(
        serialized.includes(forbidden),
        false,
      );
    }
  },
);

test(
  "discovery limits are bounded",
  () => {
    assert.equal(
      RIDE_MATCH_DISCOVERY_CANDIDATE_LIMIT,
      5,
    );

    assert.equal(
      RIDE_MATCH_DISCOVERY_OFFER_LIMIT,
      3,
    );

    assert.ok(
      RIDE_MATCH_DISCOVERY_OFFER_LIMIT <
      RIDE_MATCH_DISCOVERY_CANDIDATE_LIMIT,
    );
  },
);

test(
  "matching ride discovery composite index is declared",
  () => {
    const indexes =
      JSON.parse(
        readFileSync(
          "../firestore.indexes.json",
          "utf8",
        ),
      ) as {
        indexes?: Array<{
          collectionGroup?: unknown;
          fields?: Array<{
            fieldPath?: unknown;
            order?: unknown;
          }>;
        }>;
      };

    const found =
      indexes.indexes?.some(
        (index) =>
          index.collectionGroup ===
            "rides" &&
          JSON.stringify(index.fields) ===
            JSON.stringify([
              {
                fieldPath: "status",
                order: "ASCENDING",
              },
              {
                fieldPath: "updatedAt",
                order: "DESCENDING",
              },
              {
                fieldPath: "__name__",
                order: "DESCENDING",
              },
            ]),
      );

    assert.equal(found, true);
  },
);
