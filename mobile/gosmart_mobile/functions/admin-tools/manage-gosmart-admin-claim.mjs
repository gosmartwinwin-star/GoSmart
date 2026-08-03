import {applicationDefault, deleteApp, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {
  buildUpdatedCustomClaims,
  classifyAdminClaimError,
  maskUidForConsole,
  parseAdminClaimCommand,
} from "../lib/admin-claim-management-helpers.js";

let app;
try {
  const command = parseAdminClaimCommand(process.argv.slice(2));
  console.log(`Target Firebase project: ${command.projectId}`);
  app = initializeApp({
    credential: applicationDefault(),
    projectId: command.projectId,
  }, "gosmart-admin-claim-cli");
  const auth = getAuth(app);
  const user = await auth.getUser(command.uid);
  const enable = command.action === "enable";
  const claims = buildUpdatedCustomClaims(user.customClaims, enable);
  const maskedUid = maskUidForConsole(command.uid);
  if (command.dryRun) {
    console.log(`Dry-run tamamlandı: ${command.action} planlandı (${maskedUid}); hiçbir claim yazılmadı.`);
  } else {
    await auth.setCustomUserClaims(command.uid, claims);
    console.log(`gosmartAdmin claim güncellendi (${maskedUid}).`);
    console.log("Kullanıcının yeni claim için kimlik tokenını yenilemesi gerekir.");
  }
} catch (error) {
  console.error(`Claim işlemi tamamlanamadı: ${classifyAdminClaimError(error)}`);
  process.exitCode = 1;
} finally {
  if (app) await deleteApp(app);
}
