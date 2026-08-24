/* eslint-disable max-len */
import assert from "node:assert/strict";
import test from "node:test";
import {
  assertLocalFixtureTarget,
  buildDriverFixture,
  FIXTURE_DRIVER_ID,
  FIXTURE_PASSENGER_ID,
  FIXTURE_RIDE_ID,
  PRODUCTION_PROJECT_ID,
} from "./local-driver-fixture.js";
import {serializeActiveRide} from "./ride-lifecycle-helpers.js";

test("production project is rejected", () => {
  assert.throws(() => assertLocalFixtureTarget({projectId: PRODUCTION_PROJECT_ID,
    authHost: "127.0.0.1:9099", firestoreHost: "127.0.0.1:8080"}));
});

test("non-loopback emulator hosts are rejected", () => {
  assert.throws(() => assertLocalFixtureTarget({projectId: "demo-gosmart",
    authHost: "firebase.example.com:9099", firestoreHost: "127.0.0.1:8080"}));
  assert.throws(() => assertLocalFixtureTarget({projectId: "demo-gosmart",
    authHost: "localhost:9099", firestoreHost: "10.0.2.2:8080"}));
});

test("fixture is canonical assigned ride with eligible driver", () => {
  const fixture = buildDriverFixture();
  assert.equal(fixture.driverProfile.status, "approved");
  assert.equal(fixture.accessPass.status, "active");
  assert.equal(fixture.accessPass.driverId, FIXTURE_DRIVER_ID);
  assert.equal(fixture.ride.status, "driverEnRoute");
  assert.equal(fixture.ride.version, 2);
  assert.equal(fixture.ride.driverId, FIXTURE_DRIVER_ID);
  assert.equal(fixture.ride.passengerId, FIXTURE_PASSENGER_ID);
  assert.equal(fixture.driverActiveRide.rideId, FIXTURE_RIDE_ID);
  assert.equal(fixture.driverActiveRide.status, fixture.ride.status);
  assert.ok(fixture.ride.route.distanceMeters > 0);
  const response = serializeActiveRide(FIXTURE_RIDE_ID, fixture.ride);
  assert.equal(response.rideId, FIXTURE_RIDE_ID);
  assert.equal(response.driverId, FIXTURE_DRIVER_ID);
  assert.equal(response.status, "driverEnRoute");
  assert.equal(response.version, 2);
});

test("demo project and loopback hosts are accepted", () => {
  assert.doesNotThrow(() => assertLocalFixtureTarget({projectId: "demo-gosmart",
    authHost: "localhost:9099", firestoreHost: "[::1]:8080"}));
});
