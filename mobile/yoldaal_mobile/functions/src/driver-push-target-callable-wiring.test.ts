/* eslint-disable max-len */
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";

const source = readFileSync(
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

test(
  "index imports bounded driver push target authority exactly once",
  () => {
    const moduleMatches =
      source.match(
        /from "\.\/driver-push-target-authority\.js"/gu,
      ) ?? [];

    assert.equal(
      moduleMatches.length,
      1,
    );

    assert.match(
      source,
      /registerDriverPushTarget as registerDriverPushTargetAuthority/u,
    );
  },
);

test(
  "registerDriverPushTarget callable authenticates and delegates exact actor payload",
  () => {
    const callable =
      callableSource(
        "registerDriverPushTarget",
      );

    for (const required of [
      "region: \"europe-west1\"",
      "timeoutSeconds: 15",
      "memory: \"256MiB\"",
      "minInstances: 0",
      "maxInstances: 3",
      "request.auth?.uid",
      "\"unauthenticated\"",
      "registerDriverPushTargetAuthority",
      "{firestore}",
      "request.auth.uid",
      "request.data",
    ]) {
      assert.ok(
        callable.includes(required),
        `missing callable seam: ${required}`,
      );
    }

    for (const forbidden of [
      "collection(\"driverPushTargets\")",
      "collection(\"installations\")",
      ".set(",
      ".create(",
      ".update(",
      ".delete(",
      "driverId:",
      "fid:",
      "platform:",
    ]) {
      assert.equal(
        callable.includes(forbidden),
        false,
        `forbidden callable authority: ${forbidden}`,
      );
    }
  },
);
/* eslint-enable max-len */
