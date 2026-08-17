import assert from "node:assert/strict";
import {after, before, test} from "node:test";

import {
  deleteApp,
  initializeApp,
  type App,
} from "firebase-admin/app";
import {
  getAuth,
  type Auth,
} from "firebase-admin/auth";
import {
  getFirestore,
  Timestamp,
  type Firestore,
} from "firebase-admin/firestore";

/* eslint-disable max-len */

type JsonRecord = Record<string, unknown>;

type AuthSession = {
  uid: string;
  email: string;
  password: string;
  idToken: string;
};

type CallableSuccess = {
  ok: true;
  result: JsonRecord;
};

type CallableFailure = {
  ok: false;
  status: string;
  reason: string;
};

type CallableOutcome =
  CallableSuccess |
  CallableFailure;

const projectId = "demo-gosmart";
const region = "europe-west1";

const documentTypes = [
  "driverLicenseFront",
  "driverLicenseBack",
  "identityCardFront",
  "identityCardBack",
  "vehicleRegistration",
  "driverProfilePhoto",
  "criminalRecord",
] as const;

const requiredEnvironment = (
  name: string,
): string => {
  const value = process.env[name]?.trim();

  if (!value) {
    throw new Error(`${name} is required.`);
  }

  return value;
};

const normalizedHost = (
  value: string,
): string =>
  value
    .replace(/^https?:\/\//u, "")
    .replace(/\/+$/u, "");

const assertLoopbackHost = (
  name: string,
  value: string,
): string => {
  const host = normalizedHost(value);
  const separator = host.lastIndexOf(":");

  if (separator <= 0) {
    throw new Error(`${name} is invalid.`);
  }

  const hostname =
    host.slice(0, separator);

  const port =
    Number(host.slice(separator + 1));

  if (
    hostname !== "127.0.0.1" &&
    hostname !== "localhost"
  ) {
    throw new Error(
      `${name} must use loopback.`,
    );
  }

  if (
    !Number.isInteger(port) ||
    port <= 0 ||
    port > 65535
  ) {
    throw new Error(
      `${name} port is invalid.`,
    );
  }

  return host;
};

const authHost =
  assertLoopbackHost(
    "FIREBASE_AUTH_EMULATOR_HOST",
    requiredEnvironment(
      "FIREBASE_AUTH_EMULATOR_HOST",
    ),
  );

const firestoreHost =
  assertLoopbackHost(
    "FIRESTORE_EMULATOR_HOST",
    requiredEnvironment(
      "FIRESTORE_EMULATOR_HOST",
    ),
  );

const functionsHost =
  assertLoopbackHost(
    "FUNCTIONS_EMULATOR_HOST",
    process.env.FUNCTIONS_EMULATOR_HOST?.trim() ||
      "127.0.0.1:5001",
  );

if (
  process.env.GCLOUD_PROJECT &&
  process.env.GCLOUD_PROJECT !== projectId
) {
  throw new Error(
    "Unexpected Firebase project.",
  );
}

void firestoreHost;

let sequence = 0;

const unique = (
  label: string,
): string => {
  sequence += 1;

  return [
    label,
    process.pid,
    Date.now(),
    sequence,
  ].join("_");
};

const asRecord = (
  value: unknown,
  label: string,
): JsonRecord => {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value)
  ) {
    throw new Error(
      `${label} must be an object.`,
    );
  }

  return value as JsonRecord;
};

const authRequest = async (
  endpoint: string,
  body: JsonRecord,
): Promise<JsonRecord> => {
  const response = await fetch(
    `http://${authHost}/identitytoolkit.googleapis.com/v1/` +
      `${endpoint}?key=demo-api-key`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    },
  );

  const payload =
    asRecord(
      await response.json(),
      `${endpoint} response`,
    );

  if (!response.ok) {
    throw new Error(
      `${endpoint} failed in Auth emulator.`,
    );
  }

  return payload;
};

const signUp = async (
  label: string,
): Promise<AuthSession> => {
  const email =
    `${unique(label)}@example.test`;

  const password =
    `GoSmart_${unique("password")}_A1`;

  const payload =
    await authRequest(
      "accounts:signUp",
      {
        email,
        password,
        returnSecureToken: true,
      },
    );

  const uid = payload.localId;
  const idToken = payload.idToken;

  if (
    typeof uid !== "string" ||
    uid.length === 0 ||
    typeof idToken !== "string" ||
    idToken.length === 0
  ) {
    throw new Error(
      "Auth emulator sign-up response invalid.",
    );
  }

  return {
    uid,
    email,
    password,
    idToken,
  };
};

const signInAgain = async (
  session: AuthSession,
): Promise<AuthSession> => {
  const payload =
    await authRequest(
      "accounts:signInWithPassword",
      {
        email: session.email,
        password: session.password,
        returnSecureToken: true,
      },
    );

  const uid = payload.localId;
  const idToken = payload.idToken;

  if (
    uid !== session.uid ||
    typeof idToken !== "string" ||
    idToken.length === 0
  ) {
    throw new Error(
      "Auth emulator token refresh response invalid.",
    );
  }

  return {
    ...session,
    idToken,
  };
};

const callableOutcome = async (
  session: AuthSession,
  name: string,
  data: JsonRecord,
): Promise<CallableOutcome> => {
  const response = await fetch(
    `http://${functionsHost}/` +
      `${projectId}/${region}/${name}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization":
          `Bearer ${session.idToken}`,
      },
      body: JSON.stringify({data}),
    },
  );

  const envelope =
    asRecord(
      await response.json(),
      `${name} response`,
    );

  if (
    response.ok &&
    "result" in envelope
  ) {
    return {
      ok: true,
      result: asRecord(
        envelope.result,
        `${name} result`,
      ),
    };
  }

  const rawError =
    envelope.error;

  const error =
    typeof rawError === "object" &&
    rawError !== null &&
    !Array.isArray(rawError) ?
      rawError as JsonRecord :
      {};

  const rawDetails =
    error.details;

  const details =
    typeof rawDetails === "object" &&
    rawDetails !== null &&
    !Array.isArray(rawDetails) ?
      rawDetails as JsonRecord :
      {};

  return {
    ok: false,
    status:
      typeof error.status === "string" ?
        error.status :
        "unknown",
    reason:
      typeof details.reason === "string" ?
        details.reason :
        "unknown",
  };
};

const callable = async (
  session: AuthSession,
  name: string,
  data: JsonRecord,
): Promise<JsonRecord> => {
  const outcome =
    await callableOutcome(
      session,
      name,
      data,
    );

  if (!outcome.ok) {
    throw new Error(
      `${name} failed ` +
        `status=${outcome.status} ` +
        `reason=${outcome.reason}`,
    );
  }

  return outcome.result;
};

let app: App;
let auth: Auth;
let firestore: Firestore;

const createdUserIds: string[] = [];

before(() => {
  app = initializeApp(
    {projectId},
    `driver-application-admin-review-${process.pid}`,
  );

  auth = getAuth(app);
  firestore = getFirestore(app);
});

after(async () => {
  await Promise.allSettled(
    createdUserIds.map(
      (uid) => auth.deleteUser(uid),
    ),
  );

  if (app) {
    await deleteApp(app);
  }
});

test(
  "real admin claim reviews canonical driver application",
  async () => {
    const applicant =
      await signUp(
        "driver_review_applicant",
      );

    const admin =
      await signUp(
        "driver_review_admin",
      );

    createdUserIds.push(
      applicant.uid,
      admin.uid,
    );

    await auth.setCustomUserClaims(
      admin.uid,
      {
        gosmartAdmin: true,
      },
    );

    const claimedAdmin =
      await signInAgain(admin);

    const applicationId =
      applicant.uid;

    const documentSetId =
      unique("document_set");

    const submissionVersion = 1;

    const now =
      Timestamp.now();

    const applicationRef =
      firestore
        .collection(
          "driverApplications",
        )
        .doc(applicationId);

    const batch =
      firestore.batch();

    batch.set(
      applicationRef,
      {
        authUserId:
          applicationId,
        verifiedPhoneNumber:
          "+905550000000",
        fullName:
          "Admin Review Acceptance",
        email:
          null,
        driverTaxiStandName:
          null,
        driverTaxiStandAddress:
          null,
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
        vehicleTaxiStandName:
          null,
        status:
          "pendingReview",
        submittedAt:
          now,
        updatedAt:
          now,
        reviewedAt:
          null,
        rejectionReasonCode:
          null,
        reviewedByAdminUid:
          null,
        submissionVersion,
        documentSetId,
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

    for (
      const documentType
      of documentTypes
    ) {
      batch.set(
        applicationRef
          .collection("documents")
          .doc(documentType),
        {
          documentType,
          storagePath:
            "driverApplicationSubmissions/" +
            `${applicationId}/` +
            `${documentSetId}/` +
            `${documentType}`,
          contentType:
            "image/jpeg",
          sizeBytes:
            1,
          uploadedAt:
            now,
          reviewStatus:
            "pendingReview",
          reviewedAt:
            null,
          rejectionReasonCode:
            null,
          reviewedByAdminUid:
            null,
          documentSetId,
          submissionVersion,
          storageGeneration:
            "1",
        },
      );
    }

    await batch.commit();

    const firstDocumentPayload = {
      applicationId,
      submissionVersion,
      documentSetId,
      documentType:
        documentTypes[0],
      decision:
        "approve",
      reasonCode:
        null,
    };

    const applicantDenied =
      await callableOutcome(
        applicant,
        "reviewDriverApplicationDocument",
        firstDocumentPayload,
      );

    assert.equal(
      applicantDenied.ok,
      false,
    );

    if (!applicantDenied.ok) {
      assert.equal(
        applicantDenied.reason,
        "admin_access_required",
      );
    }

    const prematureApproval =
      await callableOutcome(
        claimedAdmin,
        "reviewDriverApplication",
        {
          applicationId,
          submissionVersion,
          documentSetId,
          decision:
            "approve",
          rejectionReasonCode:
            null,
        },
      );

    assert.equal(
      prematureApproval.ok,
      false,
    );

    if (!prematureApproval.ok) {
      assert.equal(
        prematureApproval.reason,
        "driver_application_documents_not_approved",
      );
    }

    let firstReviewedAtMillis:
      number | null = null;

    for (
      const documentType
      of documentTypes
    ) {
      const reviewed =
        await callable(
          claimedAdmin,
          "reviewDriverApplicationDocument",
          {
            applicationId,
            submissionVersion,
            documentSetId,
            documentType,
            decision:
              "approve",
            reasonCode:
              null,
          },
        );

      assert.equal(
        reviewed.applicationStatus,
        "pendingReview",
      );

      assert.equal(
        reviewed.documentStatus,
        "approved",
      );

      assert.equal(
        Number.isInteger(
          reviewed.reviewedAtMillis,
        ),
        true,
      );

      if (
        documentType ===
        documentTypes[0]
      ) {
        firstReviewedAtMillis =
          Number(reviewed.reviewedAtMillis);
      }
    }

    assert.notEqual(
      firstReviewedAtMillis,
      null,
    );

    const repeatedDocumentReview =
      await callable(
        claimedAdmin,
        "reviewDriverApplicationDocument",
        firstDocumentPayload,
      );

    assert.equal(
      repeatedDocumentReview
        .applicationStatus,
      "pendingReview",
    );

    assert.equal(
      repeatedDocumentReview
        .documentStatus,
      "approved",
    );

    assert.equal(
      repeatedDocumentReview
        .reviewedAtMillis,
      firstReviewedAtMillis,
    );

    const approved =
      await callable(
        claimedAdmin,
        "reviewDriverApplication",
        {
          applicationId,
          submissionVersion,
          documentSetId,
          decision:
            "approve",
          rejectionReasonCode:
            null,
        },
      );

    assert.equal(
      approved.status,
      "approved",
    );

    assert.equal(
      approved.driverProfileCreated,
      true,
    );

    assert.equal(
      Number.isInteger(
        approved.reviewedAtMillis,
      ),
      true,
    );

    const application =
      await applicationRef.get();

    assert.equal(
      application.exists,
      true,
    );

    assert.equal(
      application.get("status"),
      "approved",
    );

    assert.equal(
      application.get(
        "reviewedByAdminUid",
      ),
      admin.uid,
    );

    assert.equal(
      application.get(
        "rejectionReasonCode",
      ),
      null,
    );

    assert.ok(
      application.get("reviewedAt") instanceof
        Timestamp,
    );

    const storedDocuments =
      await applicationRef
        .collection("documents")
        .get();

    assert.equal(
      storedDocuments.size,
      documentTypes.length,
    );

    for (
      const snapshot
      of storedDocuments.docs
    ) {
      assert.equal(
        snapshot.get(
          "reviewStatus",
        ),
        "approved",
      );

      assert.equal(
        snapshot.get(
          "reviewedByAdminUid",
        ),
        admin.uid,
      );

      assert.equal(
        snapshot.get(
          "rejectionReasonCode",
        ),
        null,
      );

      assert.ok(
        snapshot.get("reviewedAt") instanceof
          Timestamp,
      );
    }

    const profile =
      await firestore
        .collection("driverProfiles")
        .doc(applicationId)
        .get();

    assert.equal(
      profile.exists,
      true,
    );

    assert.equal(
      profile.get("authUserId"),
      applicationId,
    );

    assert.equal(
      profile.get("status"),
      "approved",
    );

    assert.ok(
      profile.get("createdAt") instanceof
        Timestamp,
    );

    assert.ok(
      profile.get("approvedAt") instanceof
        Timestamp,
    );

    assert.equal(
      profile.get("suspendedAt"),
      null,
    );

    const passes =
      await firestore
        .collection(
          "driverAccessPasses",
        )
        .where(
          "driverId",
          "==",
          applicationId,
        )
        .get();

    assert.equal(
      passes.empty,
      true,
      "Application approval must not mint an access pass.",
    );

    const events =
      await firestore
        .collection(
          "driverApplicationReviewEvents",
        )
        .where(
          "applicationId",
          "==",
          applicationId,
        )
        .get();

    assert.equal(
      events.size,
      8,
      "Seven document approvals plus one application approval expected.",
    );

    const eventTypes =
      events.docs.map(
        (snapshot) =>
          snapshot.get("eventType"),
      );

    assert.equal(
      eventTypes.filter(
        (value) =>
          value ===
          "documentApproved",
      ).length,
      7,
    );

    assert.equal(
      eventTypes.filter(
        (value) =>
          value ===
          "applicationApproved",
      ).length,
      1,
    );

    for (
      const snapshot
      of events.docs
    ) {
      assert.equal(
        snapshot.get(
          "reviewerAuthUserId",
        ),
        admin.uid,
      );

      assert.equal(
        snapshot.get(
          "submissionVersion",
        ),
        submissionVersion,
      );

      assert.equal(
        snapshot.get(
          "documentSetId",
        ),
        documentSetId,
      );

      assert.ok(
        snapshot.get("createdAt") instanceof
          Timestamp,
      );
    }
  },
);

/* eslint-enable max-len */
