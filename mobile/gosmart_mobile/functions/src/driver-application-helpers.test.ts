import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  determineSubmissionTransition,
  normalizeFullName,
  normalizeTaxiStandName,
  normalizeVehiclePlate,
  validateApplicationPayload,
} from "./driver-application-helpers.js";

const reasonOf = (operation: () => unknown): string | undefined => {
  try {
    operation();
    return undefined;
  } catch (error: unknown) {
    assert.ok(error instanceof HttpsError);
    return (error.details as {reason?: string} | undefined)?.reason;
  }
};

test("1 Turkish full name is normalized", () =>
  assert.equal(normalizeFullName("  Çağrı   Şen  "), "Çağrı Şen"));
test("2 full name edges are trimmed", () =>
  assert.equal(normalizeFullName("  Ali  "), "Ali"));
test("3 full name spaces are collapsed", () =>
  assert.equal(normalizeFullName("Ali    Veli"), "Ali Veli"));
test("4 three-character full name is accepted", () =>
  assert.equal(normalizeFullName("Ali"), "Ali"));
test("5 two-character full name is rejected", () =>
  assert.equal(reasonOf(() => normalizeFullName("Al")), "invalid_full_name"));
test("6 80-character full name is accepted", () =>
  assert.equal(normalizeFullName("A".repeat(80)).length, 80));
test("7 81-character full name is rejected", () =>
  assert.equal(reasonOf(() => normalizeFullName("A".repeat(81))),
    "invalid_full_name"));
test("8 full name control character is rejected", () =>
  assert.equal(reasonOf(() => normalizeFullName("Ali\nVeli")),
    "invalid_full_name"));
test("9 non-string full name is rejected", () =>
  assert.equal(reasonOf(() => normalizeFullName(42)), "invalid_full_name"));

test("10 spaced plate is normalized", () =>
  assert.equal(normalizeVehiclePlate("06 ABC 123"), "06ABC123"));
test("11 dashed plate is normalized", () =>
  assert.equal(normalizeVehiclePlate("06-ABC-123"), "06ABC123"));
test("12 lowercase plate is uppercased", () =>
  assert.equal(normalizeVehiclePlate("34 abc 12"), "34ABC12"));
test("13 valid Ankara plate is accepted", () =>
  assert.equal(normalizeVehiclePlate("06A1234"), "06A1234"));
test("14 valid other-city plate is accepted", () =>
  assert.equal(normalizeVehiclePlate("81ZZ999"), "81ZZ999"));
test("15 province code 00 is rejected", () =>
  assert.equal(reasonOf(() => normalizeVehiclePlate("00ABC123")),
    "invalid_vehicle_plate"));
test("16 province code 82 is rejected", () =>
  assert.equal(reasonOf(() => normalizeVehiclePlate("82ABC123")),
    "invalid_vehicle_plate"));
test("17 plate without letters is rejected", () =>
  assert.equal(reasonOf(() => normalizeVehiclePlate("061234")),
    "invalid_vehicle_plate"));
test("18 plate without final digits is rejected", () =>
  assert.equal(reasonOf(() => normalizeVehiclePlate("06ABC")),
    "invalid_vehicle_plate"));
test("19 invalid plate character is rejected", () =>
  assert.equal(reasonOf(() => normalizeVehiclePlate("06AB@123")),
    "invalid_vehicle_plate"));
test("20 non-string plate is rejected", () =>
  assert.equal(reasonOf(() => normalizeVehiclePlate(6)),
    "invalid_vehicle_plate"));

test("21 null taxi stand is accepted", () =>
  assert.equal(normalizeTaxiStandName(null), null));
test("22 blank taxi stand becomes null", () =>
  assert.equal(normalizeTaxiStandName("   "), null));
test("23 taxi stand is normalized", () =>
  assert.equal(normalizeTaxiStandName("  Güven   Taksi "), "Güven Taksi"));
test("24 100-character taxi stand is accepted", () =>
  assert.equal(normalizeTaxiStandName("A".repeat(100))?.length, 100));
test("25 101-character taxi stand is rejected", () =>
  assert.equal(reasonOf(() => normalizeTaxiStandName("A".repeat(101))),
    "invalid_taxi_stand_name"));
test("26 taxi stand control character is rejected", () =>
  assert.equal(reasonOf(() => normalizeTaxiStandName("Güven\tTaksi")),
    "invalid_taxi_stand_name"));

const validPayload = {fullName: "Ali Veli", vehiclePlate: "06 ABC 123"};
test("27 payload with only allowed fields is accepted", () =>
  assert.deepEqual(validateApplicationPayload(validPayload), {
    fullName: "Ali Veli", vehiclePlate: "06ABC123", taxiStandName: null,
  }));
for (const [number, field] of [
  [28, "authUserId"], [29, "status"], [30, "serviceCity"],
  [31, "submittedAt"], [32, "unknownField"],
] as const) {
  test(`${number} payload field ${field} is rejected`, () =>
    assert.equal(reasonOf(() => validateApplicationPayload({
      ...validPayload, [field]: "value",
    })), "invalid_application_payload"));
}
test("33 non-map payload is rejected", () =>
  assert.equal(reasonOf(() => validateApplicationPayload([])),
    "invalid_application_payload"));

test("34 missing document starts at version 1", () => assert.deepEqual(
  determineSubmissionTransition(null), {submissionVersion: 1},
));
test("35 pending application is rejected", () =>
  assert.equal(reasonOf(() => determineSubmissionTransition({
    status: "pendingReview", submissionVersion: 1,
  })), "driver_application_exists"));
test("36 approved application is rejected", () =>
  assert.equal(reasonOf(() => determineSubmissionTransition({
    status: "approved", submissionVersion: 1,
  })), "driver_application_already_approved"));
test("37 rejected application increments version", () =>
  assert.deepEqual(determineSubmissionTransition({
    status: "rejected", submissionVersion: 2,
  }), {submissionVersion: 3}));
test("38 withdrawn application increments version", () =>
  assert.deepEqual(determineSubmissionTransition({
    status: "withdrawn", submissionVersion: 4,
  }), {submissionVersion: 5}));
test("39 unknown application status is rejected", () =>
  assert.equal(reasonOf(() => determineSubmissionTransition({
    status: "mystery", submissionVersion: 1,
  })), "driver_application_data_invalid"));
test("40 invalid submission version is rejected", () =>
  assert.equal(reasonOf(() => determineSubmissionTransition({
    status: "rejected", submissionVersion: 0,
  })), "driver_application_data_invalid"));
