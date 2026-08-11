/* eslint-disable max-len */
import {Firestore, Query, QuerySnapshot, Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {validateProfileStatus} from "./driver-access-helpers.js";

type QueryReader = (query: Query) => Promise<QuerySnapshot>;

export const loadApprovedDriverId = async (firestore: Firestore, uid: string,
  reader?: QueryReader): Promise<string> => {
  const query = firestore.collection("driverProfiles")
    .where("authUserId", "==", uid).limit(2);
  const profiles = await (reader ?? ((value) => value.get()))(query);
  if (profiles.empty) {
    throw new HttpsError("permission-denied", "SÃ¼rÃ¼cÃ¼ yetkisi gereklidir.",
      {reason: "driver_profile_required"});
  }
  if (profiles.size > 1) {
    throw new HttpsError("failed-precondition", "SÃ¼rÃ¼cÃ¼ profili doÄŸrulanamadÄ±.",
      {reason: "duplicate_driver_profile"});
  }
  const profile = profiles.docs[0];
  validateProfileStatus(profile.get("status"));
  return profile.id;
};

export const loadApprovedDriverIdInTransaction = (firestore: Firestore,
  uid: string, transaction: Transaction): Promise<string> =>
  loadApprovedDriverId(firestore, uid, (query) => transaction.get(query));
