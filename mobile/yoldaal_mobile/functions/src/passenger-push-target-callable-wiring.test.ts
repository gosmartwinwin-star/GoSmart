/* eslint-disable max-len */
import assert from "node:assert/strict";
import {test} from "node:test";
import {readFileSync} from "node:fs";

const indexSource =
  readFileSync(
    "src/index.ts",
    "utf8",
  );

const authoritySource =
  readFileSync(
    "src/passenger-push-target-authority.ts",
    "utf8",
  );

test(
  "index imports passenger push target authority exactly once",
  () => {
    assert.equal(
      (
        indexSource.match(
          /from "\.\/passenger-push-target-authority\.js"/gu,
        ) ?? []
      ).length,
      1,
    );

    assert.match(
      indexSource,
      /registerPassengerPushTarget as registerPassengerPushTargetAuthority/u,
    );
  },
);

test(
  "passenger push callable authenticates and delegates authenticated actor",
  () => {
    assert.match(
      indexSource,
      /export const registerPassengerPushTarget = onCall\(/u,
    );

    assert.match(
      indexSource,
      /Passenger push target requires authentication\./u,
    );

    assert.match(
      indexSource,
      /registerPassengerPushTargetAuthority\(\s*\{\s*firestore\s*\},\s*request\.auth\.uid,\s*request\.data,\s*\)/u,
    );
  },
);

test(
  "passenger target path is server-derived from authenticated uid",
  () => {
    assert.match(
      authoritySource,
      /\.collection\(\s*"passengerPushTargets",?\s*\)\s*\.doc\(authenticatedUid\)/u,
    );

    assert.match(
      authoritySource,
      /passengerId:\s*authenticatedUid/u,
    );

    assert.doesNotMatch(
      authoritySource,
      /driverPushTargets/u,
    );
  },
);
