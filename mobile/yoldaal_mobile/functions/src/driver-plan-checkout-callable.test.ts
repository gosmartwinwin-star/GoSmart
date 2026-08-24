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

test("iyzico runtime uses secrets and non-secret string params", () => {
  assert.match(
    source,
    /defineSecret\(\s*"IYZICO_API_KEY"\s*,?\s*\)/u,
  );

  assert.match(
    source,
    /defineSecret\(\s*"IYZICO_SECRET_KEY"\s*,?\s*\)/u,
  );

  assert.match(
    source,
    /defineString\(\s*"IYZICO_API_BASE_URL"\s*,?\s*\)/u,
  );

  assert.match(
    source,
    /defineString\(\s*"IYZICO_CHECKOUT_CALLBACK_URL"\s*,?\s*\)/u,
  );
});

test("checkout callable requires authentication and binds exactly iyzico secrets", () => {
  const callable =
    callableSource(
      "initializeDriverPlanCheckout",
    );

  assert.match(
    callable,
    /region:\s*"europe-west1"/u,
  );

  assert.match(
    callable,
    /secrets:\s*\[\s*iyzicoApiKey,\s*iyzicoSecretKey,\s*\]/u,
  );

  assert.match(
    callable,
    /if\s*\(!request\.auth\?\.uid\)/u,
  );

  assert.match(
    callable,
    /auth\.getUser\(\s*request\.auth\.uid\s*,?\s*\)/u,
  );

  assert.match(
    callable,
    /request\.rawRequest\.ip/u,
  );
});

test("checkout callable constructs server-only provider and delegates actor identity", () => {
  const callable =
    callableSource(
      "initializeDriverPlanCheckout",
    );

  assert.match(
    callable,
    /new IyzicoCheckoutFormDriverPlanPaymentProvider/u,
  );

  assert.match(
    callable,
    /apiKey:\s*iyzicoApiKey\.value\(\)/u,
  );

  assert.match(
    callable,
    /secretKey:\s*iyzicoSecretKey\.value\(\)/u,
  );

  assert.match(
    callable,
    /baseUrl:\s*iyzicoApiBaseUrl\.value\(\)/u,
  );

  assert.match(
    callable,
    /callbackUrl:\s*iyzicoCheckoutCallbackUrl\.value\(\)/u,
  );

  assert.match(
    callable,
    /initializeDriverPlanCheckoutAuthority\(/u,
  );
});

test("checkout transport follows Commit 18 statusCode contract", () => {
  const callable =
    callableSource(
      "initializeDriverPlanCheckout",
    );

  assert.match(
    callable,
    /statusCode:\s*response\.status/u,
  );

  assert.match(
    callable,
    /body:\s*await response\.text\(\)/u,
  );
});

test("settlement stays server-only and callback is explicit HTTP entrypoint", () => {
  assert.equal(
    (
      source.match(
        /settleDriverPlanPurchase/gu,
      ) ?? []
    ).length,
    0,
  );

  assert.equal(
    (
      source.match(
        /export const driverPlanCheckoutCallback\s*=\s*onRequest/gu,
      ) ?? []
    ).length,
    1,
  );

  assert.doesNotMatch(
    source,
    /X-IYZ-SIGNATURE-V3|CHECKOUT_FORM_AUTH|iyziEventType/gu,
  );
});
