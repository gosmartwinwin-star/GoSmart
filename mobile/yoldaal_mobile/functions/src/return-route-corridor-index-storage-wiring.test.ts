import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import * as path from "node:path";
import test from "node:test";

type IndexField = {
  fieldPath: string;
  order?: string;
  arrayConfig?: string;
};

type IndexEntry = {
  collectionGroup: string;
  queryScope: string;
  fields: IndexField[];
};

type IndexConfig = {
  indexes: IndexEntry[];
};

const functionsRoot =
  process.cwd();

const mobileRoot =
  path.resolve(
    functionsRoot,
    "..",
  );

const source =
  readFileSync(
    path.join(
      functionsRoot,
      "src",
      "index.ts",
    ),
    "utf8",
  );

const rules =
  readFileSync(
    path.join(
      mobileRoot,
      "firestore.rules",
    ),
    "utf8",
  );

const indexConfig =
  JSON.parse(
    readFileSync(
      path.join(
        mobileRoot,
        "firestore.indexes.json",
      ),
      "utf8",
    ),
  ) as IndexConfig;

test(
  "return-route corridor production parameters are frozen",
  () => {
    assert.ok(
      source.includes(
        "const RETURN_ROUTE_CORRIDOR_INITIAL_PRECISION = 4;",
      ),
    );

    assert.ok(
      source.includes(
        "const RETURN_ROUTE_CORRIDOR_MAX_PREFIX_COUNT = 16;",
      ),
    );

    assert.ok(
      source.includes(
        "radiusMeters: RETURN_ROUTE_MATCH_MAX_DETOUR_METERS,",
      ),
    );
  },
);

test(
  "return-route publish reuses canonical decoder and corridor helper",
  () => {
    assert.ok(
      source.includes(
        "from \"./return-route-corridor-prefix-helpers.js\";",
      ),
    );

    assert.ok(
      source.includes(
        "corridorPrefixes = buildReturnRouteCorridorPrefixes({",
      ),
    );

    assert.ok(
      source.includes(
        "routePoints: decodeEncodedPolyline(",
      ),
    );

    assert.ok(
      source.includes(
        "routeMeasurement.encodedPolyline,",
      ),
    );
  },
);

test(
  "corridor index is written atomically with active return route",
  () => {
    assert.ok(
      source.includes(
        ".collection(\"driverReturnRouteCorridorIndexes\")",
      ),
    );

    assert.ok(
      source.includes(
        "transaction.set(corridorIndexReference, {",
      ),
    );

    assert.ok(
      source.includes(
        "returnRouteId: routeReference.id,",
      ),
    );

    assert.ok(
      source.includes(
        "corridorPrefixes,",
      ),
    );

    // R138 query semantics are frozen by the worker wiring test.
  },
);

test(
  "corridor Firestore index contract is exact",
  () => {
    const entries =
      indexConfig.indexes.filter(
        (entry) =>
          entry.collectionGroup ===
          "driverReturnRouteCorridorIndexes",
      );

    assert.equal(
      entries.length,
      1,
    );

    assert.equal(
      entries[0]?.queryScope,
      "COLLECTION",
    );

    assert.deepEqual(
      entries[0]?.fields,
      [
        {
          fieldPath:
            "corridorPrefixes",
          arrayConfig:
            "CONTAINS",
        },
        {
          fieldPath:
            "expiresAt",
          order:
            "ASCENDING",
        },
      ],
    );
  },
);

test(
  "corridor index collection is client-inaccessible",
  () => {
    assert.ok(
      rules.includes(
        "match /driverReturnRouteCorridorIndexes/{driverId} {",
      ),
    );

    const ruleStart =
      rules.indexOf(
        "match /driverReturnRouteCorridorIndexes/{driverId} {",
      );

    assert.notEqual(
      ruleStart,
      -1,
    );

    const ruleSlice =
      rules.slice(
        ruleStart,
        ruleStart + 180,
      );

    assert.ok(
      ruleSlice.includes(
        "allow read, write: if false;",
      ),
    );
  },
);
