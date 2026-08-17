/* eslint-disable max-len */
import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {App, deleteApp, initializeApp} from "firebase-admin/app";
import {Firestore, getFirestore, Timestamp} from "firebase-admin/firestore";

type JsonRecord = Record<string, unknown>;

type AuthSession = {
  uid: string;
  idToken: string;
};

type CallableResponse = {
  httpStatus: number;
  envelope: JsonRecord;
};

const projectId = "demo-gosmart";
const region = "europe-west1";
const callableName = "getMyActiveReturnRoute";

let sequence = 0;
let app: App;
let firestore: Firestore;

const requiredEnvironment = (
  name: string,
): string => {
  const value = process.env[name];

  if (
    typeof value !== "string" ||
    value.trim().length === 0
  ) {
    throw new Error(
      `${name} must be provided by Firebase emulators.`,
    );
  }

  return value.trim();
};

const assertLoopbackHost = (
  name: string,
  value: string,
): void => {
  const host =
    value
      .split(":")[0]
      .trim()
      .toLowerCase();

  if (
    host !== "127.0.0.1" &&
    host !== "localhost" &&
    host !== "::1"
  ) {
    throw new Error(
      `${name} must use a loopback emulator host.`,
    );
  }
};

const configuredProject =
  process.env.GCLOUD_PROJECT?.trim() ||
  process.env.GOOGLE_CLOUD_PROJECT?.trim();

if (
  configuredProject &&
  configuredProject !== projectId
) {
  throw new Error(
    `Refusing non-demo Firebase project: ${configuredProject}`,
  );
}

const authHost =
  requiredEnvironment(
    "FIREBASE_AUTH_EMULATOR_HOST",
  );

const firestoreHost =
  requiredEnvironment(
    "FIRESTORE_EMULATOR_HOST",
  );

const functionsHost =
  process.env.FUNCTIONS_EMULATOR_HOST?.trim() ||
  "127.0.0.1:5001";

assertLoopbackHost(
  "FIREBASE_AUTH_EMULATOR_HOST",
  authHost,
);

assertLoopbackHost(
  "FIRESTORE_EMULATOR_HOST",
  firestoreHost,
);

assertLoopbackHost(
  "FUNCTIONS_EMULATOR_HOST",
  functionsHost,
);

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
      `${label} must be a JSON object.`,
    );
  }

  return value as JsonRecord;
};

const requireString = (
  record: JsonRecord,
  field: string,
  label: string,
): string => {
  const value =
    record[field];

  if (
    typeof value !== "string" ||
    value.length === 0
  ) {
    throw new Error(
      `${label}.${field} must be a non-empty string.`,
    );
  }

  return value;
};

const signUp = async (
  label: string,
): Promise<AuthSession> => {
  const response =
    await fetch(
      `http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-api-key`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          email:
            `${unique(label)}@example.test`,
          password:
            `GoSmart_${unique("password")}_A1`,
          returnSecureToken: true,
        }),
      },
    );

  const envelope =
    asRecord(
      await response.json(),
      "Auth response",
    );

  if (!response.ok) {
    throw new Error(
      `Auth sign-up failed: http=${response.status}`,
    );
  }

  return {
    uid:
      requireString(
        envelope,
        "localId",
        "Auth response",
      ),
    idToken:
      requireString(
        envelope,
        "idToken",
        "Auth response",
      ),
  };
};

const invokeCallable = async (
  session: AuthSession | null,
  data: JsonRecord,
): Promise<CallableResponse> => {
  const headers:
    Record<string, string> = {
      "Content-Type": "application/json",
    };

  if (session !== null) {
    headers.Authorization =
      `Bearer ${session.idToken}`;
  }

  const response =
    await fetch(
      `http://${functionsHost}/${projectId}/${region}/${callableName}`,
      {
        method: "POST",
        headers,
        body: JSON.stringify({
          data,
        }),
      },
    );

  const envelope =
    asRecord(
      await response.json(),
      `${callableName} response`,
    );

  return {
    httpStatus: response.status,
    envelope,
  };
};

const callableResult = (
  response: CallableResponse,
): JsonRecord => {
  assert.equal(
    response.httpStatus,
    200,
  );

  assert.equal(
    response.envelope.error,
    undefined,
  );

  const value =
    Object.prototype.hasOwnProperty.call(
      response.envelope,
      "result",
    ) ?
      response.envelope.result :
      response.envelope.data;

  return asRecord(
    value,
    `${callableName} result`,
  );
};

const expectCallableError = (
  response: CallableResponse,
  expectedStatus: string,
  expectedReason?: string,
): void => {
  assert.notEqual(
    response.httpStatus,
    200,
  );

  const error =
    asRecord(
      response.envelope.error,
      `${callableName} error`,
    );

  assert.equal(
    error.status,
    expectedStatus,
  );

  if (expectedReason === undefined) {
    return;
  }

  const details =
    asRecord(
      error.details,
      `${callableName} error details`,
    );

  assert.equal(
    details.reason,
    expectedReason,
  );
};

const seedApprovedDriver = async (
  session: AuthSession,
): Promise<string> => {
  const driverId =
    unique("return_route_driver");

  const now =
    Timestamp.now();

  await firestore
    .collection("driverProfiles")
    .doc(driverId)
    .set({
      authUserId: session.uid,
      status: "approved",
      createdAt: now,
      approvedAt: now,
      suspendedAt: null,
    });

  return driverId;
};

const seedValidActiveRoute = async (
  driverId: string,
): Promise<{
  routeId: string;
  createdAtMillis: number;
  activatedAtMillis: number;
  expiresAtMillis: number;
}> => {
  const routeId =
    unique("active_return_route");

  const nowMillis =
    Date.now();

  const createdAtMillis =
    nowMillis - 120_000;

  const activatedAtMillis =
    nowMillis - 60_000;

  const expiresAtMillis =
    nowMillis + 3_600_000;

  const createdAt =
    Timestamp.fromMillis(
      createdAtMillis,
    );

  const activatedAt =
    Timestamp.fromMillis(
      activatedAtMillis,
    );

  const expiresAt =
    Timestamp.fromMillis(
      expiresAtMillis,
    );

  const routeRef =
    firestore
      .collection("driverReturnRoutes")
      .doc(routeId);

  const lockRef =
    firestore
      .collection("driverActiveReturnRoutes")
      .doc(driverId);

  const batch =
    firestore.batch();

  batch.set(
    routeRef,
    {
      driverId,
      origin: {
        latitude: 41.0,
        longitude: 29.0,
      },
      destination: {
        latitude: 41.1,
        longitude: 29.1,
      },
      status: "active",
      createdAt,
      activatedAt,
      expiresAt,
      routeDistanceMeters: 12000,
      routeDurationSeconds: 1800,
      encodedPolyline:
        "_p~iF~ps|U_ulLnnqC_mqNvxq`@",
      pricingVersion: null,
    },
  );

  batch.set(
    lockRef,
    {
      routeId,
      activatedAt,
      expiresAt,
    },
  );

  await batch.commit();

  return {
    routeId,
    createdAtMillis,
    activatedAtMillis,
    expiresAtMillis,
  };
};

before(() => {
  app =
    initializeApp(
      {
        projectId,
      },
      `active-return-route-callable-${process.pid}`,
    );

  firestore =
    getFirestore(app);
});

after(async () => {
  if (app) {
    await deleteApp(app);
  }
});

test(
  "active return route callable rejects unauthenticated requests",
  async () => {
    const response =
      await invokeCallable(
        null,
        {},
      );

    expectCallableError(
      response,
      "UNAUTHENTICATED",
    );
  },
);

test(
  "active return route callable rejects non-empty payload",
  async () => {
    const session =
      await signUp(
        "invalid_payload",
      );

    const response =
      await invokeCallable(
        session,
        {
          driverId: "client-injected",
        },
      );

    expectCallableError(
      response,
      "INVALID_ARGUMENT",
      "invalid_active_return_route_payload",
    );
  },
);

test(
  "active return route callable requires approved driver identity",
  async () => {
    const session =
      await signUp(
        "missing_profile",
      );

    const response =
      await invokeCallable(
        session,
        {},
      );

    expectCallableError(
      response,
      "PERMISSION_DENIED",
      "driver_profile_required",
    );
  },
);

test(
  "approved driver with no canonical lock receives null",
  async () => {
    const session =
      await signUp(
        "no_lock",
      );

    await seedApprovedDriver(
      session,
    );

    const response =
      await invokeCallable(
        session,
        {},
      );

    const result =
      callableResult(
        response,
      );

    assert.deepEqual(
      Object.keys(result),
      ["activeReturnRoute"],
    );

    assert.equal(
      result.activeReturnRoute,
      null,
    );
  },
);

test(
  "expired canonical lock returns null without route document",
  async () => {
    const session =
      await signUp(
        "expired_lock",
      );

    const driverId =
      await seedApprovedDriver(
        session,
      );

    const nowMillis =
      Date.now();

    const missingRouteId =
      unique(
        "expired_missing_route",
      );

    await firestore
      .collection("driverActiveReturnRoutes")
      .doc(driverId)
      .set({
        routeId: missingRouteId,
        activatedAt:
          Timestamp.fromMillis(
            nowMillis - 3_600_000,
          ),
        expiresAt:
          Timestamp.fromMillis(
            nowMillis - 1,
          ),
      });

    const routeBefore =
      await firestore
        .collection("driverReturnRoutes")
        .doc(missingRouteId)
        .get();

    assert.equal(
      routeBefore.exists,
      false,
    );

    const response =
      await invokeCallable(
        session,
        {},
      );

    const result =
      callableResult(
        response,
      );

    assert.deepEqual(
      Object.keys(result),
      ["activeReturnRoute"],
    );

    assert.equal(
      result.activeReturnRoute,
      null,
    );

    const routeAfter =
      await firestore
        .collection("driverReturnRoutes")
        .doc(missingRouteId)
        .get();

    assert.equal(
      routeAfter.exists,
      false,
    );
  },
);
test(
  "malformed live lock fails closed",
  async () => {
    const session =
      await signUp(
        "malformed_lock",
      );

    const driverId =
      await seedApprovedDriver(
        session,
      );

    const nowMillis =
      Date.now();

    await firestore
      .collection("driverActiveReturnRoutes")
      .doc(driverId)
      .set({
        routeId: "",
        activatedAt:
          Timestamp.fromMillis(
            nowMillis - 60_000,
          ),
        expiresAt:
          Timestamp.fromMillis(
            nowMillis + 3_600_000,
          ),
      });

    const response =
      await invokeCallable(
        session,
        {},
      );

    expectCallableError(
      response,
      "FAILED_PRECONDITION",
      "active_return_route_inconsistent",
    );
  },
);

test(
  "valid canonical lock returns strict active route dto",
  async () => {
    const session =
      await signUp(
        "valid_route",
      );

    const driverId =
      await seedApprovedDriver(
        session,
      );

    const fixture =
      await seedValidActiveRoute(
        driverId,
      );

    const response =
      await invokeCallable(
        session,
        {},
      );

    const result =
      callableResult(
        response,
      );

    assert.deepEqual(
      Object.keys(result),
      ["activeReturnRoute"],
    );

    const active =
      asRecord(
        result.activeReturnRoute,
        "activeReturnRoute",
      );

    assert.deepEqual(
      Object.keys(active).sort(),
      [
        "activatedAtMillis",
        "createdAtMillis",
        "destination",
        "distanceMeters",
        "driverId",
        "encodedPolyline",
        "expiresAtMillis",
        "durationSeconds",
        "origin",
        "routeId",
        "status",
      ].sort(),
    );

    assert.equal(
      active.routeId,
      fixture.routeId,
    );

    assert.equal(
      active.driverId,
      driverId,
    );

    assert.equal(
      active.status,
      "active",
    );

    assert.deepEqual(
      active.origin,
      {
        latitude: 41.0,
        longitude: 29.0,
      },
    );

    assert.deepEqual(
      active.destination,
      {
        latitude: 41.1,
        longitude: 29.1,
      },
    );

    assert.equal(
      active.createdAtMillis,
      fixture.createdAtMillis,
    );

    assert.equal(
      active.activatedAtMillis,
      fixture.activatedAtMillis,
    );

    assert.equal(
      active.expiresAtMillis,
      fixture.expiresAtMillis,
    );

    assert.equal(
      active.distanceMeters,
      12000,
    );

    assert.equal(
      active.durationSeconds,
      1800,
    );

    assert.equal(
      active.encodedPolyline,
      "_p~iF~ps|U_ulLnnqC_mqNvxq`@",
    );

    for (
      const forbidden of [
        "authUserId",
        "pricingVersion",
        "lock",
        "passengerId",
        "measurement",
        "policyVersion",
      ]
    ) {
      assert.equal(
        Object.prototype.hasOwnProperty.call(
          active,
          forbidden,
        ),
        false,
      );
    }
  },
);

/* eslint-enable max-len */
