/* eslint-disable max-len */
import assert from "node:assert/strict";
import {after, before, test} from "node:test";
import {App, deleteApp, initializeApp} from "firebase-admin/app";
import {
  Firestore,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";

const projectId = "demo-gosmart";
const region = "europe-west1";

let app: App | undefined;
let firestore: Firestore;
let sequence = 0;

type AuthSession = {
  uid: string;
  idToken: string;
};

type JsonRecord = Record<string, unknown>;

type HistoryPage = {
  rides: JsonRecord[];
  nextCursor: JsonRecord | null;
};

const requiredEnvironment = (name: string): string => {
  const value = process.env[name];
  if (!value || value.trim().length === 0) {
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
  const normalized = value.toLowerCase();

  if (
    !normalized.startsWith("127.0.0.1:") &&
    !normalized.startsWith("localhost:") &&
    !normalized.startsWith("[::1]:")
  ) {
    throw new Error(
      `${name} must target a loopback emulator.`,
    );
  }
};

const authHost =
  requiredEnvironment("FIREBASE_AUTH_EMULATOR_HOST");

const firestoreHost =
  requiredEnvironment("FIRESTORE_EMULATOR_HOST");

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

const unique = (label: string): string => {
  sequence += 1;
  return `${label}_${process.pid}_${Date.now()}_${sequence}`;
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
    throw new Error(`${label} must be a JSON object.`);
  }

  return value as JsonRecord;
};

const requireString = (
  record: JsonRecord,
  field: string,
  label: string,
): string => {
  const value = record[field];

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
  const response = await fetch(
    `http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-api-key`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        email: `${unique(label)}@example.test`,
        password: `GoSmart_${unique("password")}_A1`,
        returnSecureToken: true,
      }),
    },
  );

  const envelope = asRecord(
    await response.json(),
    "Auth response",
  );

  if (!response.ok) {
    const error =
      typeof envelope.error === "object" &&
      envelope.error !== null ?
        envelope.error as JsonRecord :
        {};

    const code =
      typeof error.message === "string" ?
        error.message :
        "unknown";

    throw new Error(
      `Auth emulator signup failed: http=${response.status} code=${code}`,
    );
  }

  return {
    uid: requireString(
      envelope,
      "localId",
      "Auth response",
    ),
    idToken: requireString(
      envelope,
      "idToken",
      "Auth response",
    ),
  };
};

const callable = async (
  session: AuthSession,
  name: string,
  data: JsonRecord,
): Promise<JsonRecord> => {
  const response = await fetch(
    `http://${functionsHost}/${projectId}/${region}/${name}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${session.idToken}`,
      },
      body: JSON.stringify({data}),
    },
  );

  const envelope = asRecord(
    await response.json(),
    `${name} response`,
  );

  if (
    !response.ok ||
    envelope.error !== undefined
  ) {
    const error =
      typeof envelope.error === "object" &&
      envelope.error !== null ?
        envelope.error as JsonRecord :
        {};

    const status =
      typeof error.status === "string" ?
        error.status :
        "unknown";

    throw new Error(
      `Callable ${name} failed: http=${response.status} status=${status}`,
    );
  }

  const result =
    Object.prototype.hasOwnProperty.call(
      envelope,
      "result",
    ) ?
      envelope.result :
      envelope.data;

  return asRecord(
    result,
    `${name} result`,
  );
};

const historyPage = (
  result: JsonRecord,
): HistoryPage => {
  if (!Array.isArray(result.rides)) {
    throw new Error(
      "History result.rides must be an array.",
    );
  }

  const rides = result.rides.map(
    (value, index) =>
      asRecord(value, `History ride ${index}`),
  );

  const cursorValue = result.nextCursor;

  if (cursorValue === null) {
    return {
      rides,
      nextCursor: null,
    };
  }

  return {
    rides,
    nextCursor: asRecord(
      cursorValue,
      "History nextCursor",
    ),
  };
};

const ids = (
  page: HistoryPage,
): string[] =>
  page.rides.map(
    (ride) =>
      requireString(
        ride,
        "rideId",
        "History ride",
      ),
  );

const terminalRide = ({
  passengerId,
  driverId,
  status,
  updatedAt,
}: {
  passengerId: string;
  driverId: string | null;
  status: "completed" | "cancelled" | "expired";
  updatedAt: Timestamp;
}): JsonRecord => {
  const createdAt = Timestamp.fromMillis(
    updatedAt.toMillis() - 60000,
  );

  const assignedAt =
    driverId === null ?
      null :
      Timestamp.fromMillis(
        updatedAt.toMillis() - 45000,
      );

  const startedAt =
    status === "completed" ?
      Timestamp.fromMillis(
        updatedAt.toMillis() - 15000,
      ) :
      null;

  return {
    passengerId,
    driverId,
    status,
    version:
      status === "completed" ? 5 :
        status === "cancelled" ? 3 :
          2,
    pickup: {
      latitude: 41.01,
      longitude: 29.01,
      addressLabel: "History E2E Pickup",
    },
    dropoff: {
      latitude: 41.02,
      longitude: 29.02,
      addressLabel: "History E2E Dropoff",
    },
    route: {
      distanceMeters: 2500,
      durationSeconds: 420,
      encodedPolyline: "history_e2e_polyline",
      computedAt: createdAt,
    },
    createdAt,
    updatedAt,
    acceptedAt: assignedAt,
    driverEnRouteAt: assignedAt,
    arrivedAt:
      status === "completed" ?
        Timestamp.fromMillis(
          updatedAt.toMillis() - 30000,
        ) :
        null,
    startedAt,
    completedAt:
      status === "completed" ?
        updatedAt :
        null,
    cancelledAt:
      status === "cancelled" ?
        updatedAt :
        null,
    expiredAt:
      status === "expired" ?
        updatedAt :
        null,
    cancelledBy:
      status === "cancelled" ?
        "passenger" :
        null,
    terminalReason:
      status === "cancelled" ?
        "passenger_cancelled" :
        null,
  };
};

const nonTerminalRide = (
  passengerId: string,
  driverId: string,
  updatedAt: Timestamp,
): JsonRecord => {
  const createdAt = Timestamp.fromMillis(
    updatedAt.toMillis() - 60000,
  );

  return {
    passengerId,
    driverId,
    status: "inProgress",
    version: 4,
    pickup: {
      latitude: 41.01,
      longitude: 29.01,
      addressLabel: "History E2E Pickup",
    },
    dropoff: {
      latitude: 41.02,
      longitude: 29.02,
      addressLabel: "History E2E Dropoff",
    },
    route: {
      distanceMeters: 2500,
      durationSeconds: 420,
      encodedPolyline: "history_e2e_polyline",
      computedAt: createdAt,
    },
    createdAt,
    updatedAt,
    acceptedAt: createdAt,
    driverEnRouteAt: createdAt,
    arrivedAt: createdAt,
    startedAt: createdAt,
    completedAt: null,
    cancelledAt: null,
    expiredAt: null,
    cancelledBy: null,
    terminalReason: null,
  };
};

before(() => {
  app = initializeApp(
    {projectId},
    `ride-history-callable-emulator-${process.pid}`,
  );

  firestore = getFirestore(app);
});

after(async () => {
  if (app) {
    await deleteApp(app);
  }
});

test(
  "authenticated history callable isolates actors and paginates terminal rides",
  async () => {
    const passenger = await signUp(
      "history_passenger",
    );

    const otherPassenger = await signUp(
      "history_other_passenger",
    );

    const driver = await signUp(
      "history_driver",
    );

    const prefix = unique("history_fixture");

    const driverId =
      `${prefix}_driver_profile`;

    const otherDriverId =
      `${prefix}_other_driver`;

    const passengerLatest =
      `${prefix}_p_latest`;

    const passengerTieZ =
      `${prefix}_p_tie_z`;

    const passengerTieA =
      `${prefix}_p_tie_a`;

    const passengerOld =
      `${prefix}_p_old`;

    const passengerActive =
      `${prefix}_p_active`;

    const otherPassengerRide =
      `${prefix}_other_passenger`;

    const base =
      Date.now() - 120000;

    const batch = firestore.batch();

    batch.set(
      firestore
        .collection("driverProfiles")
        .doc(driverId),
      {
        authUserId: driver.uid,
        status: "suspended",
        createdAt:
          Timestamp.fromMillis(base - 60000),
        approvedAt:
          Timestamp.fromMillis(base - 50000),
        suspendedAt:
          Timestamp.fromMillis(base - 10000),
      },
    );

    batch.set(
      firestore
        .collection("rides")
        .doc(passengerLatest),
      terminalRide({
        passengerId: passenger.uid,
        driverId,
        status: "completed",
        updatedAt:
          Timestamp.fromMillis(base + 4000),
      }),
    );

    batch.set(
      firestore
        .collection("rides")
        .doc(passengerTieZ),
      terminalRide({
        passengerId: passenger.uid,
        driverId,
        status: "cancelled",
        updatedAt:
          Timestamp.fromMillis(base + 3000),
      }),
    );

    batch.set(
      firestore
        .collection("rides")
        .doc(passengerTieA),
      terminalRide({
        passengerId: passenger.uid,
        driverId: null,
        status: "expired",
        updatedAt:
          Timestamp.fromMillis(base + 3000),
      }),
    );

    batch.set(
      firestore
        .collection("rides")
        .doc(passengerOld),
      terminalRide({
        passengerId: passenger.uid,
        driverId,
        status: "completed",
        updatedAt:
          Timestamp.fromMillis(base + 2000),
      }),
    );

    batch.set(
      firestore
        .collection("rides")
        .doc(passengerActive),
      nonTerminalRide(
        passenger.uid,
        driverId,
        Timestamp.fromMillis(base + 5000),
      ),
    );

    batch.set(
      firestore
        .collection("rides")
        .doc(otherPassengerRide),
      terminalRide({
        passengerId: otherPassenger.uid,
        driverId: otherDriverId,
        status: "completed",
        updatedAt:
          Timestamp.fromMillis(base + 6000),
      }),
    );

    await batch.commit();

    const firstPassengerPage = historyPage(
      await callable(
        passenger,
        "getMyRideHistory",
        {
          scope: "passenger",
          pageSize: 2,
          cursor: null,
        },
      ),
    );

    assert.deepEqual(
      ids(firstPassengerPage),
      [
        passengerLatest,
        passengerTieZ,
      ],
    );

    assert.ok(firstPassengerPage.nextCursor);

    assert.equal(
      firstPassengerPage.nextCursor.rideId,
      passengerTieZ,
    );

    assert.equal(
      firstPassengerPage.nextCursor.updatedAtMillis,
      base + 3000,
    );

    const secondPassengerPage = historyPage(
      await callable(
        passenger,
        "getMyRideHistory",
        {
          scope: "passenger",
          pageSize: 2,
          cursor: firstPassengerPage.nextCursor,
        },
      ),
    );

    assert.deepEqual(
      ids(secondPassengerPage),
      [
        passengerTieA,
        passengerOld,
      ],
    );

    assert.equal(
      secondPassengerPage.nextCursor,
      null,
    );

    const passengerAll = [
      ...firstPassengerPage.rides,
      ...secondPassengerPage.rides,
    ];

    assert.equal(passengerAll.length, 4);

    for (const ride of passengerAll) {
      const serialized = JSON.stringify(ride);

      assert.equal(
        serialized.includes("passengerId"),
        false,
      );

      assert.notEqual(
        ride.rideId,
        otherPassengerRide,
      );

      assert.notEqual(
        ride.rideId,
        passengerActive,
      );

      assert.ok(
        [
          "completed",
          "cancelled",
          "expired",
        ].includes(String(ride.status)),
      );
    }

    const driverPage = historyPage(
      await callable(
        driver,
        "getMyRideHistory",
        {
          scope: "driver",
          pageSize: 20,
          cursor: null,
        },
      ),
    );

    assert.deepEqual(
      ids(driverPage),
      [
        passengerLatest,
        passengerTieZ,
        passengerOld,
      ],
    );

    assert.equal(
      driverPage.nextCursor,
      null,
    );

    for (const ride of driverPage.rides) {
      assert.equal(
        ride.driverId,
        driverId,
      );
    }

    const otherPassengerPage = historyPage(
      await callable(
        otherPassenger,
        "getMyRideHistory",
        {
          scope: "passenger",
          pageSize: 20,
          cursor: null,
        },
      ),
    );

    assert.deepEqual(
      ids(otherPassengerPage),
      [otherPassengerRide],
    );
  },
);
/* eslint-enable max-len */
