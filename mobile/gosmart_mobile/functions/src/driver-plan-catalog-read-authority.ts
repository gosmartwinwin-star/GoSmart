/* eslint-disable max-len */
import {Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  DRIVER_PLAN_IDS,
  DriverPlanCatalog,
  DriverPlanId,
  loadDriverPlanCatalog,
} from "./driver-plan-catalog.js";
import {loadApprovedDriverId} from "./ride-driver-identity.js";

export type PublicDriverPlanCatalogEntry = {
  planId: DriverPlanId;
  enabled: boolean;
  amountMinor: number;
  currency: string;
};

export type PublicDriverPlanCatalog = {
  catalogVersion: string;
  plans: PublicDriverPlanCatalogEntry[];
};

export type DriverPlanCatalogReadDependencies = {
  firestore: Firestore;
  loadApprovedDriverId?: (
    firestore: Firestore,
    actorUid: string,
  ) => Promise<string>;
  loadCatalog?: (
    firestore: Firestore,
  ) => Promise<DriverPlanCatalog>;
};

const failure = (
  code: "invalid-argument" | "failed-precondition",
  reason: string,
): HttpsError => new HttpsError(
  code,
  "Driver plan catalog request failed.",
  {reason},
);

export const validateDriverPlanCatalogReadPayload = (
  value: unknown,
): void => {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value) ||
    Object.keys(value).length !== 0
  ) {
    throw failure(
      "invalid-argument",
      "invalid_driver_plan_catalog_read_payload",
    );
  }
};

const loadCatalogForRead = async (
  dependencies: DriverPlanCatalogReadDependencies,
): Promise<DriverPlanCatalog> => {
  const loader = dependencies.loadCatalog ?? loadDriverPlanCatalog;

  try {
    return await loader(dependencies.firestore);
  } catch (_error: unknown) {
    throw failure(
      "failed-precondition",
      "driver_plan_catalog_unavailable",
    );
  }
};

export const getDriverPlanCatalogForActor = async (
  dependencies: DriverPlanCatalogReadDependencies,
  actorUid: string,
  payload: unknown,
): Promise<PublicDriverPlanCatalog> => {
  validateDriverPlanCatalogReadPayload(payload);

  const approvedDriverLoader =
    dependencies.loadApprovedDriverId ?? loadApprovedDriverId;

  await approvedDriverLoader(
    dependencies.firestore,
    actorUid,
  );

  const catalog = await loadCatalogForRead(dependencies);

  return {
    catalogVersion: catalog.catalogVersion,
    plans: DRIVER_PLAN_IDS.map((planId) => {
      const plan = catalog.plans[planId];

      return {
        planId,
        enabled: plan.enabled,
        amountMinor: plan.amountMinor,
        currency: plan.currency,
      };
    }),
  };
};
/* eslint-enable max-len */
