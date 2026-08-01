/* eslint-disable max-len */
export type AdminClaimCommand = {uid: string; enable: boolean; dryRun: boolean};

export const validateTargetUid = (value: unknown): string => {
  if (typeof value !== "string" || value.trim().length === 0 ||
      value.trim().length > 128 || !/^[A-Za-z0-9_-]+$/u.test(value.trim())) {
    throw new Error("Geçerli bir Firebase Auth UID gereklidir.");
  }
  return value.trim();
};

export const parseAdminClaimCommand = (args: readonly string[]): AdminClaimCommand => {
  const allowed = new Set(["--uid", "--enable", "--disable", "--dry-run"]);
  if (args.some((arg) => arg.startsWith("--") && !allowed.has(arg))) {
    throw new Error("Desteklenmeyen komut seçeneği.");
  }
  const uidIndexes = args.map((arg, index) => arg === "--uid" ? index : -1)
    .filter((index) => index >= 0);
  if (uidIndexes.length !== 1) throw new Error("Tam olarak bir UID gereklidir.");
  const enable = args.includes("--enable");
  const disable = args.includes("--disable");
  if (enable === disable) throw new Error("Enable veya disable seçilmelidir.");
  return {uid: validateTargetUid(args[uidIndexes[0] + 1]), enable,
    dryRun: args.includes("--dry-run")};
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
