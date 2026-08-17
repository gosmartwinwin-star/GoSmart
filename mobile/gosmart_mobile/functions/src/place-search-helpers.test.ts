import assert from "node:assert/strict";
import test from "node:test";
import {
  validatePlaceAutocompleteInput,
  validatePlaceDetailsInput,
} from "./place-search-helpers.js";

test("valid autocomplete payload is normalized", () => {
  assert.deepEqual(
    validatePlaceAutocompleteInput({
      input: "  Taksim Meydan\u0131  ",
      sessionToken: "123e4567-e89b-42d3-a456-426614174000",
    }),
    {
      input: "Taksim Meydan\u0131",
      sessionToken: "123e4567-e89b-42d3-a456-426614174000",
    },
  );
});

test("autocomplete rejects injected keys", () => {
  assert.throws(
    () => validatePlaceAutocompleteInput({
      input: "Taksim",
      sessionToken: "123e4567-e89b-42d3-a456-426614174000",
      passengerId: "attacker",
    }),
    (error: unknown) =>
      (error as {code?: string}).code === "invalid-argument",
  );
});

test("autocomplete rejects short input", () => {
  assert.throws(
    () => validatePlaceAutocompleteInput({
      input: "Ta",
      sessionToken: "123e4567-e89b-42d3-a456-426614174000",
    }),
  );
});

test("autocomplete rejects invalid session token", () => {
  assert.throws(
    () => validatePlaceAutocompleteInput({
      input: "Taksim",
      sessionToken: "bad token with spaces",
    }),
  );
});

test("valid details payload is normalized", () => {
  assert.deepEqual(
    validatePlaceDetailsInput({
      placeId: "  ChIJExample_123  ",
      sessionToken: "123e4567-e89b-42d3-a456-426614174000",
    }),
    {
      placeId: "ChIJExample_123",
      sessionToken: "123e4567-e89b-42d3-a456-426614174000",
    },
  );
});

test("details rejects injected keys", () => {
  assert.throws(
    () => validatePlaceDetailsInput({
      placeId: "ChIJExample_123",
      sessionToken: "123e4567-e89b-42d3-a456-426614174000",
      latitude: 41.0,
    }),
  );
});

test("details rejects empty place id", () => {
  assert.throws(
    () => validatePlaceDetailsInput({
      placeId: "   ",
      sessionToken: "123e4567-e89b-42d3-a456-426614174000",
    }),
  );
});
