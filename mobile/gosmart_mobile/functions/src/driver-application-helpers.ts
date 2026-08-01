import {HttpsError} from "firebase-functions/v2/https";

export const REQUIRED_DOCUMENT_TYPES = [
  "driverLicenseFront", "driverLicenseBack", "identityCardFront",
  "identityCardBack", "vehicleRegistration", "driverProfilePhoto",
  "criminalRecord",
] as const;
export type DocumentType = typeof REQUIRED_DOCUMENT_TYPES[number];

const WORK_TYPES = ["vehicleOwner", "employedDriver", "shiftDriver"] as const;
const OWNER_TYPES = ["applicant", "otherIndividual", "company"] as const;

export type DriverApplicationInput = {
  fullName: string;
  email: string | null;
  driverTaxiStandName: string | null;
  driverTaxiStandAddress: string | null;
  workType: typeof WORK_TYPES[number];
  vehiclePlate: string;
  vehicleBrand: string;
  vehicleModel: string;
  vehicleModelYear: number;
  registrationOwnerType: typeof OWNER_TYPES[number];
  hasVehicleUseAuthorization: boolean;
  vehicleTaxiStandName: string | null;
  informationAccuracyAccepted: true;
  documentValidityNotificationAccepted: true;
  documentProcessingNoticeAccepted: true;
  kvkkNoticeAccepted: true;
  termsAccepted: true;
  marketingConsent: boolean;
};

const invalidArgument = (reason: string) => new HttpsError(
  "invalid-argument", "Sürücü başvurusu bilgileri uygun değildir.", {reason},
);
const hasControlCharacters = (value: string): boolean =>
  // eslint-disable-next-line no-control-regex
  /[\u0000-\u001f\u007f-\u009f]/u.test(value);
const normalizeSpaces = (value: string): string =>
  value.trim().replace(/\s+/gu, " ");

export const normalizeFullName = (value: unknown): string => {
  if (typeof value !== "string" || hasControlCharacters(value)) {
    throw invalidArgument("invalid_full_name");
  }
  const normalized = normalizeSpaces(value);
  if (normalized.length < 3 || normalized.length > 80) {
    throw invalidArgument("invalid_full_name");
  }
  return normalized;
};

export const normalizeOptionalEmail = (value: unknown): string | null => {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value !== "string" || hasControlCharacters(value)) {
    throw invalidArgument("invalid_email");
  }
  const normalized = value.trim();
  if (normalized.length === 0) return null;
  if (
    normalized.length > 254 ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/u.test(normalized)
  ) throw invalidArgument("invalid_email");
  return normalized;
};

export const normalizeOptionalText = (
  value: unknown, maximumLength: number, reason: string,
): string | null => {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string" || hasControlCharacters(value)) {
    throw invalidArgument(reason);
  }
  const normalized = normalizeSpaces(value);
  if (normalized.length > maximumLength) throw invalidArgument(reason);
  return normalized.length === 0 ? null : normalized;
};

export const normalizeTaxiStandName = (value: unknown): string | null =>
  normalizeOptionalText(value, 100, "invalid_taxi_stand_name");

export const normalizeVehiclePlate = (value: unknown): string => {
  if (typeof value !== "string") throw invalidArgument("invalid_vehicle_plate");
  const normalized = value.trim().replace(/[\s-]+/gu, "").toUpperCase();
  if (!/^(0[1-9]|[1-7][0-9]|8[01])[A-Z]{1,3}[0-9]{2,4}$/u.test(
    normalized,
  )) throw invalidArgument("invalid_vehicle_plate");
  return normalized;
};

const requiredText = (
  value: unknown, maximumLength: number, reason: string,
): string => {
  const normalized = normalizeOptionalText(value, maximumLength, reason);
  if (normalized === null) throw invalidArgument(reason);
  return normalized;
};

export const validateWorkType = (
  value: unknown,
): DriverApplicationInput["workType"] => {
  if (!WORK_TYPES.includes(value as typeof WORK_TYPES[number])) {
    throw invalidArgument("invalid_work_type");
  }
  return value as DriverApplicationInput["workType"];
};

export const validateRegistrationOwnerType = (
  value: unknown,
): DriverApplicationInput["registrationOwnerType"] => {
  if (!OWNER_TYPES.includes(value as typeof OWNER_TYPES[number])) {
    throw invalidArgument("invalid_registration_owner_type");
  }
  return value as DriverApplicationInput["registrationOwnerType"];
};

export const validateVehicleModelYear = (
  value: unknown, currentUtcYear = new Date().getUTCFullYear(),
): number => {
  if (typeof value !== "number" || !Number.isInteger(value) ||
      value < 1950 || value > currentUtcYear + 1) {
    throw invalidArgument("invalid_vehicle_model_year");
  }
  return value;
};

const declarationKeys = [
  "informationAccuracyAccepted", "documentValidityNotificationAccepted",
  "documentProcessingNoticeAccepted", "kvkkNoticeAccepted", "termsAccepted",
] as const;

export const validateRequiredDeclarations = (
  input: Record<string, unknown>,
): Pick<DriverApplicationInput, typeof declarationKeys[number]> => {
  if (declarationKeys.some((key) => input[key] !== true)) {
    throw invalidArgument("required_declarations_not_accepted");
  }
  return Object.fromEntries(declarationKeys.map((key) => [key, true])) as
    Pick<DriverApplicationInput, typeof declarationKeys[number]>;
};

export const validateApplicationPayload = (
  value: unknown, currentUtcYear?: number,
): DriverApplicationInput => {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw invalidArgument("invalid_application_payload");
  }
  const input = value as Record<string, unknown>;
  const allowed = [
    "fullName", "email", "driverTaxiStandName", "driverTaxiStandAddress",
    "workType", "vehiclePlate", "vehicleBrand", "vehicleModel",
    "vehicleModelYear", "registrationOwnerType", "hasVehicleUseAuthorization",
    "vehicleTaxiStandName", ...declarationKeys, "marketingConsent",
  ];
  if (Object.keys(input).some((key) => !allowed.includes(key))) {
    throw invalidArgument("invalid_application_payload");
  }
  const registrationOwnerType = validateRegistrationOwnerType(
    input.registrationOwnerType,
  );
  if (typeof input.hasVehicleUseAuthorization !== "boolean") {
    throw invalidArgument("vehicle_use_authorization_required");
  }
  if (registrationOwnerType !== "applicant" &&
      !input.hasVehicleUseAuthorization) {
    throw invalidArgument("vehicle_use_authorization_required");
  }
  if (input.marketingConsent !== undefined &&
      typeof input.marketingConsent !== "boolean") {
    throw invalidArgument("required_declarations_not_accepted");
  }
  return {
    fullName: normalizeFullName(input.fullName),
    email: normalizeOptionalEmail(input.email),
    driverTaxiStandName: normalizeTaxiStandName(input.driverTaxiStandName),
    driverTaxiStandAddress: normalizeOptionalText(
      input.driverTaxiStandAddress, 250, "invalid_taxi_stand_address",
    ),
    workType: validateWorkType(input.workType),
    vehiclePlate: normalizeVehiclePlate(input.vehiclePlate),
    vehicleBrand: requiredText(input.vehicleBrand, 50, "invalid_vehicle_brand"),
    vehicleModel: requiredText(input.vehicleModel, 80, "invalid_vehicle_model"),
    vehicleModelYear: validateVehicleModelYear(input.vehicleModelYear,
      currentUtcYear),
    registrationOwnerType,
    hasVehicleUseAuthorization: input.hasVehicleUseAuthorization,
    vehicleTaxiStandName: normalizeTaxiStandName(input.vehicleTaxiStandName),
    ...validateRequiredDeclarations(input),
    marketingConsent: input.marketingConsent ?? false,
  };
};

export const validateVerifiedPhone = (value: unknown): string => {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("failed-precondition",
      "Doğrulanmış telefon numarası gereklidir.",
      {reason: "verified_phone_required"});
  }
  return value.trim();
};

export const getRequiredDocumentTypes = (): readonly DocumentType[] =>
  REQUIRED_DOCUMENT_TYPES;
export const buildStagingDocumentPath = (uid: string, type: DocumentType) =>
  `driverApplicationUploads/${uid}/${type}/current`;
export const buildSubmissionDocumentPath = (
  uid: string, documentSetId: string, type: DocumentType,
) => `driverApplicationSubmissions/${uid}/${documentSetId}/${type}`;

export type DocumentMetadata = {
  contentType: string;
  sizeBytes: number;
  uploadedAtMillis: number;
  generation?: string;
};

export const validateDocumentMetadata = (
  type: DocumentType,
  metadata: {contentType?: unknown; size?: unknown; timeCreated?: unknown;
    generation?: unknown; metadata?: Record<string, unknown>},
  uid: string,
): DocumentMetadata => {
  const pdfAllowed = type === "vehicleRegistration" ||
    type === "criminalRecord";
  const allowed = pdfAllowed ? ["image/jpeg", "image/png", "application/pdf"] :
    ["image/jpeg", "image/png"];
  const size = typeof metadata.size === "string" ? Number(metadata.size) :
    metadata.size;
  const maximum = (type === "driverProfilePhoto" ? 5 : 10) * 1024 * 1024;
  const timestamp = typeof metadata.timeCreated === "string" ?
    Date.parse(metadata.timeCreated) : NaN;
  if (typeof metadata.contentType !== "string" ||
      !allowed.includes(metadata.contentType) || typeof size !== "number" ||
      !Number.isInteger(size) || size <= 0 || size > maximum ||
      !Number.isFinite(timestamp) ||
      (metadata.metadata?.documentType !== undefined &&
        metadata.metadata.documentType !== type) ||
      (metadata.metadata?.ownerUid !== undefined &&
        metadata.metadata.ownerUid !== uid)) {
    throw new HttpsError("failed-precondition",
      "Sürücü başvurusu belgesi geçersizdir.",
      {reason: "driver_application_document_invalid"});
  }
  return {contentType: metadata.contentType, sizeBytes: size,
    uploadedAtMillis: timestamp,
    ...(typeof metadata.generation === "string" ?
      {generation: metadata.generation} : {})};
};

export const determineSubmissionTransition = (
  existingData: Record<string, unknown> | null,
): {submissionVersion: number} => {
  if (existingData === null) return {submissionVersion: 1};
  if (existingData.status === "pendingReview") {
    throw new HttpsError(
      "failed-precondition", "Açık bir sürücü başvurusu bulunmaktadır.",
      {reason: "driver_application_exists"});
  }
  if (existingData.status === "approved") {
    throw new HttpsError(
      "failed-precondition", "Sürücü başvurusu daha önce onaylanmıştır.",
      {reason: "driver_application_already_approved"});
  }
  const version = existingData.submissionVersion;
  if ((existingData.status !== "rejected" &&
      existingData.status !== "withdrawn") || typeof version !== "number" ||
      !Number.isInteger(version) || version < 1) {
    throw new HttpsError(
      "internal", "Sürücü başvurusu verileri doğrulanamadı.",
      {reason: "driver_application_data_invalid"});
  }
  return {submissionVersion: version + 1};
};
