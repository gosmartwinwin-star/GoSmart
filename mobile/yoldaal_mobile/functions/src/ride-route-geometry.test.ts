import assert from "node:assert/strict";
import test from "node:test";
import {
  decodeEncodedPolyline,
  geoDistanceMeters,
  locateRouteAnchors,
  routeAnchorDirectionCompatible,
} from "./ride-route-geometry.js";

test(
  "standard encoded polyline decodes deterministic route points",
  () => {
    const points =
      decodeEncodedPolyline(
        "_p~iF~ps|U_ulLnnqC_mqNvxq`@",
      );

    assert.deepEqual(
      points,
      [
        {
          latitude: 38.5,
          longitude: -120.2,
        },
        {
          latitude: 40.7,
          longitude: -120.95,
        },
        {
          latitude: 43.252,
          longitude: -126.453,
        },
      ],
    );
  },
);

test(
  "decoder rejects empty truncated invalid and single-point routes",
  () => {
    assert.throws(
      () =>
        decodeEncodedPolyline(""),
      TypeError,
    );

    assert.throws(
      () =>
        decodeEncodedPolyline("_p~iF"),
      TypeError,
    );

    assert.throws(
      () =>
        decodeEncodedPolyline(
          String.fromCharCode(1),
        ),
      TypeError,
    );

    assert.throws(
      () =>
        decodeEncodedPolyline(
          "_p~iF~ps|U",
        ),
      TypeError,
    );
  },
);

test(
  "distance is zero for same coordinate and symmetric",
  () => {
    const first = {
      latitude: 41.0082,
      longitude: 28.9784,
    };

    const second = {
      latitude: 41.0151,
      longitude: 28.9795,
    };

    assert.equal(
      geoDistanceMeters(
        first,
        first,
      ),
      0,
    );

    const forward =
      geoDistanceMeters(
        first,
        second,
      );

    const reverse =
      geoDistanceMeters(
        second,
        first,
      );

    assert.ok(forward > 0);

    assert.ok(
      Math.abs(
        forward - reverse,
      ) < 0.000001,
    );
  },
);

test(
  "anchor locator selects nearest pickup and dropoff route points",
  () => {
    const routePoints = [
      {
        latitude: 41.0,
        longitude: 29.0,
      },
      {
        latitude: 41.01,
        longitude: 29.01,
      },
      {
        latitude: 41.02,
        longitude: 29.02,
      },
    ];

    const anchors =
      locateRouteAnchors(
        routePoints,
        {
          latitude: 41.0001,
          longitude: 29.0001,
        },
        {
          latitude: 41.0199,
          longitude: 29.0199,
        },
      );

    assert.equal(
      anchors.pickupRouteIndex,
      0,
    );

    assert.equal(
      anchors.dropoffRouteIndex,
      2,
    );

    assert.deepEqual(
      anchors.pickupAnchor,
      routePoints[0],
    );

    assert.deepEqual(
      anchors.dropoffAnchor,
      routePoints[2],
    );

    assert.equal(
      routeAnchorDirectionCompatible(
        anchors,
      ),
      true,
    );
  },
);

test(
  "reversed anchors are direction incompatible",
  () => {
    const routePoints = [
      {
        latitude: 41.0,
        longitude: 29.0,
      },
      {
        latitude: 41.01,
        longitude: 29.01,
      },
      {
        latitude: 41.02,
        longitude: 29.02,
      },
    ];

    const anchors =
      locateRouteAnchors(
        routePoints,
        routePoints[2],
        routePoints[0],
      );

    assert.equal(
      anchors.pickupRouteIndex,
      2,
    );

    assert.equal(
      anchors.dropoffRouteIndex,
      0,
    );

    assert.equal(
      routeAnchorDirectionCompatible(
        anchors,
      ),
      false,
    );
  },
);

test(
  "equal nearest distance preserves first route index like Flutter locator",
  () => {
    const duplicate = {
      latitude: 41.0,
      longitude: 29.0,
    };

    const routePoints = [
      duplicate,
      duplicate,
      {
        latitude: 41.02,
        longitude: 29.02,
      },
    ];

    const anchors =
      locateRouteAnchors(
        routePoints,
        duplicate,
        routePoints[2],
      );

    assert.equal(
      anchors.pickupRouteIndex,
      0,
    );
  },
);

test(
  "same anchor index is direction incompatible",
  () => {
    const routePoints = [
      {
        latitude: 41.0,
        longitude: 29.0,
      },
      {
        latitude: 41.01,
        longitude: 29.01,
      },
    ];

    const samePoint = {
      latitude: 41.0001,
      longitude: 29.0001,
    };

    const anchors =
      locateRouteAnchors(
        routePoints,
        samePoint,
        samePoint,
      );

    assert.equal(
      anchors.pickupRouteIndex,
      anchors.dropoffRouteIndex,
    );

    assert.equal(
      routeAnchorDirectionCompatible(
        anchors,
      ),
      false,
    );
  },
);

test(
  "invalid coordinates and insufficient routes fail closed",
  () => {
    assert.throws(
      () =>
        geoDistanceMeters(
          {
            latitude: 91,
            longitude: 29,
          },
          {
            latitude: 41,
            longitude: 29,
          },
        ),
      TypeError,
    );

    assert.throws(
      () =>
        locateRouteAnchors(
          [
            {
              latitude: 41,
              longitude: 29,
            },
          ],
          {
            latitude: 41,
            longitude: 29,
          },
          {
            latitude: 41.01,
            longitude: 29.01,
          },
        ),
      TypeError,
    );
  },
);
