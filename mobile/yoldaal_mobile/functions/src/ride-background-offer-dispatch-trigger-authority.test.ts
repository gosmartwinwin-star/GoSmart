import assert from "node:assert/strict";
import test from "node:test";

import {
  buildRideOfferHintInitialDispatchEnvelope,
} from "./ride-background-offer-dispatch-policy.js";
import {
  planRideBackgroundOfferInitialDispatch,
} from "./ride-background-offer-dispatch-trigger-authority.js";

const eventId =
  "event-1";

const eventTime =
  "2026-09-09T12:34:56.789Z";

const rideId =
  "ride-1";

test(
  "new matching transition plans exact initial dispatch",
  () => {
    const after = {
      status:
        "matching",
      driverId:
        null,
      matchRound:
        3,
    };

    assert.deepEqual(
      planRideBackgroundOfferInitialDispatch({
        beforeValue:
          undefined,
        afterValue:
          after,
        eventId,
        eventTime,
        rideId,
      }),
      buildRideOfferHintInitialDispatchEnvelope({
        eventId,
        eventTime,
        rideId,
        matchRound:
          3,
      }),
    );
  },
);

test(
  "ordinary same-round matching update produces no plan",
  () => {
    const before = {
      status:
        "matching",
      driverId:
        null,
      matchRound:
        4,
      version:
        1,
    };

    const after = {
      status:
        "matching",
      driverId:
        null,
      matchRound:
        4,
      version:
        2,
    };

    assert.equal(
      planRideBackgroundOfferInitialDispatch({
        beforeValue:
          before,
        afterValue:
          after,
        eventId,
        eventTime,
        rideId,
      }),
      null,
    );
  },
);

test(
  "rematch round transition plans new deterministic envelope",
  () => {
    const plan =
      planRideBackgroundOfferInitialDispatch({
        beforeValue: {
          status:
            "matching",
          driverId:
            null,
          matchRound:
            2,
        },
        afterValue: {
          status:
            "matching",
          driverId:
            null,
          matchRound:
            3,
        },
        eventId:
          "event-rematch",
        eventTime,
        rideId,
      });

    assert.deepEqual(
      plan,
      buildRideOfferHintInitialDispatchEnvelope({
        eventId:
          "event-rematch",
        eventTime,
        rideId,
        matchRound:
          3,
      }),
    );
  },
);

test(
  "driver cancellation back to matching plans a hint dispatch",
  () => {
    const plan =
      planRideBackgroundOfferInitialDispatch({
        beforeValue: {
          status:
            "driverEnRoute",
          driverId:
            "driver-1",
          matchRound:
            7,
        },
        afterValue: {
          status:
            "matching",
          driverId:
            null,
          matchRound:
            8,
        },
        eventId:
          "event-driver-cancel",
        eventTime,
        rideId,
      });

    assert.ok(
      plan,
    );

    assert.equal(
      plan.payload.expectedMatchRound,
      8,
    );
  },
);

test(
  "assigned malformed and non-matching after records fail closed",
  () => {
    const invalidAfterValues = [
      null,
      [],
      {
        status:
          "matching",
        driverId:
          "driver-1",
        matchRound:
          1,
      },
      {
        status:
          "matching",
        driverId:
          null,
        matchRound:
          0,
      },
      {
        status:
          "completed",
        driverId:
          "driver-1",
        matchRound:
          2,
      },
    ];

    for (const afterValue of invalidAfterValues) {
      assert.equal(
        planRideBackgroundOfferInitialDispatch({
          beforeValue:
            undefined,
          afterValue,
          eventId,
          eventTime,
          rideId,
        }),
        null,
      );
    }
  },
);

test(
  "invalid internal event envelope inputs fail closed",
  () => {
    const after = {
      status:
        "matching",
      driverId:
        null,
      matchRound:
        1,
    };

    assert.equal(
      planRideBackgroundOfferInitialDispatch({
        beforeValue:
          undefined,
        afterValue:
          after,
        eventId:
          "",
        eventTime,
        rideId,
      }),
      null,
    );

    assert.equal(
      planRideBackgroundOfferInitialDispatch({
        beforeValue:
          undefined,
        afterValue:
          after,
        eventId,
        eventTime:
          "not-a-time",
        rideId,
      }),
      null,
    );

    assert.equal(
      planRideBackgroundOfferInitialDispatch({
        beforeValue:
          undefined,
        afterValue:
          after,
        eventId,
        eventTime,
        rideId:
          "",
      }),
      null,
    );
  },
);

test(
  "planner output contains only internal task id and wire payload",
  () => {
    const plan =
      planRideBackgroundOfferInitialDispatch({
        beforeValue:
          undefined,
        afterValue: {
          status:
            "matching",
          driverId:
            null,
          matchRound:
            1,
        },
        eventId,
        eventTime,
        rideId,
      });

    assert.ok(
      plan,
    );

    assert.deepEqual(
      Object.keys(plan).sort(),
      [
        "payload",
        "taskId",
      ],
    );

    assert.deepEqual(
      Object.keys(plan.payload).sort(),
      [
        "cursor",
        "dispatchId",
        "dispatchNowMillis",
        "expectedMatchRound",
        "rideId",
      ],
    );

    assert.equal(
      "type" in plan,
      false,
    );

    assert.equal(
      "passengerId" in plan.payload,
      false,
    );

    assert.equal(
      "driverId" in plan.payload,
      false,
    );
  },
);
