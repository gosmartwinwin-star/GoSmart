import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";

test("history callable authenticates and delegates actor identity", () => {
  const source = readFileSync("src/index.ts", "utf8");

  const start = source.indexOf(
    "export const getMyRideHistory",
  );
  const end = source.indexOf(
    "export const cancelRide",
    start,
  );

  assert.ok(start >= 0);
  assert.ok(end > start);

  const callable = source.slice(start, end);

  assert.match(callable, /if \(!request\.auth\)/u);
  assert.match(callable, /getRideHistoryForActor/u);
  assert.match(callable, /request\.auth\.uid/u);
  assert.match(callable, /request\.data/u);

  assert.doesNotMatch(
    callable,
    /request\.data\.(passengerId|driverId|uid|authUserId)/u,
  );
});

test("history query is bounded terminal and deterministic", () => {
  const source = readFileSync(
    "src/ride-history-service.ts",
    "utf8",
  );

  assert.match(
    source,
    /\.where\(participantField, "==", participantId\)/u,
  );
  assert.match(
    source,
    /\.where\("status", "in", TERMINAL_RIDE_STATUSES\)/u,
  );
  assert.match(
    source,
    /\.orderBy\("updatedAt", "desc"\)/u,
  );
  assert.match(
    source,
    /\.orderBy\(FieldPath\.documentId\(\), "desc"\)/u,
  );
  assert.match(
    source,
    /\.limit\(input\.pageSize \+ 1\)/u,
  );
  assert.match(
    source,
    /query\.startAfter/u,
  );
  assert.match(
    source,
    /serializeActiveRide\(document\.id, data\)/u,
  );
});

test("driver history identity does not require current approval", () => {
  const source = readFileSync(
    "src/ride-driver-identity.ts",
    "utf8",
  );

  const genericStart = source.indexOf(
    "export const loadDriverProfileId",
  );
  const approvedStart = source.indexOf(
    "export const loadApprovedDriverId",
  );
  const transactionStart = source.indexOf(
    "export const loadApprovedDriverIdInTransaction",
  );

  assert.ok(genericStart >= 0);
  assert.ok(approvedStart > genericStart);
  assert.ok(transactionStart > approvedStart);

  const generic = source.slice(
    genericStart,
    approvedStart,
  );
  const approved = source.slice(
    approvedStart,
    transactionStart,
  );

  assert.match(
    generic,
    /where\("authUserId", "==", uid\)/u,
  );
  assert.match(
    generic,
    /profiles\.size > 1/u,
  );
  assert.doesNotMatch(
    generic,
    /validateProfileStatus/u,
  );

  assert.match(
    approved,
    /validateProfileStatus/u,
  );
});

test("history has passenger and driver composite indexes", () => {
  const config = JSON.parse(
    readFileSync("../firestore.indexes.json", "utf8"),
  ) as {
    indexes: Array<{
      collectionGroup: string;
      queryScope: string;
      fields: Array<{
        fieldPath: string;
        order: string;
      }>;
    }>;
  };

  const expected = [
    ["passengerId", "status", "updatedAt", "__name__"],
    ["driverId", "status", "updatedAt", "__name__"],
  ];

  for (const fields of expected) {
    assert.ok(
      config.indexes.some((index) =>
        index.collectionGroup === "rides" &&
        index.queryScope === "COLLECTION" &&
        index.fields.map(
          (field) => field.fieldPath,
        ).join("|") === fields.join("|") &&
        index.fields[2].order === "DESCENDING" &&
        index.fields[3].order === "DESCENDING"
      ),
    );
  }
});
