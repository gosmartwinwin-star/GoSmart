import {protos, v2} from "@googlemaps/routing";
import assert from "node:assert/strict";
import test from "node:test";
import {
  computeTrafficAwareDrivingRoute,
} from "./route-helpers.js";

const routing = protos.google.maps.routing.v2;

test(
  "traffic-aware route uses DRIVE TRAFFIC_AWARE overview encoded polyline",
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
                distanceMeters: 4321,
                duration: {
                  seconds: 654,
                  nanos: 0,
                },
                polyline: {
                  encodedPolyline: "encoded-route",
                },
              },
            ],
          },
        ];
      },
    } as unknown as v2.RoutesClient;

    const result =
      await computeTrafficAwareDrivingRoute(
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
      distanceMeters: 4321,
      durationSeconds: 654,
      encodedPolyline: "encoded-route",
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

    assert.equal(
      request.polylineQuality,
      routing.PolylineQuality.OVERVIEW,
    );

    assert.equal(
      request.polylineEncoding,
      routing.PolylineEncoding.ENCODED_POLYLINE,
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
              "routes.duration,routes.distanceMeters," +
              "routes.polyline.encodedPolyline",
          },
        },
      },
    );
  },
);

test(
  "traffic-aware route fails closed without a complete positive route",
  async () => {
    const client = {
      computeRoutes: async () => [
        {
          routes: [
            {
              distanceMeters: 0,
              duration: {
                seconds: 1,
                nanos: 0,
              },
              polyline: {
                encodedPolyline: "encoded-route",
              },
            },
          ],
        },
      ],
    } as unknown as v2.RoutesClient;

    await assert.rejects(
      () =>
        computeTrafficAwareDrivingRoute(
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
      /Invalid route response/,
    );
  },
);

test(
  "traffic-aware route fails closed without encoded polyline",
  async () => {
    const client = {
      computeRoutes: async () => [
        {
          routes: [
            {
              distanceMeters: 10,
              duration: {
                seconds: 5,
                nanos: 0,
              },
              polyline: {},
            },
          ],
        },
      ],
    } as unknown as v2.RoutesClient;

    await assert.rejects(
      () =>
        computeTrafficAwareDrivingRoute(
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
      /Invalid route response/,
    );
  },
);
