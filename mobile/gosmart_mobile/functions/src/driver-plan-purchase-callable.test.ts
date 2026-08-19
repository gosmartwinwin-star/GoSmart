/* eslint-disable max-len, require-jsdoc */
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";

const source = readFileSync("src/index.ts", "utf8");

const callableSource = (name: string): string => {
  const marker = `export const ${name} = onCall`;
  const start = source.indexOf(marker);
  assert.notEqual(start, -1, `${name} callable must be exported`);

  const next = source.indexOf("\nexport const ", start + marker.length);
  return source.slice(start, next === -1 ? source.length : next);
};

test("driver plan prepare callable requires auth and delegates actor identity", () => {
  assert.match(
    source,
    /prepareDriverPlanPurchase as prepareDriverPlanPurchaseAuthority/u,
  );

  const callable = callableSource("prepareDriverPlanPurchase");

  assert.match(callable, /region: "europe-west1"/u);
  assert.match(callable, /if \(!request\.auth\)/u);
  assert.match(callable, /"unauthenticated"/u);
  assert.match(
    callable,
    /prepareDriverPlanPurchaseAuthority\(\s*\{firestore\},\s*request\.auth\.uid,\s*request\.data,\s*\)/u,
  );
});

test("driver plan settlement authority remains server-only", () => {
  assert.equal(
    (source.match(/settleDriverPlanPurchase/gu) ?? []).length,
    0,
  );
});
