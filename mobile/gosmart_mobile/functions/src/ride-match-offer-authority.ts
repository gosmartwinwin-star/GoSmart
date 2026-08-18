import {
  DocumentReference,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  requireDriverAccessInTransaction,
} from "./driver-access-authority.js";
import {
  requireRideMatchOfferForAcceptance,
  rideMatchOfferDocumentId,
} from "./ride-match-offer-helpers.js";

export type RideMatchOfferAuthority = {
  offerRef: DocumentReference;
  returnRouteId: string;
};

type RequireAuthorityInput = {
  firestore: Firestore;
  transaction: Transaction;
  driverId: string;
  rideId: string;
  rideVersion: number;
  now: Timestamp;
};

const failure = (reason: string): HttpsError =>
  new HttpsError(
    "failed-precondition",
    "Yolculuk eşleşme koşulları sağlanmıyor.",
    {reason},
  );

const positiveInteger = (
  value: unknown,
): value is number =>
  typeof value === "number" &&
  Number.isInteger(value) &&
  value > 0;

const nonEmptyString = (
  value: unknown,
): value is string =>
  typeof value === "string" &&
  value.length > 0;

export const requireRideMatchOfferAuthority = async (
  input: RequireAuthorityInput,
): Promise<RideMatchOfferAuthority> => {
  const {
    firestore,
    transaction,
    driverId,
    rideId,
    rideVersion,
    now,
  } = input;

  await requireDriverAccessInTransaction({
    firestore,
    transaction,
    driverId,
    now,
    failure,
  });

  const returnRouteLockRef = firestore
    .collection("driverActiveReturnRoutes")
    .doc(driverId);

  const offerRef = firestore
    .collection("driverRideMatchOffers")
    .doc(
      rideMatchOfferDocumentId(
        driverId,
        rideId,
      ),
    );

  const [
    returnRouteLock,
    offer,
  ] = await Promise.all([
    transaction.get(returnRouteLockRef),
    transaction.get(offerRef),
  ]);

  if (!returnRouteLock.exists) {
    throw failure(
      "active_return_route_required",
    );
  }

  const returnRouteId =
    returnRouteLock.get("routeId");

  const lockActivatedAt =
    returnRouteLock.get("activatedAt");

  const lockExpiresAt =
    returnRouteLock.get("expiresAt");

  if (
    !nonEmptyString(returnRouteId) ||
    !(lockActivatedAt instanceof Timestamp) ||
    !(lockExpiresAt instanceof Timestamp) ||
    lockExpiresAt.toMillis() <=
      lockActivatedAt.toMillis()
  ) {
    throw failure(
      "active_return_route_invalid",
    );
  }

  if (
    now.toMillis() <
      lockActivatedAt.toMillis() ||
    now.toMillis() >=
      lockExpiresAt.toMillis()
  ) {
    throw failure(
      "active_return_route_expired",
    );
  }

  const returnRouteRef = firestore
    .collection("driverReturnRoutes")
    .doc(returnRouteId);

  const returnRoute =
    await transaction.get(returnRouteRef);

  if (!returnRoute.exists) {
    throw failure(
      "active_return_route_invalid",
    );
  }

  const routeDriverId =
    returnRoute.get("driverId");

  const routeStatus =
    returnRoute.get("status");

  const routeActivatedAt =
    returnRoute.get("activatedAt");

  const routeExpiresAt =
    returnRoute.get("expiresAt");

  const routeDistanceMeters =
    returnRoute.get("routeDistanceMeters");

  const routeDurationSeconds =
    returnRoute.get("routeDurationSeconds");

  const encodedPolyline =
    returnRoute.get("encodedPolyline");

  if (
    routeDriverId !== driverId ||
    routeStatus !== "active" ||
    !(routeActivatedAt instanceof Timestamp) ||
    !(routeExpiresAt instanceof Timestamp) ||
    routeActivatedAt.toMillis() !==
      lockActivatedAt.toMillis() ||
    routeExpiresAt.toMillis() !==
      lockExpiresAt.toMillis() ||
    !positiveInteger(routeDistanceMeters) ||
    !positiveInteger(routeDurationSeconds) ||
    !nonEmptyString(encodedPolyline)
  ) {
    throw failure(
      "active_return_route_invalid",
    );
  }

  if (
    now.toMillis() <
      routeActivatedAt.toMillis() ||
    now.toMillis() >=
      routeExpiresAt.toMillis()
  ) {
    throw failure(
      "active_return_route_expired",
    );
  }

  if (!offer.exists) {
    throw failure(
      "ride_match_offer_required",
    );
  }

  requireRideMatchOfferForAcceptance(
    offer.data() ?? null,
    {
      driverId,
      rideId,
      rideVersion,
      activeReturnRouteId:
        returnRouteId,
      now,
    },
  );

  return {
    offerRef,
    returnRouteId,
  };
};
