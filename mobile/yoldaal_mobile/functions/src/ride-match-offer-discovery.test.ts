/* eslint-disable max-len */
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
  createdAt: Timestamp.fromMillis(
    1700000000000,
  ),
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
  route: {
    distanceMeters: 10000,
    durationSeconds: 1200,
    encodedPolyline: "passenger_route",
    computedAt: Timestamp.fromMillis(
      1700000000000,
    ),
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
      candidate.createdAt.toMillis(),
      1700000000000,
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
  "matching ride candidate requires canonical createdAt",
  () => {
    assert.equal(
      parseMatchingRideCandidate(
        "ride-1",
        {
          ...candidateData(),
          createdAt: null,
        },
      ),
      null,
    );

    assert.equal(
      parseMatchingRideCandidate(
        "ride-1",
        {
          ...candidateData(),
          createdAt:
            "not-a-server-timestamp",
        },
      ),
      null,
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
  "matching ride candidate requires canonical route metrics",
  () => {
    assert.equal(
      parseMatchingRideCandidate(
        "ride-1",
        {
          ...candidateData(),
          route: null,
        },
      ),
      null,
    );

    assert.equal(
      parseMatchingRideCandidate(
        "ride-1",
        {
          ...candidateData(),
          route: {
            ...candidateData().route,
            distanceMeters: 0,
          },
        },
      ),
      null,
    );

    assert.equal(
      parseMatchingRideCandidate(
        "ride-1",
        {
          ...candidateData(),
          route: {
            ...candidateData().route,
            durationSeconds: 0,
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

    assert.equal(
      publicOffer.pickupDetourMeters,
      1000,
    );

    assert.equal(
      publicOffer.pickupDetourSeconds,
      200,
    );

    assert.equal(
      publicOffer.dropoffDetourMeters,
      1200,
    );

    assert.equal(
      publicOffer.dropoffDetourSeconds,
      240,
    );

    assert.equal(
      publicOffer.passengerTripDistanceMeters,
      10000,
    );

    assert.equal(
      publicOffer.passengerTripDurationSeconds,
      1200,
    );

    for (const forbidden of [
      "passengerId",
      "driverId",
      "returnRouteId",
      "measurement",
      "policyVersion",
      "encodedPolyline",
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
const w1bSelectionPolicyModule =
  import("./ride-match-offer-discovery.js");

const w1bPreparedCandidate = (
  rideId: string,
  createdAtMillis: number,
  pickupProximityMeters: number,
  dropoffProximityMeters: number,
) => ({
  candidate: {
    rideId,
    passengerId:
      `passenger-${rideId}`,
    version: 1,
    createdAt:
      Timestamp.fromMillis(
        createdAtMillis,
      ),
    pickup: {
      latitude: 41,
      longitude: 29,
      addressLabel:
        `Pickup ${rideId}`,
    },
    dropoff: {
      latitude: 41.02,
      longitude: 29.02,
      addressLabel:
        `Dropoff ${rideId}`,
    },
    passengerTripDistanceMeters: 10000,
    passengerTripDurationSeconds: 1200,
  },
  anchors: {
    pickupRouteIndex: 0,
    dropoffRouteIndex: 2,
    pickupAnchor: {
      latitude: 41,
      longitude: 29,
    },
    dropoffAnchor: {
      latitude: 41.02,
      longitude: 29.02,
    },
    pickupAnchorProximityMeters:
      pickupProximityMeters,
    dropoffAnchorProximityMeters:
      dropoffProximityMeters,
  },
});

const w1bEvaluatedCandidate = (
  rideId: string,
  createdAtMillis: number,
  fairnessProtected: boolean,
  pickupDetourMeters: number,
  pickupDetourSeconds: number,
  dropoffDetourMeters: number,
  dropoffDetourSeconds: number,
) => ({
  candidate:
    w1bPreparedCandidate(
      rideId,
      createdAtMillis,
      0,
      0,
    ).candidate,
  fairnessProtected,
  measurement: {
    pickupRouteIndex: 0,
    dropoffRouteIndex: 2,
    pickupDetourMeters,
    pickupDetourSeconds,
    dropoffDetourMeters,
    dropoffDetourSeconds,
  },
});

test(
  "W1B selection policy v1 freezes 15 minute aging and 2 plus 3 slots",
  async () => {
    const policy =
      await w1bSelectionPolicyModule;

    assert.equal(
      policy.RIDE_MATCH_DISCOVERY_AGING_THRESHOLD_SECONDS,
      15 * 60,
    );

    assert.equal(
      policy.RIDE_MATCH_DISCOVERY_FAIRNESS_SLOT_LIMIT,
      2,
    );

    assert.equal(
      policy.RIDE_MATCH_DISCOVERY_BEST_ROUTE_SLOT_LIMIT,
      3,
    );

    assert.equal(
      policy.RIDE_MATCH_DISCOVERY_FAIRNESS_SLOT_LIMIT +
        policy.RIDE_MATCH_DISCOVERY_BEST_ROUTE_SLOT_LIMIT,
      policy.RIDE_MATCH_DISCOVERY_CANDIDATE_LIMIT,
    );
  },
);

test(
  "W1B selection aging starts at exact 15 minute boundary",
  async () => {
    const policy =
      await w1bSelectionPolicyModule;

    const now =
      Timestamp.fromMillis(
        2_000_000,
      );

    const thresholdMillis =
      policy.RIDE_MATCH_DISCOVERY_AGING_THRESHOLD_SECONDS *
      1000;

    const exact =
      w1bPreparedCandidate(
        "exact-aging",
        now.toMillis() -
          thresholdMillis,
        0,
        0,
      );

    const oneMillisecondYoung =
      w1bPreparedCandidate(
        "young-aging",
        now.toMillis() -
          thresholdMillis +
          1,
        0,
        0,
      );

    assert.equal(
      policy.isRideMatchCandidateAged(
        exact.candidate,
        now,
      ),
      true,
    );

    assert.equal(
      policy.isRideMatchCandidateAged(
        oneMillisecondYoung.candidate,
        now,
      ),
      false,
    );
  },
);

test(
  "W1B cheap endpoint gate never bypasses 3000 meter hard distance",
  async () => {
    const policy =
      await w1bSelectionPolicyModule;

    const prepared =
      w1bPreparedCandidate(
        "cheap-gate",
        1_500_000,
        0,
        0,
      );

    assert.equal(
      policy.isRideMatchCheapEndpointEligible(
        {
          latitude: 41,
          longitude: 29,
        },
        {
          latitude: 41.02,
          longitude: 29.02,
        },
        prepared.candidate,
      ),
      true,
    );

    assert.equal(
      policy.isRideMatchCheapEndpointEligible(
        {
          latitude: 41.1,
          longitude: 29,
        },
        {
          latitude: 41.02,
          longitude: 29.02,
        },
        prepared.candidate,
      ),
      false,
    );
  },
);

test(
  "W1B selection policy v1 reserves two aged fairness slots",
  async () => {
    const policy =
      await w1bSelectionPolicyModule;

    const now =
      Timestamp.fromMillis(
        2_000_000,
      );

    const selected =
      policy.selectRideMatchPromisingCandidates(
        [
          w1bPreparedCandidate(
            "aged-oldest",
            0,
            2500,
            2500,
          ),
          w1bPreparedCandidate(
            "aged-second",
            100_000,
            2400,
            2400,
          ),
          w1bPreparedCandidate(
            "aged-route-best",
            200_000,
            10,
            10,
          ),
          w1bPreparedCandidate(
            "young-route-a",
            1_500_000,
            20,
            20,
          ),
          w1bPreparedCandidate(
            "young-route-b",
            1_550_000,
            30,
            30,
          ),
          w1bPreparedCandidate(
            "young-route-c",
            1_600_000,
            40,
            40,
          ),
        ],
        now,
      );

    assert.deepEqual(
      selected.map(
        (item) =>
          item.candidate.rideId,
      ),
      [
        "aged-oldest",
        "aged-second",
        "aged-route-best",
        "young-route-a",
        "young-route-b",
      ],
    );

    assert.deepEqual(
      selected.map(
        (item) =>
          item.fairnessProtected,
      ),
      [
        true,
        true,
        false,
        false,
        false,
      ],
    );
  },
);

test(
  "W1B unused fairness capacity spills into best route capacity",
  async () => {
    const policy =
      await w1bSelectionPolicyModule;

    const now =
      Timestamp.fromMillis(
        2_000_000,
      );

    const selected =
      policy.selectRideMatchPromisingCandidates(
        [
          w1bPreparedCandidate(
            "aged-only",
            0,
            2500,
            2500,
          ),
          w1bPreparedCandidate(
            "route-a",
            1_500_000,
            10,
            10,
          ),
          w1bPreparedCandidate(
            "route-b",
            1_510_000,
            20,
            20,
          ),
          w1bPreparedCandidate(
            "route-c",
            1_520_000,
            30,
            30,
          ),
          w1bPreparedCandidate(
            "route-d",
            1_530_000,
            40,
            40,
          ),
        ],
        now,
      );

    assert.equal(
      selected.length,
      5,
    );

    assert.equal(
      selected.filter(
        (item) =>
          item.fairnessProtected,
      ).length,
      1,
    );
  },
);

test(
  "W1B cheap best route minimizes worst normalized endpoint before total",
  async () => {
    const policy =
      await w1bSelectionPolicyModule;

    const now =
      Timestamp.fromMillis(
        2_000_000,
      );

    const selected =
      policy.selectRideMatchPromisingCandidates(
        [
          w1bPreparedCandidate(
            "worst-090",
            1_500_000,
            2700,
            0,
          ),
          w1bPreparedCandidate(
            "worst-060",
            1_510_000,
            1800,
            1800,
          ),
          w1bPreparedCandidate(
            "worst-070",
            1_520_000,
            2100,
            0,
          ),
          w1bPreparedCandidate(
            "worst-080",
            1_530_000,
            2400,
            0,
          ),
          w1bPreparedCandidate(
            "worst-050",
            1_540_000,
            1500,
            0,
          ),
          w1bPreparedCandidate(
            "worst-040",
            1_550_000,
            1200,
            0,
          ),
        ],
        now,
      );

    assert.deepEqual(
      selected.map(
        (item) =>
          item.candidate.rideId,
      ),
      [
        "worst-040",
        "worst-050",
        "worst-060",
        "worst-070",
        "worst-080",
      ],
    );
  },
);

test(
  "W1B cheap best route uses normalized total then createdAt and rideId as ties",
  async () => {
    const policy =
      await w1bSelectionPolicyModule;

    const now =
      Timestamp.fromMillis(
        2_000_000,
      );

    const selected =
      policy.selectRideMatchPromisingCandidates(
        [
          w1bPreparedCandidate(
            "total-high",
            1_500_000,
            1500,
            1500,
          ),
          w1bPreparedCandidate(
            "ride-z",
            1_400_000,
            1500,
            0,
          ),
          w1bPreparedCandidate(
            "ride-b",
            1_300_000,
            1500,
            0,
          ),
          w1bPreparedCandidate(
            "ride-a",
            1_300_000,
            1500,
            0,
          ),
          w1bPreparedCandidate(
            "better-a",
            1_600_000,
            900,
            0,
          ),
          w1bPreparedCandidate(
            "better-b",
            1_610_000,
            1200,
            0,
          ),
        ],
        now,
      );

    assert.deepEqual(
      selected.map(
        (item) =>
          item.candidate.rideId,
      ),
      [
        "better-a",
        "better-b",
        "ride-a",
        "ride-b",
        "ride-z",
      ],
    );
  },
);

test(
  "W1B final offers preserve eligible fairness before measured route ranking",
  async () => {
    const policy =
      await w1bSelectionPolicyModule;

    const ranked =
      policy.rankRideMatchEligibleOffers(
        [
          w1bEvaluatedCandidate(
            "fair-oldest",
            0,
            true,
            2700,
            810,
            2700,
            810,
          ),
          w1bEvaluatedCandidate(
            "fair-second",
            100_000,
            true,
            2850,
            855,
            2850,
            855,
          ),
          w1bEvaluatedCandidate(
            "route-a",
            1_500_000,
            false,
            1500,
            450,
            1500,
            450,
          ),
          w1bEvaluatedCandidate(
            "route-b",
            1_510_000,
            false,
            1200,
            360,
            1200,
            360,
          ),
          w1bEvaluatedCandidate(
            "route-c",
            1_520_000,
            false,
            900,
            270,
            900,
            270,
          ),
        ],
      );

    assert.deepEqual(
      ranked.map(
        (item) =>
          item.candidate.rideId,
      ),
      [
        "fair-oldest",
        "fair-second",
        "route-c",
      ],
    );
  },
);

test(
  "W1B measured best route minimizes worst normalized constraint before total",
  async () => {
    const policy =
      await w1bSelectionPolicyModule;

    const ranked =
      policy.rankRideMatchEligibleOffers(
        [
          w1bEvaluatedCandidate(
            "worst-090",
            1_500_000,
            false,
            2700,
            0,
            0,
            0,
          ),
          w1bEvaluatedCandidate(
            "worst-060",
            1_510_000,
            false,
            1800,
            540,
            1800,
            540,
          ),
          w1bEvaluatedCandidate(
            "worst-070",
            1_520_000,
            false,
            2100,
            0,
            0,
            0,
          ),
          w1bEvaluatedCandidate(
            "worst-080",
            1_530_000,
            false,
            2400,
            0,
            0,
            0,
          ),
        ],
      );

    assert.deepEqual(
      ranked.map(
        (item) =>
          item.candidate.rideId,
      ),
      [
        "worst-060",
        "worst-070",
        "worst-080",
      ],
    );
  },
);
