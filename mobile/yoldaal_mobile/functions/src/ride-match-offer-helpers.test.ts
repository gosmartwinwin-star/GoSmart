import assert from "node:assert/strict";
import test from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  buildRideMatchOffer,
  isRideMatchMeasurementEligible,
  requireRideMatchOfferForAcceptance,
  rideMatchOfferDocumentId,
  RETURN_ROUTE_MATCH_MAX_DETOUR_METERS,
  RETURN_ROUTE_MATCH_MAX_DETOUR_SECONDS,
  RIDE_MATCH_OFFER_POLICY_VERSION,
} from "./ride-match-offer-helpers.js";

const now =
  Timestamp.fromMillis(1_800_000_000_000);

const measurement = (
  overrides: Partial<{
    pickupRouteIndex: number;
    dropoffRouteIndex: number;
    pickupDetourMeters: number;
    pickupDetourSeconds: number;
    dropoffDetourMeters: number;
    dropoffDetourSeconds: number;
  }> = {},
) => ({
  pickupRouteIndex: 2,
  dropoffRouteIndex: 8,
  pickupDetourMeters: 1200,
  pickupDetourSeconds: 240,
  dropoffDetourMeters: 1800,
  dropoffDetourSeconds: 360,
  ...overrides,
});

const build = (
  overrides: Partial<
    Parameters<typeof buildRideMatchOffer>[0]
  > = {},
) =>
  buildRideMatchOffer({
    driverId: "driver-profile-1",
    rideId: "ride-1",
    rideVersion: 1,
    returnRouteId: "return-route-1",
    routeExpiresAt:
      Timestamp.fromMillis(
        now.toMillis() + 600_000,
      ),
    now,
    measurement: measurement(),
    ...overrides,
  });

const reasonFrom = (
  callback: () => unknown,
): string | undefined => {
  try {
    callback();
  } catch (error: unknown) {
    assert.ok(error instanceof HttpsError);
    return (
      error.details as {
        reason?: string;
      }
    ).reason;
  }

  assert.fail("Expected HttpsError.");
};

test(
  "offer id is deterministic path-safe sha256",
  () => {
    const first =
      rideMatchOfferDocumentId(
        "driver-profile-1",
        "ride-1",
      );

    const second =
      rideMatchOfferDocumentId(
        "driver-profile-1",
        "ride-1",
      );

    assert.equal(first, second);
    assert.match(first, /^[a-f0-9]{64}$/u);

    assert.notEqual(
      first,
      rideMatchOfferDocumentId(
        "driver-profile-2",
        "ride-1",
      ),
    );
  },
);

test(
  "matching thresholds accept exact boundary",
  () => {
    assert.equal(
      isRideMatchMeasurementEligible(
        measurement({
          pickupDetourMeters:
            RETURN_ROUTE_MATCH_MAX_DETOUR_METERS,
          pickupDetourSeconds:
            RETURN_ROUTE_MATCH_MAX_DETOUR_SECONDS,
          dropoffDetourMeters:
            RETURN_ROUTE_MATCH_MAX_DETOUR_METERS,
          dropoffDetourSeconds:
            RETURN_ROUTE_MATCH_MAX_DETOUR_SECONDS,
        }),
      ),
      true,
    );
  },
);

test(
  "matching rejects distance time and direction violations",
  () => {
    assert.equal(
      isRideMatchMeasurementEligible(
        measurement({
          pickupDetourMeters:
            RETURN_ROUTE_MATCH_MAX_DETOUR_METERS + 1,
        }),
      ),
      false,
    );

    assert.equal(
      isRideMatchMeasurementEligible(
        measurement({
          dropoffDetourSeconds:
            RETURN_ROUTE_MATCH_MAX_DETOUR_SECONDS + 1,
        }),
      ),
      false,
    );

    assert.equal(
      isRideMatchMeasurementEligible(
        measurement({
          pickupRouteIndex: 8,
          dropoffRouteIndex: 2,
        }),
      ),
      false,
    );

    assert.equal(
      isRideMatchMeasurementEligible(
        measurement({
          pickupRouteIndex: 4,
          dropoffRouteIndex: 4,
        }),
      ),
      false,
    );
  },
);

test(
  "offer binds driver ride version route and policy",
  () => {
    const offer = build();

    assert.equal(
      offer.driverId,
      "driver-profile-1",
    );
    assert.equal(offer.rideId, "ride-1");
    assert.equal(offer.rideVersion, 1);
    assert.equal(
      offer.returnRouteId,
      "return-route-1",
    );
    assert.equal(
      offer.policyVersion,
      RIDE_MATCH_OFFER_POLICY_VERSION,
    );
    assert.equal(offer.status, "active");
    assert.equal(offer.consumedAt, null);
  },
);

test(
  "offer ttl is capped by route expiry",
  () => {
    const routeExpiresAt =
      Timestamp.fromMillis(
        now.toMillis() + 30_000,
      );

    const offer = build({
      routeExpiresAt,
      ttlSeconds: 120,
    });

    assert.equal(
      offer.expiresAt.toMillis(),
      routeExpiresAt.toMillis(),
    );
  },
);

test(
  "eligible active offer is accepted",
  () => {
    const offer = build();

    const accepted =
      requireRideMatchOfferForAcceptance(
        offer,
        {
          driverId: "driver-profile-1",
          rideId: "ride-1",
          rideVersion: 1,
          activeReturnRouteId:
            "return-route-1",
          now: Timestamp.fromMillis(
            now.toMillis() + 1000,
          ),
        },
      );

    assert.deepEqual(accepted, offer);
  },
);

test(
  "consumed offer is rejected",
  () => {
    const offer = {
      ...build(),
      status: "consumed" as const,
      consumedAt:
        Timestamp.fromMillis(
          now.toMillis() + 1000,
        ),
    };

    assert.equal(
      reasonFrom(() =>
        requireRideMatchOfferForAcceptance(
          offer,
          {
            driverId: "driver-profile-1",
            rideId: "ride-1",
            rideVersion: 1,
            activeReturnRouteId:
              "return-route-1",
            now: Timestamp.fromMillis(
              now.toMillis() + 2000,
            ),
          },
        )
      ),
      "ride_match_offer_not_active",
    );
  },
);

test(
  "offer identity mismatch is rejected",
  () => {
    const offer = build();

    assert.equal(
      reasonFrom(() =>
        requireRideMatchOfferForAcceptance(
          offer,
          {
            driverId: "driver-profile-2",
            rideId: "ride-1",
            rideVersion: 1,
            activeReturnRouteId:
              "return-route-1",
            now,
          },
        )
      ),
      "ride_match_offer_mismatch",
    );
  },
);

test(
  "ride version mismatch is stale",
  () => {
    assert.equal(
      reasonFrom(() =>
        requireRideMatchOfferForAcceptance(
          build(),
          {
            driverId: "driver-profile-1",
            rideId: "ride-1",
            rideVersion: 2,
            activeReturnRouteId:
              "return-route-1",
            now,
          },
        )
      ),
      "ride_match_offer_stale",
    );
  },
);

test(
  "active route replacement invalidates offer",
  () => {
    assert.equal(
      reasonFrom(() =>
        requireRideMatchOfferForAcceptance(
          build(),
          {
            driverId: "driver-profile-1",
            rideId: "ride-1",
            rideVersion: 1,
            activeReturnRouteId:
              "return-route-2",
            now,
          },
        )
      ),
      "ride_match_offer_route_changed",
    );
  },
);

test(
  "offer is expired at exact expiry instant",
  () => {
    const offer = build({
      ttlSeconds: 30,
    });

    assert.equal(
      reasonFrom(() =>
        requireRideMatchOfferForAcceptance(
          offer,
          {
            driverId: "driver-profile-1",
            rideId: "ride-1",
            rideVersion: 1,
            activeReturnRouteId:
              "return-route-1",
            now: offer.expiresAt,
          },
        )
      ),
      "ride_match_offer_expired",
    );
  },
);

test(
  "malformed or ineligible offer fails closed",
  () => {
    const malformed = {
      ...build(),
      measurement: measurement({
        pickupRouteIndex: 9,
        dropoffRouteIndex: 1,
      }),
    };

    assert.equal(
      reasonFrom(() =>
        requireRideMatchOfferForAcceptance(
          malformed,
          {
            driverId: "driver-profile-1",
            rideId: "ride-1",
            rideVersion: 1,
            activeReturnRouteId:
              "return-route-1",
            now,
          },
        )
      ),
      "ride_match_offer_invalid",
    );
  },
);

test(
  "builder rejects expired route and ineligible match",
  () => {
    assert.throws(
      () =>
        build({
          routeExpiresAt: now,
        }),
      TypeError,
    );

    assert.throws(
      () =>
        build({
          measurement: measurement({
            pickupDetourMeters:
              RETURN_ROUTE_MATCH_MAX_DETOUR_METERS + 1,
          }),
        }),
      TypeError,
    );
  },
);
