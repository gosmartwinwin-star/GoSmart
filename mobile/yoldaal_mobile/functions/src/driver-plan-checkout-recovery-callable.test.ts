/* eslint-disable max-len, require-jsdoc */

import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";

const source =
  readFileSync(
    "src/driver-plan-payment-functions.ts",
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

test("checkout recovery callable is authenticated owner-scoped backend read", () => {
  const callable =
    callableSource(
      "getMyLatestDriverPlanPaymentStatus",
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
    /minInstances:\s*0/u,
  );

  assert.match(
    callable,
    /maxInstances:\s*3/u,
  );

  assert.match(
    callable,
    /if\s*\(!request\.auth\)/u,
  );

  assert.match(
    callable,
    /getLatestDriverPlanPaymentStatusAuthority\(\s*\{firestore\},\s*request\.auth\.uid,\s*request\.data,\s*\)/u,
  );
});

test("checkout recovery callable binds no provider secrets or payment mutation authority", () => {
  const callable =
    callableSource(
      "getMyLatestDriverPlanPaymentStatus",
    );

  assert.doesNotMatch(
    callable,
    /secrets:|iyzico|provider|callbackUrl|auth\.getUser|rawRequest|paymentPageUrl|conversationId|token/u,
  );

  assert.doesNotMatch(
    callable,
    /settleDriverPlanPurchase|driverPlanPaymentSettlements|driverAccessPasses|\.set\(|\.update\(|\.create\(|runTransaction/u,
  );
});

test("checkout recovery authority import and callable export are unique", () => {
  assert.equal(
    (
      source.match(
        /getMyLatestDriverPlanPaymentStatusForActor as\s+getLatestDriverPlanPaymentStatusAuthority/gu,
      ) ?? []
    ).length,
    1,
  );

  assert.equal(
    (
      source.match(
        /export const getMyLatestDriverPlanPaymentStatus\s*=\s*onCall/gu,
      ) ?? []
    ).length,
    1,
  );
});

/* eslint-enable max-len, require-jsdoc */
