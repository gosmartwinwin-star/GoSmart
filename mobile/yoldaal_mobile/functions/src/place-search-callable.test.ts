import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import test from "node:test";

const source = readFileSync(
  resolve(__dirname, "../src/index.ts"),
  "utf8",
);

const callableSource = (name: string): string => {
  const marker = `export const ${name} = onCall`;
  const start = source.indexOf(marker);
  assert.notEqual(start, -1);

  const next = source.indexOf(
    "\nexport const ",
    start + marker.length,
  );

  return source.slice(
    start,
    next === -1 ? source.length : next,
  );
};

test("Places API key is declared as a secret", () => {
  assert.match(
    source,
    /defineSecret\(\s*"GOOGLE_PLACES_API_KEY"\s*,?\s*\)/,
  );

  assert.doesNotMatch(
    source,
    /AIza[A-Za-z0-9_-]{20,}/,
  );
});

test("Places callables require auth and bind only their secret", () => {
  for (const name of [
    "searchPlaces",
    "resolvePlace",
  ]) {
    const callable = callableSource(name);

    assert.match(
      callable,
      /region: "europe-west1"/,
    );
    assert.match(
      callable,
      /secrets: \[googlePlacesApiKey\]/,
    );
    assert.match(
      callable,
      /if \(!request\.auth\?\.uid\)/,
    );
    assert.match(
      callable,
      /"unauthenticated"/,
    );
    assert.match(
      callable,
      /googlePlacesApiKey\.value\(\)/,
    );
  }
});

test("secret is bound and read exactly by both Places callables", () => {
  assert.equal(
    (source.match(
      /secrets: \[googlePlacesApiKey\]/g,
    ) ?? []).length,
    2,
  );

  assert.equal(
    (source.match(
      /googlePlacesApiKey\.value\(\)/g,
    ) ?? []).length,
    2,
  );
});
