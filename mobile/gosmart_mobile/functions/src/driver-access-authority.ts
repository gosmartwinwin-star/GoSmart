import {
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {isActivePass} from "./driver-access-helpers.js";

export type DriverAccessMode = "launchFree" | "paid";

type FailureFactory = (reason: string) => Error;

type QueryReader = (
  query: FirebaseFirestore.Query,
) => Promise<FirebaseFirestore.QuerySnapshot>;

export const driverAccessModeFromData = (
  value: unknown,
): DriverAccessMode => {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value)
  ) {
    return "paid";
  }

  return (value as Record<string, unknown>).mode === "launchFree" ?
    "launchFree" :
    "paid";
};

export const hasDriverAccess = (
  mode: DriverAccessMode,
  passData: Record<string, unknown> | null,
  now: Timestamp,
): boolean => {
  if (mode === "launchFree") {
    return true;
  }

  return passData !== null &&
    isActivePass(passData, now);
};

const accessModeRef = (
  firestore: Firestore,
) => firestore
  .collection("platformConfig")
  .doc("driverAccess");

const latestPassQuery = (
  firestore: Firestore,
  driverId: string,
) => firestore
  .collection("driverAccessPasses")
  .where("driverId", "==", driverId)
  .orderBy("purchasedAt", "desc")
  .limit(1);

export const requireDriverAccess = async (input: {
  firestore: Firestore;
  driverId: string;
  now: Timestamp;
  failure: FailureFactory;
  getDocuments?: QueryReader;
}): Promise<DriverAccessMode> => {
  const config = await accessModeRef(
    input.firestore,
  ).get();

  const mode = driverAccessModeFromData(
    config.exists ? config.data() : undefined,
  );

  if (mode === "launchFree") {
    return mode;
  }

  const getDocuments =
    input.getDocuments ??
    ((query: FirebaseFirestore.Query) => query.get());

  const passes = await getDocuments(
    latestPassQuery(
      input.firestore,
      input.driverId,
    ),
  );

  if (
    passes.empty ||
    !hasDriverAccess(
      mode,
      passes.docs[0].data(),
      input.now,
    )
  ) {
    throw input.failure("subscription_required");
  }

  return mode;
};

export const requireDriverAccessInTransaction = async (
  input: {
    firestore: Firestore;
    transaction: Transaction;
    driverId: string;
    now: Timestamp;
    failure: FailureFactory;
  },
): Promise<DriverAccessMode> => {
  const config = await input.transaction.get(
    accessModeRef(input.firestore),
  );

  const mode = driverAccessModeFromData(
    config.exists ? config.data() : undefined,
  );

  if (mode === "launchFree") {
    return mode;
  }

  const passes = await input.transaction.get(
    latestPassQuery(
      input.firestore,
      input.driverId,
    ),
  );

  if (
    passes.empty ||
    !hasDriverAccess(
      mode,
      passes.docs[0].data(),
      input.now,
    )
  ) {
    throw input.failure("subscription_required");
  }

  return mode;
};
