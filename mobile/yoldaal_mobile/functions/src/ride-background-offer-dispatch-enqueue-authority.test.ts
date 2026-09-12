import assert from "node:assert/strict";
import test from "node:test";

import type {
  RideOfferHintTaskPayload,
} from "./ride-background-offer-dispatch-policy.js";
import {
  planRideBackgroundOfferInitialDispatch,
} from "./ride-background-offer-dispatch-trigger-authority.js";
import {
  enqueueRideBackgroundOfferInitialDispatch,
} from "./ride-background-offer-dispatch-enqueue-authority.js";

const eventTime =
  "2026-09-09T12:34:56.789Z";

const matchingInput = {
  beforeValue:
    undefined,
  afterValue: {
    status:
      "matching",
    driverId:
      null,
    matchRound:
      3,
  },
  eventId:
    "event-1",
  eventTime,
  rideId:
    "ride-1",
};

test(
  "non-hint transition is skipped without invoking enqueue dependency",
  async () => {
    let callCount =
      0;

    const result =
      await enqueueRideBackgroundOfferInitialDispatch(
        {
          beforeValue: {
            status:
              "matching",
            driverId:
              null,
            matchRound:
              4,
          },
          afterValue: {
            status:
              "matching",
            driverId:
              null,
            matchRound:
              4,
            version:
              2,
          },
          eventId:
            "event-skip",
          eventTime,
          rideId:
            "ride-skip",
        },
        {
          enqueueTask:
            async () => {
              callCount +=
                1;
            },
        },
      );

    assert.equal(
      result,
      "skipped",
    );

    assert.equal(
      callCount,
      0,
    );
  },
);

test(
  "successful enqueue receives exact planner payload and explicit task id",
  async () => {
    const expectedPlan =
      planRideBackgroundOfferInitialDispatch(
        matchingInput,
      );

    assert.ok(
      expectedPlan,
    );

    let capturedPayload:
      RideOfferHintTaskPayload | null =
        null;

    let capturedTaskId:
      string | null =
        null;

    let callCount =
      0;

    const result =
      await enqueueRideBackgroundOfferInitialDispatch(
        matchingInput,
        {
          enqueueTask:
            async (
              payload,
              taskId,
            ) => {
              callCount +=
                1;

              capturedPayload =
                payload;

              capturedTaskId =
                taskId;
            },
        },
      );

    assert.equal(
      result,
      "enqueued",
    );

    assert.equal(
      callCount,
      1,
    );

    assert.deepEqual(
      capturedPayload,
      expectedPlan.payload,
    );

    assert.equal(
      capturedTaskId,
      expectedPlan.taskId,
    );
  },
);

test(
  "task already exists is classified as duplicate success",
  async () => {
    const result =
      await enqueueRideBackgroundOfferInitialDispatch(
        matchingInput,
        {
          enqueueTask:
            async () => {
              const error =
                Object.assign(
                  new Error(
                    "task already exists",
                  ),
                  {
                    code:
                      "functions/task-already-exists",
                  },
                );

              throw error;
            },
        },
      );

    assert.equal(
      result,
      "duplicate",
    );
  },
);

test(
  "non-duplicate enqueue error is rethrown unchanged",
  async () => {
    const error =
      Object.assign(
        new Error(
          "enqueue failed",
        ),
        {
          code:
            "functions/internal-error",
        },
      );

    await assert.rejects(
      async () =>
        enqueueRideBackgroundOfferInitialDispatch(
          matchingInput,
          {
            enqueueTask:
              async () => {
                throw error;
              },
          },
        ),
      (actual: unknown) => {
        assert.equal(
          actual,
          error,
        );

        return true;
      },
    );
  },
);

test(
  "primitive error without duplicate code is rethrown unchanged",
  async () => {
    const error =
      "raw enqueue failure";

    await assert.rejects(
      async () =>
        enqueueRideBackgroundOfferInitialDispatch(
          matchingInput,
          {
            enqueueTask:
              async () => {
                throw error;
              },
          },
        ),
      (actual: unknown) => {
        assert.equal(
          actual,
          error,
        );

        return true;
      },
    );
  },
);

test(
  "throwing structural code accessor does not replace original error",
  async () => {
    const error =
      Object.defineProperty(
        new Error(
          "hostile code getter",
        ),
        "code",
        {
          get: () => {
            throw new Error(
              "getter failure",
            );
          },
        },
      );

    await assert.rejects(
      async () =>
        enqueueRideBackgroundOfferInitialDispatch(
          matchingInput,
          {
            enqueueTask:
              async () => {
                throw error;
              },
          },
        ),
      (actual: unknown) => {
        assert.equal(
          actual,
          error,
        );

        return true;
      },
    );
  },
);
