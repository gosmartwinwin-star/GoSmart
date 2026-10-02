/* eslint-disable max-len */
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";

const orchestration =
  readFileSync(
    "src/ride-lifecycle-orchestration.ts",
    "utf8",
  );

const indexSource =
  readFileSync(
    "src/index.ts",
    "utf8",
  );

const createRideSource = (() => {
  const start =
    orchestration.indexOf(
      "export const createRideRequestForPassenger",
    );
  const end =
    orchestration.indexOf(
      "export const cancelRideForActor",
      start,
    );

  assert.ok(start >= 0);
  assert.ok(end > start);
  return orchestration.slice(start, end);
})();

const createRideCallableSource = (() => {
  const start =
    indexSource.indexOf(
      "export const createRideRequest = onCall(",
    );
  const end =
    indexSource.indexOf(
      "export const getMyActiveRide = onCall(",
      start,
    );

  assert.ok(start >= 0);
  assert.ok(end > start);
  return indexSource.slice(start, end);
})();

test(
  "create ride loads quote binding with transaction reader",
  () => {
    assert.match(
      createRideSource,
      /createTransactionFareQuoteReaderV1\(\s*firestore,\s*transaction,\s*\)/u,
    );
    assert.match(
      createRideSource,
      /await loadRideFareBindingV1\([\s\S]{0,500}passengerId,[\s\S]{0,100}input/u,
    );
  },
);

test(
  "fare quote transaction read precedes create writes",
  () => {
    const bindingRead =
      createRideSource.indexOf(
        "const binding = await loadRideFareBindingV1(",
      );
    const firstWrite =
      createRideSource.indexOf(
        "transaction.create(",
      );

    assert.ok(bindingRead >= 0);
    assert.ok(firstWrite > bindingRead);
  },
);

test(
  "create ride persists fare-bound ride",
  () => {
    assert.match(
      createRideSource,
      /const persistedRide = buildFareBoundInitialRideV1\([\s\S]{0,260}binding,\s*\);/u,
    );
    assert.match(
      createRideSource,
      /transaction\.create\(rideRef, persistedRide\);/u,
    );
    assert.doesNotMatch(
      createRideSource,
      /transaction\.create\(rideRef, buildInitialRide/u,
    );
  },
);

test(
  "create result fare derives from persisted ride before operation write",
  () => {
    const attach =
      createRideSource.indexOf(
        "attachFareToCreateRideResultV1(",
      );
    const operationWrite =
      createRideSource.indexOf(
        "transaction.create(operationRef",
      );

    assert.ok(attach >= 0);
    assert.ok(operationWrite > attach);
    assert.match(
      createRideSource,
      /attachFareToCreateRideResultV1\(\s*baseResult,\s*persistedRide,\s*\)/u,
    );
    assert.match(
      createRideSource,
      /status: "completed", result, createdAt: now, updatedAt: now/u,
    );
  },
);

test(
  "completed operation replay remains the stored authoritative result",
  () => {
    const replayMatches =
      createRideSource.match(
        /return (?:data|operationData)\.result as Record<string, unknown>;/gu,
      ) ?? [];

    assert.equal(
      replayMatches.length,
      2,
    );
  },
);

test(
  "createRide callable enforces App Check without client fare authority",
  () => {
    assert.match(
      createRideCallableSource,
      /enforceAppCheck:\s*true/u,
    );
    assert.match(
      createRideCallableSource,
      /createRideRequestForPassenger/u,
    );
    assert.match(
      createRideCallableSource,
      /computeRoute:\s*computePublishedRoute/u,
    );
    assert.doesNotMatch(
      createRideCallableSource,
      /quoteId|tariffZoneId|tariffVersionId|farePolicyVersionId|yoldaalFareMinor/u,
    );
  },
);

test(
  "create ride index wiring does not own driver offer fare projection",
  () => {
    assert.doesNotMatch(
      indexSource,
      /attachFareToDriverOfferV1/u,
    );
  },
);
