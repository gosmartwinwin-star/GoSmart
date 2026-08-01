import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {
  buildUpdatedCustomClaims,
  maskUidForConsole,
  parseAdminClaimCommand,
} from "../lib/admin-claim-management-helpers.js";

try {
  const command = parseAdminClaimCommand(process.argv.slice(2));
  const auth = getAuth(getApps()[0] ?? initializeApp());
  const user = await auth.getUser(command.uid);
  const claims = buildUpdatedCustomClaims(user.customClaims, command.enable);
  const maskedUid = maskUidForConsole(command.uid);
  if (command.dryRun) {
    console.log(`Dry-run tamamlandı (${maskedUid}); hiçbir claim yazılmadı.`);
  } else {
    await auth.setCustomUserClaims(command.uid, claims);
    console.log(`gosmartAdmin claim güncellendi (${maskedUid}).`);
    console.log("Kullanıcının yeni claim için kimlik tokenını yenilemesi gerekir.");
  }
} catch (_error) {
  console.error("Claim işlemi tamamlanamadı. UID, komut ve ADC yapılandırmasını doğrulayın.");
  process.exitCode = 1;
}
