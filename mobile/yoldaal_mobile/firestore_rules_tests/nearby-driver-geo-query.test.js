import assert from "node:assert/strict";
import {createRequire} from "node:module";
import {after, before, test} from "node:test";

import {
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";

import {
  collection,
  doc,
  getDocs,
  orderBy,
  query,
  setDoc,
  where,
} from "firebase/firestore";

const require = createRequire(import.meta.url);

const {
  buildNearbyDriverGeoHashPrefixRange,
} = require(
  "../functions/lib/nearby-driver-geo-query-helpers.js",
);

const projectId =
  "demo-gosmart";

const collectionName =
  "_r56NearbyDriverGeoRangeVerification";

let testEnv;

before(async () => {
  testEnv =
    await initializeTestEnvironment({
      projectId,
    });
});

after(async () => {
  if (testEnv !== undefined) {
    await testEnv.cleanup();
  }
});

const seedValues = async (
  values,
) => {
  await testEnv.withSecurityRulesDisabled(
    async (context) => {
      const db =
        context.firestore();

      for (
        let index = 0;
        index < values.length;
        index += 1
      ) {
        await setDoc(
          doc(
            db,
            collectionName,
            `item-${index}`,
          ),
          {
            geohash: values[index],
          },
        );
      }
    },
  );
};

const queryRange = async (
  prefix,
) => {
  const range =
    buildNearbyDriverGeoHashPrefixRange(
      prefix,
    );

  let result;

  await testEnv.withSecurityRulesDisabled(
    async (context) => {
      const db =
        context.firestore();

      const snapshot =
        await getDocs(
          query(
            collection(
              db,
              collectionName,
            ),
            where(
              "geohash",
              ">=",
              range.startInclusive,
            ),
            where(
              "geohash",
              "<",
              range.endExclusive,
            ),
            orderBy(
              "geohash",
              "asc",
            ),
          ),
        );

      result =
        snapshot.docs.map(
          (item) =>
            item.data().geohash,
        );
    },
  );

  return result;
};
test(
  "Firestore range selects exactly the sxk97 geohash prefix",
  async () => {
    await seedValues([
      "sxk96z",
      "sxk97",
      "sxk970",
      "sxk973m6",
      "sxk97z",
      "sxk98",
    ]);

    assert.deepEqual(
      await queryRange(
        "sxk97",
      ),
      [
        "sxk97",
        "sxk970",
        "sxk973m6",
        "sxk97z",
      ],
    );
  },
);

test(
  "Firestore range honors numeric-character exclusive successor",
  async () => {
    await seedValues([
      "8zz",
      "9",
      "90",
      "9z",
      ":",
      ":0",
    ]);

    assert.deepEqual(
      await queryRange(
        "9",
      ),
      [
        "9",
        "90",
        "9z",
      ],
    );
  },
);

test(
  "Firestore range honors z to left-brace exclusive successor",
  async () => {
    await seedValues([
      "yzz",
      "z",
      "z0",
      "zz",
      "{",
      "{0",
    ]);

    assert.deepEqual(
      await queryRange(
        "z",
      ),
      [
        "z",
        "z0",
        "zz",
      ],
    );
  },
);
