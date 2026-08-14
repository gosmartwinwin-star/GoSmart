/* eslint-disable max-len */
import {initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {
  assertLocalFixtureTarget,
  buildDriverFixture,
  FIXTURE_DRIVER_ID,
  FIXTURE_DRIVER_UID,
  FIXTURE_PASSENGER_ID,
  FIXTURE_RIDE_ID,
} from "./local-driver-fixture.js";

const argument = (name: string): string | undefined => {
  const index = process.argv.indexOf(`--${name}`);
  return index < 0 ? undefined : process.argv[index + 1];
};

const projectId = argument("project") ?? process.env.GCLOUD_PROJECT ?? "demo-gosmart";
const phoneNumber = argument("phone") ?? process.env.GOSMART_FIXTURE_PHONE;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099";
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";

assertLocalFixtureTarget({projectId, authHost, firestoreHost});
if (!phoneNumber || !/^\+[1-9]\d{7,14}$/u.test(phoneNumber)) {
  throw new Error("Provide a synthetic E.164 phone via --phone or GOSMART_FIXTURE_PHONE.");
}
process.env.FIREBASE_AUTH_EMULATOR_HOST = authHost;
process.env.FIRESTORE_EMULATOR_HOST = firestoreHost;

const main = async (): Promise<void> => {
  const app = initializeApp({projectId});
  const auth = getAuth(app);
  try {
    await auth.getUser(FIXTURE_DRIVER_UID);
    await auth.updateUser(FIXTURE_DRIVER_UID, {phoneNumber, disabled: false});
  } catch (error: unknown) {
    if ((error as {code?: string}).code !== "auth/user-not-found") throw error;
    await auth.createUser({uid: FIXTURE_DRIVER_UID, phoneNumber});
  }

  const fixture = buildDriverFixture();
  const firestore = getFirestore(app);
  const batch = firestore.batch();
  batch.set(firestore.collection("driverProfiles").doc(FIXTURE_DRIVER_ID),
    fixture.driverProfile);
  batch.set(firestore.collection("driverAccessPasses").doc("fixture_driver_pass"),
    fixture.accessPass);
  batch.set(firestore.collection("rides").doc(FIXTURE_RIDE_ID), fixture.ride);
  batch.set(firestore.collection("driverActiveRides").doc(FIXTURE_DRIVER_ID),
    fixture.driverActiveRide);
  batch.set(firestore.collection("passengerActiveRides").doc(FIXTURE_PASSENGER_ID),
    fixture.passengerActiveRide);
  await batch.commit();
  console.log(`Seeded ${FIXTURE_RIDE_ID} for ${FIXTURE_DRIVER_UID} in ${projectId}.`);
};

void main();
