/* eslint-disable max-len, require-jsdoc */
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";

const source =
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
    source.indexOf(marker);

  assert.notEqual(
    start,
    -1,
    `${name} callable must be exported`,
  );

  const next =
    source.indexOf(
      "\nexport const ",
      start + marker.length,
    );

  return source.slice(
    start,
    next === -1 ?
      source.length :
      next,
  );
};

test("payment status callable is authenticated owner-scoped backend read", () => {
  const callable =
    callableSource(
      "getDriverPlanPaymentStatus",
    );

  assert.match(
    callable,
    /region:\s*"europe-west1"/u,
  );

  assert.match(
    callable,
    /timeoutSeconds:\s*15/u,
  );

  assert.match(
    callable,
    /memory:\s*"256MiB"/u,
  );

  assert.match(
    callable,
    /if\s*\(!request\.auth\)/u,
  );

  assert.match(
    callable,
    /getDriverPlanPaymentStatusAuthority\(\s*\{firestore\},\s*request\.auth\.uid,\s*request\.data,\s*\)/u,
  );
});

test("payment status callable binds no provider secrets or browser authority", () => {
  const callable =
    callableSource(
      "getDriverPlanPaymentStatus",
    );

  assert.doesNotMatch(
    callable,
    /secrets:|iyzico|provider|callbackUrl|auth\.getUser|rawRequest|paymentPageUrl/u,
  );

  assert.doesNotMatch(
    callable,
    /settleDriverPlanPurchase|driverPlanPaymentSettlements|driverAccessPasses/u,
  );
});

test("payment status authority import and export are unique", () => {
  assert.equal(
    (
      source.match(
        /getDriverPlanPaymentStatusForActor as getDriverPlanPaymentStatusAuthority/gu,
      ) ?? []
    ).length,
    1,
  );

  assert.equal(
    (
      source.match(
        /export const getDriverPlanPaymentStatus\s*=\s*onCall/gu,
      ) ?? []
    ).length,
    1,
  );
});
/* eslint-enable max-len, require-jsdoc */
