/* eslint-disable max-len */
export const GOSMART_FIREBASE_PROJECT_ID = "gosmart-fd8f6";

export type AdminClaimCommand = {
  projectId: string;
  uid: string;
  action: "enable" | "disable";
  dryRun: boolean;
};

export const validateFirebaseProjectId = (value: unknown): string => {
  if (typeof value !== "string" ||
      value.trim() !== GOSMART_FIREBASE_PROJECT_ID) {
    throw new Error("invalid_firebase_project");
  }
  return value.trim();
};

export const validateTargetUid = (value: unknown): string => {
  if (typeof value !== "string" || value.trim().length === 0 ||
      value.trim().length > 128 || !/^[A-Za-z0-9_-]+$/u.test(value.trim())) {
    throw new Error("Geçerli bir Firebase Auth UID gereklidir.");
  }
  return value.trim();
};

export const parseAdminClaimCommand = (args: readonly string[]): AdminClaimCommand => {
  const allowed = new Set([
    "--project-id", "--uid", "--enable", "--disable", "--dry-run",
  ]);
  if (args.some((arg) => arg.startsWith("--") && !allowed.has(arg))) {
    throw new Error("Desteklenmeyen komut seçeneği.");
  }
  const projectIndexes = args.map((arg, index) =>
    arg === "--project-id" ? index : -1).filter((index) => index >= 0);
  const uidIndexes = args.map((arg, index) => arg === "--uid" ? index : -1)
    .filter((index) => index >= 0);
  if (projectIndexes.length !== 1) {
    throw new Error("Tam olarak bir Firebase project ID gereklidir.");
  }
  if (uidIndexes.length !== 1) throw new Error("Tam olarak bir UID gereklidir.");
  const enable = args.includes("--enable");
  const disable = args.includes("--disable");
  if (enable === disable) throw new Error("Enable veya disable seçilmelidir.");
  const consumed = new Set([
    projectIndexes[0], projectIndexes[0] + 1,
    uidIndexes[0], uidIndexes[0] + 1,
    args.indexOf(enable ? "--enable" : "--disable"),
  ]);
  const dryRunIndex = args.indexOf("--dry-run");
  if (dryRunIndex >= 0) consumed.add(dryRunIndex);
  if (consumed.has(args.length) || args.some((_arg, index) => !consumed.has(index))) {
    throw new Error("Komut argümanları geçerli değildir.");
  }
  return {
    projectId: validateFirebaseProjectId(args[projectIndexes[0] + 1]),
    uid: validateTargetUid(args[uidIndexes[0] + 1]),
    action: enable ? "enable" : "disable",
    dryRun: dryRunIndex >= 0,
  };
};

export const buildUpdatedCustomClaims = (claims: Record<string, unknown> | undefined,
  enable: boolean): Record<string, unknown> => {
  const updated = {...(claims ?? {})};
  if (enable) updated.gosmartAdmin = true;
  else delete updated.gosmartAdmin;
  return updated;
};

export const maskUidForConsole = (uid: string): string => {
  const value = validateTargetUid(uid);
  if (value.length <= 6) return `${value.slice(0, 1)}***${value.slice(-1)}`;
  return `${value.slice(0, 3)}***${value.slice(-3)}`;
};

export const classifyAdminClaimError = (error: unknown): string => {
  const candidate = error as {code?: unknown; message?: unknown};
  const code = String(candidate?.code ?? "").toLowerCase();
  const message = String(candidate?.message ?? "").toLowerCase();
  if (message === "invalid_firebase_project") return "invalid_firebase_project";
  if (code.includes("user-not-found")) return "auth_user_not_found";
  if (code.includes("permission") || message.includes("permission denied") ||
      message.includes("insufficient permission")) return "adc_permission_denied";
  if (code.includes("credential") || message.includes("default credentials")) {
    return "adc_not_available";
  }
  if (code.includes("project") || message.includes("project id")) {
    return "firebase_project_id_not_detected";
  }
  if (code.startsWith("app/") || message.includes("initialize")) {
    return "admin_sdk_initialization_failed";
  }
  return "admin_claim_operation_failed";
};
