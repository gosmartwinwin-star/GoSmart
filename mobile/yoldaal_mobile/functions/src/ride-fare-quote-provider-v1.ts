import {Firestore} from "firebase-admin/firestore";
import {
  loadApprovedFarePolicyVersionV1,
} from "./ride-fare-policy-repository-v1.js";
import {
  FareQuoteProviderV1,
} from "./ride-fare-quote-orchestration-v1.js";
import {
  FareQuoteRequestV1,
} from "./ride-fare-quote-persistence-v1.js";
import {
  buildFareQuoteSnapshotV1,
} from "./ride-fare-quote-v1.js";
import {
  loadApprovedTariffVersionV1,
} from "./ride-tariff-repository-v1.js";

export type FareQuoteTariffZoneResolverV1 = (
  input: FareQuoteRequestV1,
  quoteAtMillis: number,
) => Promise<string>;

export type FareQuoteRouteMeasurementV1 = {
  distanceMeters: number;
  durationSeconds: number;
};

export type FareQuoteRouteProviderV1 = (
  pickup: {
    latitude: number;
    longitude: number;
  },
  dropoff: {
    latitude: number;
    longitude: number;
  },
) => Promise<FareQuoteRouteMeasurementV1>;

export type FareQuoteProviderCompositionDependenciesV1 = {
  firestore: Firestore;
  resolveTariffZone:
    FareQuoteTariffZoneResolverV1;
  computeRoute: FareQuoteRouteProviderV1;
};

export const createFareQuoteProviderV1 = (
  dependencies:
    FareQuoteProviderCompositionDependenciesV1,
): FareQuoteProviderV1 =>
  async (
    input,
    quoteId,
    quotedAtMillis,
  ) => {
    const tariffZoneId =
      await dependencies.resolveTariffZone(
        input,
        quotedAtMillis,
      );

    const [
      route,
      tariff,
      farePolicy,
    ] = await Promise.all([
      dependencies.computeRoute(
        input.pickup,
        input.dropoff,
      ),
      loadApprovedTariffVersionV1(
        dependencies.firestore,
        tariffZoneId,
        quotedAtMillis,
      ),
      loadApprovedFarePolicyVersionV1(
        dependencies.firestore,
        quotedAtMillis,
      ),
    ]);

    return buildFareQuoteSnapshotV1({
      quoteId,
      tariff,
      farePolicy,
      plannedDistanceMeters:
        route.distanceMeters,
      plannedDurationSeconds:
        route.durationSeconds,
      quotedAtMillis,
    });
  };
