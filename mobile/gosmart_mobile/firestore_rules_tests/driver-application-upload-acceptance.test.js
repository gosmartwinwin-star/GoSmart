import assert from "node:assert/strict";
import {createRequire} from "node:module";
import {after, before, test} from "node:test";

import {
  deleteApp as deleteClientApp,
  initializeApp as initializeClientApp,
} from "firebase/app";
import {
  connectAuthEmulator,
  getAuth as getClientAuth,
  getIdTokenResult,
  signInWithEmailAndPassword,
  signOut,
} from "firebase/auth";
import {
  connectStorageEmulator,
  getBytes,
  getStorage as getClientStorage,
  ref as storageRef,
  uploadBytes,
} from "firebase/storage";

const functionsRequire = createRequire(
  new URL("../functions/package.json", import.meta.url),
);

const {
  deleteApp: deleteAdminApp,
  initializeApp: initializeAdminApp,
} = functionsRequire("firebase-admin/app");

const {
  getAuth: getAdminAuth,
} = functionsRequire("firebase-admin/auth");

const {
  getFirestore,
  Timestamp,
} = functionsRequire("firebase-admin/firestore");

const {
  getStorage: getAdminStorage,
} = functionsRequire("firebase-admin/storage");

const projectId = "demo-gosmart";
const region = "europe-west1";
const bucket = `${projectId}.appspot.com`;

const requiredEnvironment = (name) => {
  const value = process.env[name]?.trim();

  if (!value) {
    throw new Error(`${name} is required.`);
  }

  return value;
};

const parseLoopbackAddress = (name, value) => {
  const normalized = value
    .replace(/^https?:\/\//u, "")
    .replace(/\/+$/u, "");

  const separator = normalized.lastIndexOf(":");

  if (separator <= 0) {
    throw new Error(`${name} is invalid.`);
  }

  const host = normalized.slice(0, separator);
  const port = Number(normalized.slice(separator + 1));

  if (
    host !== "127.0.0.1" &&
    host !== "localhost"
  ) {
    throw new Error(`${name} must use loopback.`);
  }

  if (
    !Number.isInteger(port) ||
    port <= 0 ||
    port > 65535
  ) {
    throw new Error(`${name} port is invalid.`);
  }

  return {host, port};
};

const authAddress = parseLoopbackAddress(
  "FIREBASE_AUTH_EMULATOR_HOST",
  requiredEnvironment("FIREBASE_AUTH_EMULATOR_HOST"),
);

const firestoreAddress = parseLoopbackAddress(
  "FIRESTORE_EMULATOR_HOST",
  requiredEnvironment("FIRESTORE_EMULATOR_HOST"),
);

const storageAddress = parseLoopbackAddress(
  "FIREBASE_STORAGE_EMULATOR_HOST",
  requiredEnvironment("FIREBASE_STORAGE_EMULATOR_HOST"),
);

const functionsAddress = parseLoopbackAddress(
  "FUNCTIONS_EMULATOR_HOST",
  process.env.FUNCTIONS_EMULATOR_HOST?.trim() ||
    "127.0.0.1:5001",
);

if (
  process.env.GCLOUD_PROJECT &&
  process.env.GCLOUD_PROJECT !== projectId
) {
  throw new Error("Unexpected emulator project.");
}

let sequence = 0;

const unique = (prefix) => {
  sequence += 1;

  return [
    prefix,
    process.pid,
    Date.now(),
    sequence,
  ].join("_");
};

const safeCallableError = (
  name,
  response,
  envelope,
) => {
  const error =
    envelope &&
    typeof envelope === "object" &&
    envelope.error &&
    typeof envelope.error === "object"
      ? envelope.error
      : {};

  const status =
    typeof error.status === "string"
      ? error.status
      : "unknown";

  const details =
    error.details &&
    typeof error.details === "object"
      ? error.details
      : {};

  const reason =
    typeof details.reason === "string"
      ? details.reason
      : "unknown";

  return new Error(
    `${name} failed http=${response.status} ` +
      `status=${status} reason=${reason}`,
  );
};

const callable = async (
  idToken,
  name,
  data,
) => {
  const response = await fetch(
    `http://${functionsAddress.host}:` +
      `${functionsAddress.port}/` +
      `${projectId}/${region}/${name}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${idToken}`,
      },
      body: JSON.stringify({data}),
    },
  );

  const envelope = await response.json();

  if (
    !response.ok ||
    !envelope ||
    typeof envelope !== "object" ||
    !("result" in envelope)
  ) {
    throw safeCallableError(
      name,
      response,
      envelope,
    );
  }

  return envelope.result;
};

const documents = [
  {
    type: "driverLicenseFront",
    contentType: "image/jpeg",
    bytes: new Uint8Array([0xff, 0xd8, 0xff, 0xd9]),
  },
  {
    type: "driverLicenseBack",
    contentType: "image/png",
    bytes: new Uint8Array([0x89, 0x50, 0x4e, 0x47]),
  },
  {
    type: "identityCardFront",
    contentType: "image/jpeg",
    bytes: new Uint8Array([0xff, 0xd8, 0x01, 0xd9]),
  },
  {
    type: "identityCardBack",
    contentType: "image/png",
    bytes: new Uint8Array([0x89, 0x50, 0x4e, 0x48]),
  },
  {
    type: "vehicleRegistration",
    contentType: "application/pdf",
    bytes: new Uint8Array([0x25, 0x50, 0x44, 0x46]),
  },
  {
    type: "driverProfilePhoto",
    contentType: "image/jpeg",
    bytes: new Uint8Array([0xff, 0xd8, 0x02, 0xd9]),
  },
  {
    type: "criminalRecord",
    contentType: "application/pdf",
    bytes: new Uint8Array([0x25, 0x50, 0x44, 0x47]),
  },
];

let adminApp;
let adminAuth;
let firestore;
let adminBucket;

let clientApp;
let clientAuth;
let clientStorage;

let createdUid = null;

before(() => {
  adminApp = initializeAdminApp(
    {
      projectId,
      storageBucket: bucket,
    },
    `driver-application-acceptance-admin-${process.pid}`,
  );

  adminAuth = getAdminAuth(adminApp);
  firestore = getFirestore(adminApp);
  adminBucket = getAdminStorage(adminApp).bucket(bucket);

  clientApp = initializeClientApp(
    {
      apiKey:
        "AIza00000000000000000000000000000000000",
      authDomain: `${projectId}.firebaseapp.com`,
      projectId,
      storageBucket: bucket,
    },
    `driver-application-acceptance-client-${process.pid}`,
  );

  clientAuth = getClientAuth(clientApp);

  connectAuthEmulator(
    clientAuth,
    `http://${authAddress.host}:${authAddress.port}`,
    {disableWarnings: true},
  );

  clientStorage = getClientStorage(clientApp);

  connectStorageEmulator(
    clientStorage,
    storageAddress.host,
    storageAddress.port,
  );

  assert.equal(
    firestoreAddress.host === "127.0.0.1" ||
      firestoreAddress.host === "localhost",
    true,
  );
});

after(async () => {
  if (clientAuth?.currentUser) {
    await signOut(clientAuth).catch(() => {});
  }

  if (createdUid) {
    await adminAuth
      .deleteUser(createdUid)
      .catch(() => {});
  }

  if (clientApp) {
    await deleteClientApp(clientApp);
  }

  if (adminApp) {
    await deleteAdminApp(adminApp);
  }
});

test(
  "real auth and Storage rules submit immutable driver application",
  async () => {
    const email =
      `${unique("driver_application")}@example.test`;

    const password =
      `GoSmart_${unique("password")}_A1`;

    const phoneSuffix =
      String(
        (
          Date.now() +
          process.pid +
          sequence
        ) % 10000000,
      ).padStart(7, "0");

    const phoneNumber =
      `+90555${phoneSuffix}`;

    const userRecord =
      await adminAuth.createUser({
        email,
        password,
        phoneNumber,
      });

    createdUid = userRecord.uid;

    const credential =
      await signInWithEmailAndPassword(
        clientAuth,
        email,
        password,
      );

    assert.equal(
      credential.user.uid,
      createdUid,
    );

    const tokenResult =
      await getIdTokenResult(
        credential.user,
        true,
      );

    const idToken =
      tokenResult.token;

    assert.equal(
      typeof idToken,
      "string",
    );

    assert.ok(
      idToken.length > 20,
    );

    for (const document of documents) {
      const path =
        `driverApplicationUploads/` +
        `${createdUid}/` +
        `${document.type}/current`;

      await uploadBytes(
        storageRef(
          clientStorage,
          path,
        ),
        document.bytes,
        {
          contentType:
            document.contentType,
          customMetadata: {
            documentType:
              document.type,
            ownerUid:
              createdUid,
          },
        },
      );
    }

    const result =
      await callable(
        idToken,
        "submitDriverApplication",
        {
          fullName:
            "Acceptance Driver",
          workType:
            "vehicleOwner",
          vehiclePlate:
            "34ABC123",
          vehicleBrand:
            "AcceptanceBrand",
          vehicleModel:
            "AcceptanceModel",
          vehicleModelYear:
            new Date().getUTCFullYear(),
          registrationOwnerType:
            "applicant",
          hasVehicleUseAuthorization:
            false,
          informationAccuracyAccepted:
            true,
          documentValidityNotificationAccepted:
            true,
          documentProcessingNoticeAccepted:
            true,
          kvkkNoticeAccepted:
            true,
          termsAccepted:
            true,
          marketingConsent:
            false,
        },
      );

    assert.ok(
      result &&
      typeof result === "object",
    );

    assert.equal(
      result.status,
      "pendingReview",
    );

    assert.equal(
      result.submissionVersion,
      1,
    );

    assert.equal(
      Number.isInteger(
        result.submittedAtMillis,
      ),
      true,
    );

    assert.equal(
      Number.isInteger(
        result.updatedAtMillis,
      ),
      true,
    );

    const applicationRef =
      firestore
        .collection("driverApplications")
        .doc(createdUid);

    const application =
      await applicationRef.get();

    assert.equal(
      application.exists,
      true,
    );

    assert.equal(
      application.get("authUserId"),
      createdUid,
    );

    assert.equal(
      application.get("status"),
      "pendingReview",
    );

    assert.equal(
      application.get("submissionVersion"),
      1,
    );

    assert.equal(
      application.get("vehiclePlate"),
      "34ABC123",
    );

    assert.equal(
      application.get("marketingConsent"),
      false,
    );

    assert.ok(
      application.get("submittedAt")
        instanceof Timestamp,
    );

    assert.ok(
      application.get("updatedAt")
        instanceof Timestamp,
    );

    const documentSetId =
      application.get("documentSetId");

    assert.equal(
      typeof documentSetId,
      "string",
    );

    assert.ok(
      documentSetId.length > 0,
    );

    const storedDocuments =
      await applicationRef
        .collection("documents")
        .get();

    assert.equal(
      storedDocuments.size,
      documents.length,
    );

    for (const expected of documents) {
      const snapshot =
        storedDocuments.docs.find(
          (item) =>
            item.id === expected.type,
        );

      assert.ok(
        snapshot,
        `${expected.type} Firestore record missing`,
      );

      assert.equal(
        snapshot.get("documentType"),
        expected.type,
      );

      assert.equal(
        snapshot.get("contentType"),
        expected.contentType,
      );

      assert.equal(
        snapshot.get("sizeBytes"),
        expected.bytes.length,
      );

      assert.equal(
        snapshot.get("reviewStatus"),
        "pendingReview",
      );

      assert.equal(
        snapshot.get("submissionVersion"),
        1,
      );

      assert.equal(
        snapshot.get("documentSetId"),
        documentSetId,
      );

      assert.ok(
        snapshot.get("uploadedAt")
          instanceof Timestamp,
      );

      const immutablePath =
        `driverApplicationSubmissions/` +
        `${createdUid}/` +
        `${documentSetId}/` +
        `${expected.type}`;

      assert.equal(
        snapshot.get("storagePath"),
        immutablePath,
      );

      const [
        immutableMetadata,
      ] =
        await adminBucket
          .file(immutablePath)
          .getMetadata();

      assert.equal(
        immutableMetadata.contentType,
        expected.contentType,
      );

      assert.equal(
        Number(
          immutableMetadata.size,
        ),
        expected.bytes.length,
      );

      assert.equal(
        immutableMetadata.metadata
          ?.documentType,
        expected.type,
      );

      assert.equal(
        immutableMetadata.metadata
          ?.ownerUid,
        createdUid,
      );

      await assert.rejects(
        getBytes(
          storageRef(
            clientStorage,
            immutablePath,
          ),
        ),
      );

      const stagingPath =
        `driverApplicationUploads/` +
        `${createdUid}/` +
        `${expected.type}/current`;

      const [
        stagingExists,
      ] =
        await adminBucket
          .file(stagingPath)
          .exists();

      assert.equal(
        stagingExists,
        false,
        `${expected.type} staging object must be consumed`,
      );
    }
  },
);