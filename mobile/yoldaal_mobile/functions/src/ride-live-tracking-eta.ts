import {randomUUID} from "node:crypto";

import {
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";

export const RIDE_LIVE_TRACKING_ETA_REFRESH_SECONDS = 30;

export type RideTrackingCoordinate = {
  latitude: number;
  longitude: number;
};

export type RideLiveTrackingEtaResult = {
  etaSeconds: number | null;
  etaUpdatedAtMillis: number | null;
};

export type RideLiveTrackingEtaInput = {
  rideId: string;
  driverId: string;
  status:
    | "driverEnRoute"
    | "driverArrived"
    | "inProgress";
  origin: RideTrackingCoordinate;
  destination: RideTrackingCoordinate | null;
};

export type RideLiveTrackingEtaDependencies = {
  firestore: Firestore;
  computeDrivingMeasurement: (
    origin: RideTrackingCoordinate,
    destination: RideTrackingCoordinate,
  ) => Promise<{
    distanceMeters: number;
    durationSeconds: number;
  }>;
  now?: () => Timestamp;
  createRefreshToken?: () => string;
};

type CacheState = {
  sameScope: boolean;
  etaSeconds: number | null;
  etaUpdatedAt: Timestamp | null;
  refreshLeaseUntil: Timestamp | null;
};

const noEta = (): RideLiveTrackingEtaResult => ({
  etaSeconds: null,
  etaUpdatedAtMillis: null,
});

const validCoordinate = (
  value: RideTrackingCoordinate,
): boolean =>
  Number.isFinite(value.latitude) &&
  value.latitude >= -90 &&
  value.latitude <= 90 &&
  Number.isFinite(value.longitude) &&
  value.longitude >= -180 &&
  value.longitude <= 180;

const readCacheState = (
  data: Record<string, unknown>,
  driverId: string,
  status: RideLiveTrackingEtaInput["status"],
): CacheState => {
  const sameScope =
    data.driverId === driverId &&
    data.status === status;

  const etaSeconds =
    typeof data.etaSeconds === "number" &&
    Number.isInteger(data.etaSeconds) &&
    data.etaSeconds >= 0 ?
      data.etaSeconds :
      null;

  const etaUpdatedAt =
    data.etaUpdatedAt instanceof Timestamp ?
      data.etaUpdatedAt :
      null;

  const refreshLeaseUntil =
    data.refreshLeaseUntil instanceof Timestamp ?
      data.refreshLeaseUntil :
      null;

  return {
    sameScope,
    etaSeconds,
    etaUpdatedAt,
    refreshLeaseUntil,
  };
};

const freshCachedEta = (
  state: CacheState,
  nowMillis: number,
): RideLiveTrackingEtaResult | null => {
  if (
    !state.sameScope ||
    state.etaSeconds === null ||
    state.etaUpdatedAt === null
  ) {
    return null;
  }

  const updatedAtMillis =
    state.etaUpdatedAt.toMillis();

  if (
    updatedAtMillis > nowMillis ||
    nowMillis - updatedAtMillis >
      RIDE_LIVE_TRACKING_ETA_REFRESH_SECONDS * 1000
  ) {
    return null;
  }

  return {
    etaSeconds: state.etaSeconds,
    etaUpdatedAtMillis: updatedAtMillis,
  };
};

export const getRideLiveTrackingEta = async (
  dependencies: RideLiveTrackingEtaDependencies,
  input: RideLiveTrackingEtaInput,
): Promise<RideLiveTrackingEtaResult> => {
  if (input.status === "driverArrived") {
    return noEta();
  }

  if (
    input.destination === null ||
    !validCoordinate(input.origin) ||
    !validCoordinate(input.destination)
  ) {
    return noEta();
  }

  const now =
    dependencies.now?.() ?? Timestamp.now();

  const nowMillis = now.toMillis();

  const cacheRef = dependencies.firestore
    .collection("rideLiveTrackingEtaCaches")
    .doc(input.rideId);

  const refreshToken =
    dependencies.createRefreshToken?.() ??
    randomUUID();

  type Reservation =
    | {
      kind: "cached";
      result: RideLiveTrackingEtaResult;
    }
    | {
      kind: "blocked";
    }
    | {
      kind: "reserved";
    };

  const reservation =
    await dependencies.firestore.runTransaction(
      async (transaction): Promise<Reservation> => {
        const snapshot =
          await transaction.get(cacheRef);

        const data =
          snapshot.data() ?? {};

        const state =
          readCacheState(
            data,
            input.driverId,
            input.status,
          );

        const cached =
          freshCachedEta(state, nowMillis);

        if (cached !== null) {
          return {
            kind: "cached",
            result: cached,
          };
        }

        if (
          state.sameScope &&
          state.refreshLeaseUntil !== null &&
          state.refreshLeaseUntil.toMillis() >
            nowMillis
        ) {
          return {kind: "blocked"};
        }

        transaction.set(
          cacheRef,
          {
            rideId: input.rideId,
            driverId: input.driverId,
            status: input.status,
            refreshToken,
            refreshStartedAt: now,
            refreshLeaseUntil:
              Timestamp.fromMillis(
                nowMillis +
                RIDE_LIVE_TRACKING_ETA_REFRESH_SECONDS *
                  1000,
              ),
            updatedAt: now,
          },
          {merge: true},
        );

        return {kind: "reserved"};
      },
    );

  if (reservation.kind === "cached") {
    return reservation.result;
  }

  if (reservation.kind === "blocked") {
    return noEta();
  }

  let durationSeconds: number;

  try {
    const measurement =
      await dependencies.computeDrivingMeasurement(
        input.origin,
        input.destination,
      );

    if (
      typeof measurement.durationSeconds !== "number" ||
      !Number.isInteger(
        measurement.durationSeconds,
      ) ||
      measurement.durationSeconds < 0
    ) {
      return noEta();
    }

    durationSeconds =
      measurement.durationSeconds;
  } catch (_error: unknown) {
    return noEta();
  }

  const completedAt =
    dependencies.now?.() ?? Timestamp.now();

  const completedAtMillis =
    completedAt.toMillis();

  let cacheWriteAccepted = false;

  await dependencies.firestore.runTransaction(
    async (transaction) => {
      const current =
        await transaction.get(cacheRef);

      const currentData =
        current.data() ?? {};

      if (
        currentData.refreshToken !==
          refreshToken ||
        currentData.driverId !==
          input.driverId ||
        currentData.status !==
          input.status
      ) {
        return;
      }

      transaction.set(
        cacheRef,
        {
          rideId: input.rideId,
          driverId: input.driverId,
          status: input.status,
          etaSeconds: durationSeconds,
          etaUpdatedAt: completedAt,
          refreshToken: null,
          refreshLeaseUntil:
            Timestamp.fromMillis(
              completedAtMillis +
              RIDE_LIVE_TRACKING_ETA_REFRESH_SECONDS *
                1000,
            ),
          updatedAt: completedAt,
        },
        {merge: true},
      );

      cacheWriteAccepted = true;
    },
  );

  if (!cacheWriteAccepted) {
    return noEta();
  }

  return {
    etaSeconds: durationSeconds,
    etaUpdatedAtMillis: completedAtMillis,
  };
};
