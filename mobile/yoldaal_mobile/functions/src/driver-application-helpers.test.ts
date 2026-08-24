import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  buildStagingDocumentPath, buildSubmissionDocumentPath,
  determineSubmissionTransition, getRequiredDocumentTypes,
  normalizeFullName, normalizeOptionalEmail, normalizeOptionalText,
  normalizeVehiclePlate, validateApplicationPayload,
  validateDocumentMetadata, validateRegistrationOwnerType,
  validateRequiredDeclarations, validateVehicleModelYear,
  validateVerifiedPhone, validateWorkType,
} from "./driver-application-helpers.js";

const reasonOf = (operation: () => unknown): string | undefined => {
  try {
    operation(); return undefined;
  } catch (error: unknown) {
    assert.ok(error instanceof HttpsError);
    return (error.details as {reason?: string} | undefined)?.reason;
  }
};
const declarations = {
  informationAccuracyAccepted: true,
  documentValidityNotificationAccepted: true,
  documentProcessingNoticeAccepted: true,
  kvkkNoticeAccepted: true,
  termsAccepted: true,
};
const payload = {
  fullName: "Çağrı Şen", workType: "vehicleOwner",
  vehiclePlate: "06 ABC 123", vehicleBrand: " Fiat ",
  vehicleModel: " Egea ", vehicleModelYear: 2020,
  registrationOwnerType: "applicant", hasVehicleUseAuthorization: false,
  ...declarations,
};

for (const [number, value] of [[1, "vehicleOwner"], [2, "employedDriver"],
  [3, "shiftDriver"]] as const) {
  test(`${number} accepts work type`, () =>
    assert.equal(validateWorkType(value), value));
}
test("4 rejects unknown work type", () => assert.equal(
  reasonOf(() => validateWorkType("unknown")), "invalid_work_type"));
for (const [number, value] of [[5, "applicant"], [6, "otherIndividual"],
  [7, "company"]] as const) {
  test(`${number} accepts owner type`, () =>
    assert.equal(validateRegistrationOwnerType(value), value));
}
test("8 rejects unknown owner type", () => assert.equal(reasonOf(() =>
  validateRegistrationOwnerType("unknown")),
"invalid_registration_owner_type"));

for (const [number, field] of [[9, "serviceCity"], [10, "authUserId"],
  [11, "verifiedPhoneNumber"], [12, "status"], [13, "documentSetId"],
  [14, "documents"], [15, "storagePath"], [16, "reviewStatus"],
  [17, "unknown"]] as const) {
  test(`${number} rejects ${field}`, () =>
    assert.equal(reasonOf(() => validateApplicationPayload({...payload,
      [field]: "x"}, 2026)), "invalid_application_payload"));
}

test("18 normalizes Turkish name", () => assert.equal(
  normalizeFullName("  Çağrı   Şen "), "Çağrı Şen"));
test("19 optional email accepts null", () => assert.equal(
  normalizeOptionalEmail(null), null));
test("20 accepts email", () => assert.equal(
  normalizeOptionalEmail(" a@example.com "), "a@example.com"));
test("21 rejects invalid email", () => assert.equal(reasonOf(() =>
  normalizeOptionalEmail("invalid")), "invalid_email"));
test("22 optional stand accepts null", () => assert.equal(
  normalizeOptionalText(null, 100, "invalid_taxi_stand_name"), null));
test("23 optional address accepts null", () => assert.equal(
  normalizeOptionalText(null, 250, "invalid_taxi_stand_address"), null));
test("24 rejects control characters", () => assert.equal(reasonOf(() =>
  normalizeOptionalText("bad\ntext", 100, "invalid_taxi_stand_name")),
"invalid_taxi_stand_name"));

test("25 normalizes plate", () => assert.equal(
  normalizeVehiclePlate("06 abc-123"), "06ABC123"));
test("26 accepts other province", () => assert.equal(
  normalizeVehiclePlate("81 ZZ 999"), "81ZZ999"));
test("27 normalizes brand", () => assert.equal(
  validateApplicationPayload(payload, 2026).vehicleBrand, "Fiat"));
test("28 normalizes model", () => assert.equal(
  validateApplicationPayload(payload, 2026).vehicleModel, "Egea"));
test("29 accepts valid year", () => assert.equal(
  validateVehicleModelYear(2026, 2026), 2026));
for (const [number, value] of [[30, 2020.5], [31, true], [32, 1949],
  [33, 2028]] as const) {
  test(`${number} rejects invalid year`, () =>
    assert.equal(reasonOf(() => validateVehicleModelYear(value, 2026)),
      "invalid_vehicle_model_year"));
}
test("34 applicant may deny authorization", () => assert.doesNotThrow(() =>
  validateApplicationPayload(payload, 2026)));
test("35 other owner with authorization accepted", () =>
  assert.doesNotThrow(() => validateApplicationPayload({...payload,
    registrationOwnerType: "otherIndividual",
    hasVehicleUseAuthorization: true}, 2026)));
for (const [number, owner] of (
  [[36, "otherIndividual"], [37, "company"]] as const
)) {
  test(`${number} non-applicant requires authorization`, () =>
    assert.equal(reasonOf(() => validateApplicationPayload({...payload,
      registrationOwnerType: owner}, 2026)),
    "vehicle_use_authorization_required"));
}
test("38 company with authorization accepted", () => assert.doesNotThrow(() =>
  validateApplicationPayload({...payload, registrationOwnerType: "company",
    hasVehicleUseAuthorization: true}, 2026)));

test("39 all declarations accepted", () => assert.deepEqual(
  validateRequiredDeclarations(declarations), declarations));
let declarationTest = 40;
for (const key of Object.keys(declarations)) {
  test(`${declarationTest++} rejects false declaration`, () => assert.equal(
    reasonOf(() => validateRequiredDeclarations({...declarations,
      [key]: false})), "required_declarations_not_accepted"));
}
test("45 rejects missing declaration", () => assert.equal(reasonOf(() =>
  validateRequiredDeclarations({...declarations, termsAccepted: undefined})),
"required_declarations_not_accepted"));
test("46 rejects non-bool declaration", () => assert.equal(reasonOf(() =>
  validateRequiredDeclarations({...declarations, termsAccepted: "yes"})),
"required_declarations_not_accepted"));
test("47 accepts false marketing", () => assert.equal(
  validateApplicationPayload({...payload, marketingConsent: false}, 2026)
    .marketingConsent, false));
test("48 accepts true marketing", () => assert.equal(
  validateApplicationPayload({...payload, marketingConsent: true}, 2026)
    .marketingConsent, true));
test("49 defaults marketing to false", () => assert.equal(
  validateApplicationPayload(payload, 2026).marketingConsent, false));

test("50 lists seven required documents", () => assert.equal(
  getRequiredDocumentTypes().length, 7));
const metadata = (contentType: string, size: number) => ({contentType,
  size: String(size), timeCreated: "2026-01-01T00:00:00.000Z",
  metadata: {documentType: "driverProfilePhoto", ownerUid: "user-a"}});
test("51 accepts profile JPEG", () => assert.doesNotThrow(() =>
  validateDocumentMetadata("driverProfilePhoto",
    metadata("image/jpeg", 5 * 1024 * 1024), "user-a")));
test("52 accepts profile PNG", () => assert.doesNotThrow(() =>
  validateDocumentMetadata("driverProfilePhoto",
    metadata("image/png", 1), "user-a")));
test("53 rejects profile PDF", () => assert.equal(reasonOf(() =>
  validateDocumentMetadata("driverProfilePhoto",
    metadata("application/pdf", 1), "user-a")),
"driver_application_document_invalid"));
for (const [number, type] of [[54, "vehicleRegistration"],
  [55, "criminalRecord"]] as const) {
  test(`${number} accepts PDF`, () =>
    assert.doesNotThrow(() => validateDocumentMetadata(type, {
      ...metadata("application/pdf", 1), metadata: {documentType: type,
        ownerUid: "user-a"}}, "user-a")));
}
test("56 rejects license PDF", () => assert.equal(reasonOf(() =>
  validateDocumentMetadata("driverLicenseFront", {
    ...metadata("application/pdf", 1), metadata: {
      documentType: "driverLicenseFront", ownerUid: "user-a"}}, "user-a")),
"driver_application_document_invalid"));
test("57 accepts 5 MiB photo", () => assert.doesNotThrow(() =>
  validateDocumentMetadata("driverProfilePhoto",
    metadata("image/jpeg", 5 * 1024 * 1024), "user-a")));
test("58 rejects oversized photo", () => assert.equal(reasonOf(() =>
  validateDocumentMetadata("driverProfilePhoto",
    metadata("image/jpeg", 5 * 1024 * 1024 + 1), "user-a")),
"driver_application_document_invalid"));
const licenseMetadata = (size: number) => ({contentType: "image/jpeg",
  size: String(size), timeCreated: "2026-01-01T00:00:00.000Z",
  metadata: {documentType: "driverLicenseFront", ownerUid: "user-a"}});
test("59 accepts 10 MiB document", () => assert.doesNotThrow(() =>
  validateDocumentMetadata("driverLicenseFront",
    licenseMetadata(10 * 1024 * 1024), "user-a")));
test("60 rejects oversized document", () => assert.equal(reasonOf(() =>
  validateDocumentMetadata("driverLicenseFront",
    licenseMetadata(10 * 1024 * 1024 + 1), "user-a")),
"driver_application_document_invalid"));
test("61 builds staging path", () => assert.equal(
  buildStagingDocumentPath("user-a", "criminalRecord"),
  "driverApplicationUploads/user-a/criminalRecord/current"));
test("62 builds immutable path", () => assert.equal(
  buildSubmissionDocumentPath("user-a", "set-a", "criminalRecord"),
  "driverApplicationSubmissions/user-a/set-a/criminalRecord"));

test("63 new submission starts at one", () => assert.deepEqual(
  determineSubmissionTransition(null), {submissionVersion: 1}));
test("64 pending submission rejected", () => assert.equal(reasonOf(() =>
  determineSubmissionTransition({status: "pendingReview",
    submissionVersion: 1})), "driver_application_exists"));
test("65 approved submission rejected", () => assert.equal(reasonOf(() =>
  determineSubmissionTransition({status: "approved", submissionVersion: 1})),
"driver_application_exists"));
test("66 rejected submission rejected", () => assert.equal(reasonOf(() =>
  determineSubmissionTransition({status: "rejected", submissionVersion: 2})),
"driver_application_exists"));
test("67 withdrawn submission rejected", () => assert.equal(reasonOf(() =>
  determineSubmissionTransition({status: "withdrawn", submissionVersion: 2})),
"driver_application_exists"));
test("68 unknown status rejected", () => assert.equal(reasonOf(() =>
  determineSubmissionTransition({status: "unknown", submissionVersion: 1})),
"driver_application_exists"));
test("69 invalid version rejected", () => assert.equal(reasonOf(() =>
  determineSubmissionTransition({status: "rejected", submissionVersion: 0})),
"driver_application_exists"));
test("70 missing phone rejected safely", () => assert.equal(reasonOf(() =>
  validateVerifiedPhone(null)), "verified_phone_required"));
