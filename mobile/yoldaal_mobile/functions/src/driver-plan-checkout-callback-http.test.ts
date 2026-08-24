/* eslint-disable max-len, require-jsdoc */

import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";

const indexSource =
  readFileSync(
    "src/index.ts",
    "utf8",
  );

const authoritySource =
  readFileSync(
    "src/driver-plan-checkout-callback-authority.ts",
    "utf8",
  );

const httpSource = (
  name: string,
): string => {
  const marker =
    `export const ${name} = onRequest`;

  const start =
    indexSource.indexOf(marker);

  assert.notEqual(
    start,
    -1,
    `${name} HTTP function must be exported`,
  );

  const next =
    indexSource.indexOf(
      "\nexport const ",
      start + marker.length,
    );

  return indexSource.slice(
    start,
    next === -1 ?
      indexSource.length :
      next,
  );
};

test("checkout callback is POST-only and binds exact iyzico secrets", () => {
  const callback =
    httpSource(
      "driverPlanCheckoutCallback",
    );

  assert.match(
    callback,
    /region:\s*"europe-west1"/u,
  );

  assert.match(
    callback,
    /secrets:\s*\[\s*iyzicoApiKey,\s*iyzicoSecretKey,\s*\]/u,
  );

  assert.match(
    callback,
    /request\.method\s*!==\s*"POST"/u,
  );

  assert.match(
    callback,
    /response\.status\(405\)/u,
  );

  assert.doesNotMatch(
    callback,
    /request\.auth/u,
  );
});

test("checkout callback delegates only request body to server authority", () => {
  const callback =
    httpSource(
      "driverPlanCheckoutCallback",
    );

  assert.match(
    callback,
    /driverPlanCheckoutCallbackAuthority\(\s*\{\s*firestore,\s*retriever,\s*\},\s*request\.body,\s*\)/u,
  );

  assert.match(
    callback,
    /new IyzicoCheckoutFormDriverPlanPaymentProvider/u,
  );

  assert.match(
    callback,
    /iyzicoApiKey\.value\(\)/u,
  );

  assert.match(
    callback,
    /iyzicoSecretKey\.value\(\)/u,
  );

  assert.match(
    callback,
    /iyzicoApiBaseUrl\.value\(\)/u,
  );
});

test("callback response is generic and settlement stays outside index", () => {
  const callback =
    httpSource(
      "driverPlanCheckoutCallback",
    );

  assert.match(
    callback,
    /response\.status\(200\)\.json\(\{\s*success:\s*true,\s*\}\)/u,
  );

  assert.match(
    callback,
    /response\.status\(statusCode\)\.json\(\{\s*success:\s*false,\s*\}\)/u,
  );

  assert.equal(
    (
      indexSource.match(
        /settleDriverPlanPurchase/gu,
      ) ?? []
    ).length,
    0,
  );

  assert.match(
    authoritySource,
    /settleDriverPlanPurchase/u,
  );
});

test("Commit 20 does not add webhook handling", () => {
  assert.equal(
    (
      indexSource.match(
        /X-IYZ-SIGNATURE-V3|CHECKOUT_FORM_AUTH|iyziEventType/gu,
      ) ?? []
    ).length,
    0,
  );
});
