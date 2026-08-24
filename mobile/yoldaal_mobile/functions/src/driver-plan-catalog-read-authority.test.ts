/* eslint-disable max-len */
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {DriverPlanCatalog} from "./driver-plan-catalog.js";
import {
  getDriverPlanCatalogForActor,
  validateDriverPlanCatalogReadPayload,
} from "./driver-plan-catalog-read-authority.js";

const firestore = {} as Firestore;

const catalog = (): DriverPlanCatalog => ({
  catalogVersion: "catalog-v7",
  plans: {
    daily: {
      enabled: true,
      amountMinor: 0,
      currency: "TRY",
    },
    weekly: {
      enabled: false,
      amountMinor: 200,
      currency: "TRY",
    },
    monthly: {
      enabled: true,
      amountMinor: 300,
      currency: "TRY",
    },
    quarterly: {
      enabled: true,
      amountMinor: 400,
      currency: "TRY",
    },
  },
});

const reasonIs = (
  expected: string,
) => (error: unknown): boolean => {
  if (!(error instanceof HttpsError)) {
    return false;
  }

  return (
    error.details as Record<string, unknown> | undefined
  )?.reason === expected;
};

test("catalog read payload accepts only an exact empty object", () => {
  assert.doesNotThrow(() => {
    validateDriverPlanCatalogReadPayload({});
  });

  assert.throws(
    () => validateDriverPlanCatalogReadPayload(null),
    reasonIs("invalid_driver_plan_catalog_read_payload"),
  );

  assert.throws(
    () => validateDriverPlanCatalogReadPayload({
      planId: "daily",
    }),
    reasonIs("invalid_driver_plan_catalog_read_payload"),
  );

  assert.throws(
    () => validateDriverPlanCatalogReadPayload({
      amountMinor: 1,
      currency: "TRY",
    }),
    reasonIs("invalid_driver_plan_catalog_read_payload"),
  );
});

test("approved actor receives canonical authoritative public catalog", async () => {
  const actors: string[] = [];
  let catalogLoads = 0;

  const result = await getDriverPlanCatalogForActor(
    {
      firestore,
      loadApprovedDriverId: async (
        actualFirestore,
        actorUid,
      ) => {
        assert.equal(actualFirestore, firestore);
        actors.push(actorUid);
        return "driver-1";
      },
      loadCatalog: async (actualFirestore) => {
        assert.equal(actualFirestore, firestore);
        catalogLoads += 1;
        return catalog();
      },
    },
    "uid-1",
    {},
  );

  assert.deepEqual(actors, ["uid-1"]);
  assert.equal(catalogLoads, 1);

  assert.deepEqual(result, {
    catalogVersion: "catalog-v7",
    plans: [
      {
        planId: "daily",
        enabled: true,
        amountMinor: 0,
        currency: "TRY",
      },
      {
        planId: "weekly",
        enabled: false,
        amountMinor: 200,
        currency: "TRY",
      },
      {
        planId: "monthly",
        enabled: true,
        amountMinor: 300,
        currency: "TRY",
      },
      {
        planId: "quarterly",
        enabled: true,
        amountMinor: 400,
        currency: "TRY",
      },
    ],
  });

  assert.deepEqual(
    Object.keys(result).sort(),
    ["catalogVersion", "plans"],
  );

  for (const plan of result.plans) {
    assert.deepEqual(
      Object.keys(plan).sort(),
      ["amountMinor", "currency", "enabled", "planId"],
    );
  }
});

test("driver approval failure stops before catalog read", async () => {
  const identityFailure = new HttpsError(
    "permission-denied",
    "Driver is not approved.",
    {reason: "driver_profile_not_approved"},
  );

  let catalogLoads = 0;

  await assert.rejects(
    () => getDriverPlanCatalogForActor(
      {
        firestore,
        loadApprovedDriverId: async () => {
          throw identityFailure;
        },
        loadCatalog: async () => {
          catalogLoads += 1;
          return catalog();
        },
      },
      "uid-unapproved",
      {},
    ),
    (error: unknown) => error === identityFailure,
  );

  assert.equal(catalogLoads, 0);
});

test("missing or malformed catalog failure is sanitized and fails closed", async () => {
  await assert.rejects(
    () => getDriverPlanCatalogForActor(
      {
        firestore,
        loadApprovedDriverId: async () => "driver-1",
        loadCatalog: async () => {
          throw new TypeError("internal firestore/catalog detail");
        },
      },
      "uid-1",
      {},
    ),
    reasonIs("driver_plan_catalog_unavailable"),
  );
});

test("catalog read authority contains no purchase settlement or pass mutation", () => {
  const source = readFileSync(
    "src/driver-plan-catalog-read-authority.ts",
    "utf8",
  );

  assert.doesNotMatch(
    source,
    /driverPlanPurchaseOperations|driverPlanPaymentSettlements|driverAccessPasses/u,
  );

  assert.doesNotMatch(
    source,
    /prepareDriverPlanPurchase|settleDriverPlanPurchase/u,
  );
});
/* eslint-enable max-len */
