/* eslint-disable max-len */
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";

import {
  isMidtripRouteChangeCompatible,
  rideDropoffChangeProposalId,
  validateRideDropoffChangeAcknowledgementPayload,
  validateRideDropoffChangeReadPayload,
  validateRideDropoffChangeProposalPayload,
} from "./ride-midtrip-route-change-authority.js";
import {
  rideOperationId,
} from "./ride-lifecycle-helpers.js";

const requestId =
  "midtrip_request_1234567890";

const reasonOf = (
  callback: () => unknown,
): string | null => {
  try {
    callback();
    return null;
  } catch (error: unknown) {
    if (!(error instanceof HttpsError)) {
      throw error;
    }

    const details =
      error.details as
        | Record<string, unknown>
        | undefined;

    return typeof details?.reason === "string" ?
      details.reason :
      null;
  }
};

test(
  "proposal payload accepts only frozen exact client input",
  () => {
    assert.deepEqual(
      validateRideDropoffChangeProposalPayload({
        rideId: "ride_1",
        newDropoff: {
          latitude: 41.01,
          longitude: 29.01,
          addressLabel: "  Yeni hedef  ",
        },
        requestId,
      }),
      {
        rideId: "ride_1",
        newDropoff: {
          latitude: 41.01,
          longitude: 29.01,
          addressLabel: "Yeni hedef",
        },
        requestId,
      },
    );

    assert.equal(
      reasonOf(() =>
        validateRideDropoffChangeProposalPayload({
          rideId: "ride_1",
          newDropoff: {
            latitude: 41.01,
            longitude: 29.01,
            addressLabel: "Yeni hedef",
          },
          requestId,
          driverId: "forbidden",
        })),
      "invalid_ride_dropoff_change_payload",
    );

    assert.equal(
      reasonOf(() =>
        validateRideDropoffChangeProposalPayload({
          rideId: "ride_1",
          newDropoff: {
            latitude: 41.01,
            longitude: 29.01,
            addressLabel: "Yeni hedef",
          },
          requestId,
          compatible: true,
        })),
      "invalid_ride_dropoff_change_payload",
    );
  },
);

test(
  "ack payload accepts only rideId proposalId decision requestId",
  () => {
    assert.deepEqual(
      validateRideDropoffChangeAcknowledgementPayload({
        rideId: "ride_1",
        proposalId: "proposal_1",
        decision: "accept",
        requestId,
      }),
      {
        rideId: "ride_1",
        proposalId: "proposal_1",
        decision: "accept",
        requestId,
      },
    );

    assert.equal(
      reasonOf(() =>
        validateRideDropoffChangeAcknowledgementPayload({
          rideId: "ride_1",
          proposalId: "proposal_1",
          decision: "maybe",
          requestId,
        })),
      "invalid_route_change_decision",
    );

    assert.equal(
      reasonOf(() =>
        validateRideDropoffChangeAcknowledgementPayload({
          rideId: "ride_1",
          proposalId: "proposal_1",
          decision: "reject",
          requestId,
          passengerId: "forbidden",
        })),
      "invalid_ride_dropoff_change_ack_payload",
    );
  },
);

test(
  "proposal id uses frozen actor callable request id operation identity",
  () => {
    assert.equal(
      rideDropoffChangeProposalId(
        "actor_1",
        requestId,
      ),
      rideOperationId(
        "actor_1",
        "proposeRideDropoffChange",
        requestId,
      ),
    );
  },
);

test(
  "four frozen 3000m 900s endpoint gates are inclusive and independent",
  () => {
    const boundary = {
      pickupDetourMeters: 3000,
      pickupDetourSeconds: 900,
      dropoffDetourMeters: 3000,
      dropoffDetourSeconds: 900,
    };

    assert.equal(
      isMidtripRouteChangeCompatible(
        boundary,
      ),
      true,
    );

    for (const override of [
      {pickupDetourMeters: 3001},
      {pickupDetourSeconds: 901},
      {dropoffDetourMeters: 3001},
      {dropoffDetourSeconds: 901},
    ]) {
      assert.equal(
        isMidtripRouteChangeCompatible({
          ...boundary,
          ...override,
        }),
        false,
      );
    }
  },
);

test(
  "authority source uses frozen historical route and never active route lock",
  () => {
    const source =
      readFileSync(
        "src/ride-midtrip-route-change-authority.ts",
        "utf8",
      );

    assert.match(
      source,
      /\.collection\("driverReturnRoutes"\)/u,
    );

    assert.doesNotMatch(
      source,
      /driverActiveReturnRoutes/u,
    );

    assert.match(
      source,
      /\.collection\("routeChangeProposals"\)/u,
    );

    assert.match(
      source,
      /returnRouteId/u,
    );

    assert.match(
      source,
      /frozenRoute\.origin[\s\S]*ride\.pickup/u,
    );

    assert.match(
      source,
      /input\.newDropoff[\s\S]*frozenRoute\.destination/u,
    );
  },
);

test(
  "authority source freezes compatible pending accept reject audit semantics",
  () => {
    const source =
      readFileSync(
        "src/ride-midtrip-route-change-authority.ts",
        "utf8",
      );

    for (const signal of [
      "appliedCompatible",
      "pendingAcknowledgement",
      "acceptedIncompatible",
      "rejectedIncompatible",
      "rideDropoffChangedCompatible",
      "rideDropoffChangeProposed",
      "rideDropoffChangeAcceptedIncompatible",
      "rideDropoffChangeRejectedIncompatible",
    ]) {
      assert.equal(
        source.includes(signal),
        true,
        signal,
      );
    }

    assert.match(
      source,
      /requiresCounterpartyAcknowledgement/u,
    );

    assert.match(
      source,
      /counterpartyId/u,
    );

    assert.match(
      source,
      /baseRideVersion/u,
    );
  },
);

test(
  "accepted incompatible proposal writes immutable regime-end marker only",
  () => {
    const source =
      readFileSync(
        "src/ride-midtrip-route-change-authority.ts",
        "utf8",
      );

    assert.match(
      source,
      /yoldaalRegimeEnd:\s*\{/u,
    );

    assert.match(
      source,
      /incompatible_midtrip_dropoff_change/u,
    );

    assert.match(
      source,
      /proposalId:[\s\S]*endedAt:/u,
    );

    assert.doesNotMatch(
      source,
      /pricingVersion\s*:/u,
    );

    assert.doesNotMatch(
      source,
      /taximeterAmount|fareAmount|paymentAmount/u,
    );
  },
);
test(
  "read payload accepts only rideId proposalId",
  () => {
    assert.deepEqual(
      validateRideDropoffChangeReadPayload({
        rideId: "ride_1",
        proposalId: "proposal_1",
      }),
      {
        rideId: "ride_1",
        proposalId: "proposal_1",
      },
    );

    assert.equal(
      reasonOf(() =>
        validateRideDropoffChangeReadPayload({
          rideId: "ride_1",
          proposalId: "proposal_1",
          driverId: "forbidden",
        })),
      "invalid_ride_dropoff_change_read_payload",
    );

    assert.equal(
      reasonOf(() =>
        validateRideDropoffChangeReadPayload({
          rideId: "ride_1",
          proposalId: "proposal/invalid",
        })),
      "invalid_route_change_proposal_id",
    );
  },
);

test(
  "pending proposal read surface is counterparty-only and privacy-minimal",
  () => {
    const source =
      readFileSync(
        "src/ride-midtrip-route-change-authority.ts",
        "utf8",
      );

    const start =
      source.indexOf(
        "export const getPendingRideDropoffChangeProposalForActor",
      );

    const end =
      source.indexOf(
        "export const proposeRideDropoffChangeForActor",
        start,
      );

    assert.notEqual(start, -1);
    assert.notEqual(end, -1);

    const readSurface =
      source.slice(start, end);

    assert.match(
      readSurface,
      /pendingAcknowledgement/u,
    );

    assert.match(
      readSurface,
      /route_change_counterparty_required/u,
    );

    assert.match(
      readSurface,
      /ride\.participant\.reporterId/u,
    );

    assert.match(
      readSurface,
      /requestedDropoff/u,
    );

    assert.match(
      readSurface,
      /status:\s*"pendingAcknowledgement"/u,
    );

    assert.doesNotMatch(
      readSurface,
      /proposedRoute|pickupDetour|dropoffDetour|baseRideVersion|returnRouteId|driverId|fareAmount|paymentAmount/u,
    );
  },
);

test(
  "index exposes authenticated pending proposal read without routes client",
  () => {
    const source =
      readFileSync(
        "src/index.ts",
        "utf8",
      );

    const start =
      source.indexOf(
        "export const getPendingRideDropoffChangeProposal = onCall",
      );

    const end =
      source.indexOf(
        "export const getMyActiveDriverRide = onCall",
        start,
      );

    assert.notEqual(start, -1);
    assert.notEqual(end, -1);

    const callable =
      source.slice(start, end);

    assert.match(
      callable,
      /getPendingRideDropoffChangeProposalForActor/u,
    );

    assert.match(
      callable,
      /\{\s*firestore,\s*\}/u,
    );

    assert.doesNotMatch(
      callable,
      /routesClient/u,
    );
  },
);
