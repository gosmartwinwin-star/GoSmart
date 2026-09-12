import {protos, v2} from "@googlemaps/routing";
import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  computeTrafficAwareDrivingMeasurement,
} from "./route-helpers.js";

const routing = protos.google.maps.routing.v2;

test(
  "traffic-aware measurement bypasses Routes for identical coordinates",
  async () => {
    let calls = 0;

    const client = {
      computeRoutes: async () => {
        calls += 1;
        throw new Error("must not be called");
      },
    } as unknown as v2.RoutesClient;

    const coordinate = {
      latitude: 41.0082,
      longitude: 28.9784,
    };

    const result =
      await computeTrafficAwareDrivingMeasurement(
        client,
        coordinate,
        coordinate,
      );

    assert.deepEqual(result, {
      distanceMeters: 0,
      durationSeconds: 0,
    });

    assert.equal(calls, 0);
  },
);

test(
  "traffic-aware measurement uses DRIVE TRAFFIC_AWARE and exact field mask",
  async () => {
    let capturedRequest: unknown;
    let capturedOptions: unknown;

    const client = {
      computeRoutes: async (
        request: unknown,
        options: unknown,
      ) => {
        capturedRequest = request;
        capturedOptions = options;

        return [
          {
            routes: [
              {
                distanceMeters: 1234,
                duration: {
                  seconds: 321,
                  nanos: 0,
                },
              },
            ],
          },
        ];
      },
    } as unknown as v2.RoutesClient;

    const result =
      await computeTrafficAwareDrivingMeasurement(
        client,
        {
          latitude: 41.0,
          longitude: 29.0,
        },
        {
          latitude: 41.1,
          longitude: 29.1,
        },
      );

    assert.deepEqual(result, {
      distanceMeters: 1234,
      durationSeconds: 321,
    });

    const request =
      capturedRequest as Record<string, unknown>;

    assert.equal(
      request.travelMode,
      routing.RouteTravelMode.DRIVE,
    );

    assert.equal(
      request.routingPreference,
      routing.RoutingPreference.TRAFFIC_AWARE,
    );

    assert.equal(
      request.computeAlternativeRoutes,
      false,
    );

    assert.equal(request.languageCode, "tr-TR");
    assert.equal(request.regionCode, "TR");
    assert.equal(
      request.units,
      routing.Units.METRIC,
    );

    assert.deepEqual(
      capturedOptions,
      {
        otherArgs: {
          headers: {
            "X-Goog-FieldMask":
              "routes.duration,routes.distanceMeters",
          },
        },
      },
    );
  },
);

test(
  "traffic-aware measurement fails closed for malformed route response",
  async () => {
    const client = {
      computeRoutes: async () => [
        {
          routes: [{}],
        },
      ],
    } as unknown as v2.RoutesClient;

    await assert.rejects(
      () =>
        computeTrafficAwareDrivingMeasurement(
          client,
          {
            latitude: 41.0,
            longitude: 29.0,
          },
          {
            latitude: 41.1,
            longitude: 29.1,
          },
        ),
      (error: unknown) =>
        error instanceof HttpsError &&
        error.code === "internal",
    );
  },
);
