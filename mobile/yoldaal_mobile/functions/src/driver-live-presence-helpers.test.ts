import assert from "node:assert/strict";
import test from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  buildDriverLivePresenceRecord,
  validateDriverLiveLocationInput,
} from "./driver-live-presence-helpers.js";

const reasonOf = (operation: () => unknown): string | undefined => {
  try {
    operation();
    return undefined;
  } catch (error: unknown) {
    assert.ok(error instanceof HttpsError);
    return (error.details as {reason?: string} | undefined)?.reason;
  }
};

test("accepts valid normal coordinates", () => {
  assert.deepEqual(
    validateDriverLiveLocationInput({latitude: 41.0082, longitude: 28.9784}),
    {latitude: 41.0082, longitude: 28.9784},
  );
});

test("accepts exact coordinate boundaries", () => {
  for (const input of [
    {latitude: -90, longitude: -180},
    {latitude: 90, longitude: 180},
  ]) {
    assert.deepEqual(validateDriverLiveLocationInput(input), input);
  }
});

test("rejects null non-object and array payloads", () => {
  for (const input of [null, undefined, "41,29", 41, [], [41, 29]]) {
    assert.equal(
      reasonOf(() => validateDriverLiveLocationInput(input)),
      "invalid_driver_live_location",
    );
  }
});

test("rejects missing latitude or longitude", () => {
  for (const input of [{latitude: 41}, {longitude: 29}, {}]) {
    assert.equal(
      reasonOf(() => validateDriverLiveLocationInput(input)),
      "invalid_driver_live_location",
    );
  }
});

test("rejects non-number NaN and infinite coordinates", () => {
  for (const input of [
    {latitude: "41", longitude: 29},
    {latitude: 41, longitude: "29"},
    {latitude: Number.NaN, longitude: 29},
    {latitude: 41, longitude: Number.POSITIVE_INFINITY},
    {latitude: Number.NEGATIVE_INFINITY, longitude: 29},
  ]) {
    assert.equal(
      reasonOf(() => validateDriverLiveLocationInput(input)),
      "invalid_driver_live_location",
    );
  }
});

test("rejects latitude outside valid range", () => {
  for (const latitude of [-90.0001, 90.0001]) {
    assert.equal(
      reasonOf(() =>
        validateDriverLiveLocationInput({latitude, longitude: 29})),
      "invalid_driver_live_location",
    );
  }
});

test("rejects longitude outside valid range", () => {
  for (const longitude of [-180.0001, 180.0001]) {
    assert.equal(
      reasonOf(() =>
        validateDriverLiveLocationInput({latitude: 41, longitude})),
      "invalid_driver_live_location",
    );
  }
});

test("rejects any extra client key", () => {
  assert.equal(
    reasonOf(() => validateDriverLiveLocationInput({
      latitude: 41,
      longitude: 29,
      extra: "injected",
    })),
    "invalid_driver_live_location",
  );
});

test("rejects client authority fields explicitly", () => {
  for (const extra of [
    {driverId: "driver-1"},
    {authUserId: "uid-1"},
    {updatedAt: 1000},
    {timestamp: 1000},
    {online: true},
  ]) {
    assert.equal(
      reasonOf(() => validateDriverLiveLocationInput({
        latitude: 41,
        longitude: 29,
        ...extra,
      })),
      "invalid_driver_live_location",
    );
  }
});

test("builds an exact four-field server record", () => {
  const updatedAt = Timestamp.fromMillis(1000);
  const location = validateDriverLiveLocationInput({
    latitude: 41.0082,
    longitude: 28.9784,
  });

  const record = buildDriverLivePresenceRecord(
    "driver-1",
    location,
    updatedAt,
  );

  assert.deepEqual(Object.keys(record).sort(), [
    "driverId",
    "latitude",
    "longitude",
    "updatedAt",
  ]);
  assert.deepEqual(record, {
    driverId: "driver-1",
    latitude: 41.0082,
    longitude: 28.9784,
    updatedAt,
  });
});

test("preserves trusted driver id and timestamp identity", () => {
  const updatedAt = Timestamp.fromMillis(2000);
  const record = buildDriverLivePresenceRecord(
    "driver-authoritative",
    {latitude: 40.9, longitude: 29.1},
    updatedAt,
  );

  assert.equal(record.driverId, "driver-authoritative");
  assert.equal(record.updatedAt, updatedAt);
});

test("server record exposes no online or auth user fields", () => {
  const record = buildDriverLivePresenceRecord(
    "driver-1",
    {latitude: 41, longitude: 29},
    Timestamp.fromMillis(3000),
  );

  assert.equal("online" in record, false);
  assert.equal("authUserId" in record, false);
  assert.equal("timestamp" in record, false);
});
