import {HttpsError} from "firebase-functions/v2/https";

export type DriverApplicationInput = {
  fullName: string;
  vehiclePlate: string;
  taxiStandName: string | null;
};

export type SubmissionTransition = {
  submissionVersion: number;
};

const invalidArgument = (reason: string) => new HttpsError(
  "invalid-argument",
  "Sürücü başvurusu bilgileri uygun değildir.",
  {reason},
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

export const normalizeVehiclePlate = (value: unknown): string => {
  if (typeof value !== "string") {
    throw invalidArgument("invalid_vehicle_plate");
  }
  const normalized = value.trim().replace(/[\s-]+/gu, "").toUpperCase();
  if (!/^(0[1-9]|[1-7][0-9]|8[01])[A-Z]{1,3}[0-9]{2,4}$/u.test(
    normalized,
  )) {
    throw invalidArgument("invalid_vehicle_plate");
  }
  return normalized;
};

export const normalizeTaxiStandName = (value: unknown): string | null => {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string" || hasControlCharacters(value)) {
    throw invalidArgument("invalid_taxi_stand_name");
  }
  const normalized = normalizeSpaces(value);
  if (normalized.length > 100) {
    throw invalidArgument("invalid_taxi_stand_name");
  }
  return normalized.length === 0 ? null : normalized;
};

export const validateApplicationPayload = (
  value: unknown,
): DriverApplicationInput => {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw invalidArgument("invalid_application_payload");
  }
  const input = value as Record<string, unknown>;
  const allowedKeys = ["fullName", "vehiclePlate", "taxiStandName"];
  if (Object.keys(input).some((key) => !allowedKeys.includes(key))) {
    throw invalidArgument("invalid_application_payload");
  }
  return {
    fullName: normalizeFullName(input.fullName),
    vehiclePlate: normalizeVehiclePlate(input.vehiclePlate),
    taxiStandName: normalizeTaxiStandName(input.taxiStandName),
  };
};

export const determineSubmissionTransition = (
  existingData: Record<string, unknown> | null,
): SubmissionTransition => {
  if (existingData === null) return {submissionVersion: 1};

  const status = existingData.status;
  if (status === "pendingReview") {
    throw new HttpsError(
      "failed-precondition",
      "Açık bir sürücü başvurusu zaten bulunmaktadır.",
      {reason: "driver_application_exists"},
    );
  }
  if (status === "approved") {
    throw new HttpsError(
      "failed-precondition",
      "Sürücü başvurusu daha önce onaylanmıştır.",
      {reason: "driver_application_already_approved"},
    );
  }
  const version = existingData.submissionVersion;
  if (
    (status !== "rejected" && status !== "withdrawn") ||
    typeof version !== "number" ||
    !Number.isInteger(version) ||
    version < 1
  ) {
    throw new HttpsError(
      "internal",
      "Sürücü başvurusu verileri doğrulanamadı.",
      {reason: "driver_application_data_invalid"},
    );
  }
  return {submissionVersion: version + 1};
};
