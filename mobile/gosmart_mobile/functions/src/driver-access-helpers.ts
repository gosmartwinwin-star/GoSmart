import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

const precondition = (reason: string) => new HttpsError(
  "failed-precondition",
  "Sürücü erişim koşulları sağlanmıyor.",
  {reason},
);

export const validateProfileStatus = (status: unknown): void => {
  if (status === "approved") return;

  const reason = status === "pendingReview" ? "driver_approval_required" :
    status === "suspended" ? "driver_suspended" :
      status === "rejected" ? "driver_rejected" :
        status === "deactivated" ? "driver_deactivated" : null;

  if (reason === null) {
    throw new HttpsError("internal", "Sürücü profili doğrulanamadı.");
  }
  throw precondition(reason);
};

export const isActivePass = (
  data: Record<string, unknown>,
  now: Timestamp,
): boolean => {
  const activatedAt = data.activatedAt;
  const expiresAt = data.expiresAt;
  return data.status === "active" &&
    activatedAt instanceof Timestamp &&
    expiresAt instanceof Timestamp &&
    now.toMillis() >= activatedAt.toMillis() &&
    now.toMillis() < expiresAt.toMillis();
};

export const validateRouteValidity = (value: unknown): number => {
  if (
    typeof value !== "number" ||
    !Number.isInteger(value) ||
    value < 900 ||
    value > 14_400
  ) {
    throw new HttpsError(
      "invalid-argument",
      "Dönüş rotası geçerlilik süresi uygun değildir.",
      {reason: "invalid_route_validity"},
    );
  }
  return value;
};

export const requireExactKeys = (
  value: unknown,
  allowedKeys: readonly string[],
): Record<string, unknown> => {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "Geçerli rota verisi gereklidir.");
  }
  const record = value as Record<string, unknown>;
  if (Object.keys(record).some((key) => !allowedKeys.includes(key))) {
    throw new HttpsError("invalid-argument", "Desteklenmeyen rota alanı.");
  }
  return record;
};
