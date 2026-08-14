import {Timestamp} from "firebase-admin/firestore";

export const PRODUCTION_PROJECT_ID = "gosmart-fd8f6";
export const FIXTURE_DRIVER_UID = "fixture_driver_user";
export const FIXTURE_DRIVER_ID = "fixture_driver_profile";
export const FIXTURE_RIDE_ID = "fixture_assigned_ride";
export const FIXTURE_PASSENGER_ID = "fixture_passenger_user";

const isLoopbackEndpoint = (value: string, port: number): boolean =>
  value === `127.0.0.1:${port}` || value === `localhost:${port}` ||
  value === `[::1]:${port}`;

export const assertLocalFixtureTarget = (input: {
  projectId: string;
  authHost: string;
  firestoreHost: string;
}): void => {
  if (input.projectId === PRODUCTION_PROJECT_ID) {
    throw new Error("Production GoSmart project ID is forbidden.");
  }
  if (!input.projectId.startsWith("demo-")) {
    throw new Error("Fixture project ID must start with demo-.");
  }
  if (!isLoopbackEndpoint(input.authHost, 9099)) {
    throw new Error("Auth emulator must use a loopback host and port 9099.");
  }
  if (!isLoopbackEndpoint(input.firestoreHost, 8080)) {
    throw new Error(
      "Firestore emulator must use a loopback host and port 8080.",
    );
  }
};

export const buildDriverFixture = () => {
  const createdAt = Timestamp.fromDate(new Date("2026-01-01T00:00:00.000Z"));
  const expiresAt = Timestamp.fromDate(new Date("2099-01-01T00:00:00.000Z"));
  const pickup = {latitude: 41.0082, longitude: 28.9784,
    addressLabel: "Fixture pickup"};
  const dropoff = {latitude: 41.0151, longitude: 28.9795,
    addressLabel: "Fixture dropoff"};
  return {
    driverProfile: {authUserId: FIXTURE_DRIVER_UID, status: "approved",
      createdAt, approvedAt: createdAt, suspendedAt: null},
    accessPass: {driverId: FIXTURE_DRIVER_ID, plan: "monthly", status: "active",
      purchasedAt: createdAt, activatedAt: createdAt, expiresAt},
    ride: {passengerId: FIXTURE_PASSENGER_ID, driverId: FIXTURE_DRIVER_ID,
      status: "driverEnRoute", version: 2, pickup, dropoff,
      route: {distanceMeters: 1400, durationSeconds: 420,
        encodedPolyline: "fixture_polyline", computedAt: createdAt},
      createdAt, updatedAt: createdAt, acceptedAt: createdAt,
      driverEnRouteAt: createdAt, arrivedAt: null, startedAt: null,
      completedAt: null, cancelledAt: null, expiredAt: null,
      cancelledBy: null, terminalReason: null},
    driverActiveRide: {rideId: FIXTURE_RIDE_ID, status: "driverEnRoute"},
    passengerActiveRide: {rideId: FIXTURE_RIDE_ID, status: "driverEnRoute"},
  };
};
