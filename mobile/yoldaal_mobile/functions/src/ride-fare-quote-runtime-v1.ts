import type {
  Firestore,
} from "firebase-admin/firestore";
import {
  HttpsError,
} from "firebase-functions/v2/https";
import {
  FARE_QUOTES_COLLECTION,
} from "./ride-fare-quote-orchestration-v1.js";
import type {
  FareQuoteProviderV1,
} from "./ride-fare-quote-orchestration-v1.js";
import {
  projectPassengerFareQuoteViewV1,
} from "./ride-fare-quote-passenger-view-v1.js";
import type {
  PassengerFareQuoteViewV1,
} from "./ride-fare-quote-passenger-view-v1.js";
import {
  createFareQuoteProviderV1,
} from "./ride-fare-quote-provider-v1.js";
import type {
  FareQuoteRouteProviderV1,
} from "./ride-fare-quote-provider-v1.js";
import type {
  GoogleGeocodingFetchV1,
} from "./ride-tariff-zone-google-geocoding-v4-v1.js";
import {
  createFirestoreTariffZonePolicyResolverV1,
} from "./ride-tariff-zone-policy-repository-v1.js";
import {
  createTariffZoneRuntimeResolverV1,
} from "./ride-tariff-zone-runtime-composition-v1.js";

export type FareQuoteRuntimeDependenciesV1 = {
  firestore: Firestore;
  googleGeocodingApiKey: string;
  fetch: GoogleGeocodingFetchV1;
  computeRoute: FareQuoteRouteProviderV1;
};

const SHA256_HEX =
  /^[0-9a-f]{64}$/u;

const hasAsciiControlCharacter = (
  value: string,
): boolean =>
  value.split("").some((character) => {
    const codeUnit = character.charCodeAt(0);
    return codeUnit <= 31 || codeUnit === 127;
  });

const requirePassengerId = (
  value: string,
): string => {
  if (typeof value !== "string") {
    throw new HttpsError(
      "invalid-argument",
      "Fare quote request is invalid.",
      {reason: "fare_quote_passenger_id_invalid"},
    );
  }

  const normalized = value.trim();
  if (
    normalized.length === 0 ||
    normalized.length > 128 ||
    hasAsciiControlCharacter(normalized)
  ) {
    throw new HttpsError(
      "invalid-argument",
      "Fare quote request is invalid.",
      {reason: "fare_quote_passenger_id_invalid"},
    );
  }
  return normalized;
};

const requireQuoteId = (
  value: string,
): string => {
  if (
    typeof value !== "string" ||
    !SHA256_HEX.test(value)
  ) {
    throw new HttpsError(
      "invalid-argument",
      "Fare quote request is invalid.",
      {reason: "fare_quote_id_invalid"},
    );
  }
  return value;
};

export const createFareQuoteRuntimeProviderV1 = (
  dependencies: FareQuoteRuntimeDependenciesV1,
): FareQuoteProviderV1 => {
  const resolveZoneFromEvidence =
    createFirestoreTariffZonePolicyResolverV1(
      dependencies.firestore,
    );

  const resolveTariffZone =
    createTariffZoneRuntimeResolverV1({
      googleGeocodingApiKey:
        dependencies.googleGeocodingApiKey,
      fetch: dependencies.fetch,
      resolveZoneFromEvidence,
    });

  return createFareQuoteProviderV1({
    firestore: dependencies.firestore,
    resolveTariffZone,
    computeRoute: dependencies.computeRoute,
  });
};

export const readPassengerFareQuoteViewV1 = async (
  firestore: Firestore,
  passengerIdRaw: string,
  quoteIdRaw: string,
): Promise<PassengerFareQuoteViewV1> => {
  const passengerId =
    requirePassengerId(passengerIdRaw);
  const quoteId =
    requireQuoteId(quoteIdRaw);

  let snapshot;
  try {
    snapshot = await firestore
      .collection(FARE_QUOTES_COLLECTION)
      .doc(quoteId)
      .get();
  } catch (_error: unknown) {
    throw new HttpsError(
      "unavailable",
      "Fare quote could not be loaded.",
      {reason: "fare_quote_view_read_unavailable"},
    );
  }

  if (!snapshot.exists) {
    throw new HttpsError(
      "failed-precondition",
      "Fare quote is unavailable.",
      {reason: "fare_quote_storage_inconsistent"},
    );
  }

  try {
    return projectPassengerFareQuoteViewV1(
      snapshot.data(),
      passengerId,
      quoteId,
    );
  } catch (_error: unknown) {
    throw new HttpsError(
      "internal",
      "Fare quote could not be verified.",
      {reason: "fare_quote_view_invalid"},
    );
  }
};
