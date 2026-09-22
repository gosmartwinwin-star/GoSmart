import {
  Timestamp,
  type Firestore,
} from "firebase-admin/firestore";

import {
  RideVoiceCallAuthorityError,
  createRideVoiceCallForActor,
  type RideVoiceAuthoritativeRide,
  type RideVoiceCallCreation,
  type RideVoiceExistingCall,
} from "./ride-voice-call-authority.js";

export type RideVoiceCallStorageDependencies = Readonly<{
  firestore: Firestore;
  newOpaqueCallId?: () => string;
  nowMillis?: () => number;
}>;

const requireStorageId = (
  value: unknown,
  message: string,
): string => {
  if (
    typeof value !== "string" ||
    value.length === 0
  ) {
    throw new RideVoiceCallAuthorityError(
      "data-invalid",
      message,
    );
  }

  return value;
};

const snapshotRide = async (
  dependencies: RideVoiceCallStorageDependencies,
  transaction: FirebaseFirestore.Transaction,
  rideId: string,
): Promise<RideVoiceAuthoritativeRide | null> => {
  const rideRef =
    dependencies.firestore
      .collection("rides")
      .doc(rideId);

  const rideSnapshot =
    await transaction.get(rideRef);

  if (!rideSnapshot.exists) {
    return null;
  }

  const data =
    rideSnapshot.data() ?? {};

  const driverId =
    requireStorageId(
      data.driverId,
      "Ride driver identity is invalid.",
    );

  const driverProfileRef =
    dependencies.firestore
      .collection("driverProfiles")
      .doc(driverId);

  const driverProfileSnapshot =
    await transaction.get(driverProfileRef);

  const driverProfileData =
    driverProfileSnapshot.exists ?
      (driverProfileSnapshot.data() ?? {}) :
      {};

  const passengerUid =
    typeof data.passengerId === "string" ?
      data.passengerId :
      "";

  const driverUid =
    typeof driverProfileData.authUserId === "string" ?
      driverProfileData.authUserId :
      "";

  const version =
    typeof data.version === "number" ?
      data.version :
      Number.NaN;

  return {
    id: rideSnapshot.id,
    version,
    status: data.status,
    passengerUid,
    driverUid,
  };
};

const snapshotActiveCall = async (
  dependencies: RideVoiceCallStorageDependencies,
  transaction: FirebaseFirestore.Transaction,
  rideId: string,
): Promise<RideVoiceExistingCall | null> => {
  const activeRef =
    dependencies.firestore
      .collection("rideVoiceActiveCalls")
      .doc(rideId);

  const activeSnapshot =
    await transaction.get(activeRef);

  if (!activeSnapshot.exists) {
    return null;
  }

  const data =
    activeSnapshot.data() ?? {};

  return {
    callId:
      typeof data.callId === "string" ?
        data.callId :
        "",
    rideId:
      typeof data.rideId === "string" ?
        data.rideId :
        "",
    state: data.state,
  };
};

export const createStoredRideVoiceCallForActor = async (
  dependencies: RideVoiceCallStorageDependencies,
  actorUid: unknown,
  input: unknown,
): Promise<RideVoiceCallCreation> =>
  dependencies.firestore.runTransaction(
    async (transaction) => {
      let cachedRide:
        RideVoiceAuthoritativeRide | null |
        undefined;

      const loadRide =
        async (): Promise<
          RideVoiceAuthoritativeRide | null
        > => {
          if (cachedRide !== undefined) {
            return cachedRide;
          }

          const inputRecord =
            typeof input === "object" &&
            input !== null &&
            !Array.isArray(input) ?
              input as Record<string, unknown> :
              null;

          const rideId =
            inputRecord !== null &&
            typeof inputRecord.rideId === "string" ?
              inputRecord.rideId :
              "";

          if (rideId.length === 0) {
            cachedRide = null;
            return cachedRide;
          }

          cachedRide =
            await snapshotRide(
              dependencies,
              transaction,
              rideId,
            );

          return cachedRide;
        };

      const loadActiveCall =
        async (
          rideId: string,
        ): Promise<RideVoiceExistingCall | null> =>
          snapshotActiveCall(
            dependencies,
            transaction,
            rideId,
          );

      const creation =
        await createRideVoiceCallForActor(
          {
            loadRide: async () => loadRide(),
            loadActiveCall,
            newOpaqueCallId:
              dependencies.newOpaqueCallId,
            nowMillis:
              dependencies.nowMillis,
          },
          actorUid,
          input,
        );

      const rideRef =
        dependencies.firestore
          .collection("rides")
          .doc(creation.rideId);

      const callRef =
        rideRef
          .collection("voiceCalls")
          .doc(creation.callId);

      const activeRef =
        dependencies.firestore
          .collection("rideVoiceActiveCalls")
          .doc(creation.rideId);

      const createdAt =
        Timestamp.fromMillis(
          creation.createdAtMillis,
        );

      transaction.create(
        callRef,
        {
          callId: creation.callId,
          rideId: creation.rideId,
          rideVersion: creation.rideVersion,
          state: creation.state,
          caller: {
            uid: creation.caller.uid,
            role: creation.caller.role,
          },
          callee: {
            uid: creation.callee.uid,
            role: creation.callee.role,
          },
          createdAt,
          updatedAt: createdAt,
        },
      );

      transaction.set(
        activeRef,
        {
          callId: creation.callId,
          rideId: creation.rideId,
          state: creation.state,
          updatedAt: createdAt,
        },
      );

      return creation;
    },
  );
