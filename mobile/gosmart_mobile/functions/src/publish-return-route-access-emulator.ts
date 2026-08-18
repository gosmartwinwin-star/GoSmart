/* eslint-disable max-len */
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test, {after, beforeEach} from "node:test";
import {
  deleteApp,
  initializeApp,
} from "firebase-admin/app";
import {
  getFirestore,
  Timestamp,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {requireDriverAccess} from "./driver-access-authority.js";

const PROJECT_ID = "demo-gosmart";

const firestoreHost =
  process.env.FIRESTORE_EMULATOR_HOST?.trim();

if (!firestoreHost) {
  throw new Error(
    "FIRESTORE_EMULATOR_HOST is required.",
  );
}

const hostOnly =
  firestoreHost
    .replace(/^\[/u, "")
    .replace(/\].*$/u, "")
    .split(":")[0];

if (
  hostOnly !== "127.0.0.1" &&
  hostOnly !== "localhost" &&
  hostOnly !== "::1"
) {
  throw new Error(
    "Firestore emulator must use loopback.",
  );
}

for (const key of [
  "GCLOUD_PROJECT",
  "GOOGLE_CLOUD_PROJECT",
  "FIREBASE_PROJECT_ID",
]) {
  const value =
    process.env[key]?.trim();

  if (
    value &&
    value !== PROJECT_ID
  ) {
    throw new Error(
      `${key} must be ${PROJECT_ID}.`,
    );
  }
}

const app =
  initializeApp(
    {projectId: PROJECT_ID},
    `publish-return-route-access-${Date.now()}`,
  );

const firestore =
  getFirestore(app);

after(async () => {
  await deleteApp(app);
});

beforeEach(async () => {
  await firestore
    .collection("platformConfig")
    .doc("driverAccess")
    .delete();
});

let sequence = 0;

const unique = (
  label: string,
): string => {
  sequence += 1;

  return [
    label,
    Date.now(),
    sequence,
  ].join("_");
};

const failure = (
  reason: string,
): Error =>
  new HttpsError(
    "failed-precondition",
    "Driver access is required.",
    {reason},
  );

const errorReason = (
  error: unknown,
): string | undefined => {
  if (!(error instanceof HttpsError)) {
    return undefined;
  }

  return (
    error.details as {
      reason?: string;
    } | undefined
  )?.reason;
};

const rejectSubscription = async (
  promise: Promise<unknown>,
): Promise<void> => {
  await assert.rejects(
    promise,
    (error: unknown) =>
      errorReason(error) ===
      "subscription_required",
  );
};

const setConfig = async (
  mode:
    | "launchFree"
    | "paid"
    | "malformed",
): Promise<void> => {
  await firestore
    .collection("platformConfig")
    .doc("driverAccess")
    .set({
      mode:
        mode === "malformed" ?
          "unexpected" :
          mode,
    });
};

const requireAccess = (
  driverId: string,
) =>
  requireDriverAccess({
    firestore,
    driverId,
    now: Timestamp.now(),
    failure,
  });

test(
  "publishReturnRoute source delegates both access checks through loadDriverAccess",
  () => {
    const source =
      readFileSync(
        "functions/src/index.ts",
        "utf8",
      );

    const loadStart =
      source.indexOf(
        "const loadDriverAccess",
      );

    const validationStart =
      source.indexOf(
        "const validatePublishInput",
      );

    const publishStart =
      source.indexOf(
        "export const publishReturnRoute",
      );

    assert.ok(loadStart >= 0);
    assert.ok(validationStart > loadStart);
    assert.ok(publishStart > validationStart);

    const loadSection =
      source.slice(
        loadStart,
        validationStart,
      );

    assert.match(
      loadSection,
      /await requireDriverAccess\(\{/u,
    );

    const publishSection =
      source.slice(
        publishStart,
      );

    const accessRechecks =
      publishSection.match(
        /loadDriverAccess\(/gu,
      ) ?? [];

    assert.equal(
      accessRechecks.length,
      2,
    );
  },
);

test(
  "publish access dependency allows launchFree without pass",
  async () => {
    await setConfig("launchFree");

    const mode =
      await requireAccess(
        unique("launch_free_driver"),
      );

    assert.equal(
      mode,
      "launchFree",
    );
  },
);

test(
  "publish access dependency rejects explicit paid without pass",
  async () => {
    await setConfig("paid");

    await rejectSubscription(
      requireAccess(
        unique("paid_driver"),
      ),
    );
  },
);

test(
  "publish access dependency treats missing config as paid",
  async () => {
    await rejectSubscription(
      requireAccess(
        unique("missing_config_driver"),
      ),
    );
  },
);

test(
  "publish access dependency treats malformed config as paid",
  async () => {
    await setConfig("malformed");

    await rejectSubscription(
      requireAccess(
        unique("malformed_config_driver"),
      ),
    );
  },
);

test(
  "publish transaction-shaped recheck allows launchFree without pass",
  async () => {
    await setConfig("launchFree");

    const driverId =
      unique("transaction_launch_free");

    const mode =
      await firestore.runTransaction(
        async (transaction) =>
          requireDriverAccess({
            firestore,
            driverId,
            now: Timestamp.now(),
            failure,
            getDocuments: (query) =>
              transaction.get(query),
          }),
      );

    assert.equal(
      mode,
      "launchFree",
    );
  },
);

test(
  "publish transaction-shaped recheck rejects paid without pass",
  async () => {
    await setConfig("paid");

    const driverId =
      unique("transaction_paid");

    await rejectSubscription(
      firestore.runTransaction(
        async (transaction) =>
          requireDriverAccess({
            firestore,
            driverId,
            now: Timestamp.now(),
            failure,
            getDocuments: (query) =>
              transaction.get(query),
          }),
      ),
    );
  },
);
