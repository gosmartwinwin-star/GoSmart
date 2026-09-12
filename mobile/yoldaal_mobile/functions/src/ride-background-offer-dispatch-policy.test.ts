import assert from "node:assert/strict";
import test from "node:test";
import {
  RIDE_OFFER_HINT_FCM_BATCH_MAX,
  RIDE_OFFER_HINT_QUERY_PAGE_SIZE,
  RIDE_OFFER_HINT_TASK_ALREADY_EXISTS_CODE,
  RIDE_OFFER_HINT_UNREGISTERED_FID_CODE,
  buildRideOfferHintTaskId,
  isRideOfferHintTaskAlreadyExistsCode,
  parseRideOfferHintCursor,
  serializeRideOfferHintCursor,
  shouldDeleteRideOfferHintPushTarget,
  shouldEnqueueNextRideOfferHintPage,
  RIDE_OFFER_HINT_TASK_MAX_ATTEMPTS,
  RIDE_OFFER_HINT_TASK_MIN_BACKOFF_SECONDS,
  RIDE_OFFER_HINT_TASK_MAX_BACKOFF_SECONDS,
  RIDE_OFFER_HINT_TASK_TIMEOUT_SECONDS,
  RIDE_OFFER_HINT_TASK_MAX_CONCURRENT_DISPATCHES,
  RIDE_OFFER_HINT_TASK_MAX_DISPATCHES_PER_SECOND,
  isRideOfferHintDispatchStillCurrent,
  shouldRetryRideOfferHintBatchResponse,
  buildRideOfferHintTaskPayload,
  parseRideOfferHintTaskPayload,
  buildRideOfferHintInitialDispatchEnvelope,
} from "./ride-background-offer-dispatch-policy.js";

test(
  "dispatch page and FID batch limits align at 500",
  () => {
    assert.equal(
      RIDE_OFFER_HINT_QUERY_PAGE_SIZE,
      500,
    );

    assert.equal(
      RIDE_OFFER_HINT_FCM_BATCH_MAX,
      500,
    );
  },
);

test(
  "cursor serialization is deterministic and round-trips",
  () => {
    const cursor = {
      expiresAtMillis: 1_800_000_000_000,
      driverId: "driver-a",
    };

    const serialized =
      serializeRideOfferHintCursor(
        cursor,
      );

    assert.equal(
      serialized,
      "[1800000000000,\"driver-a\"]",
    );

    assert.deepEqual(
      parseRideOfferHintCursor(
        serialized,
      ),
      cursor,
    );
  },
);

test(
  "invalid cursors fail closed",
  () => {
    assert.throws(
      () =>
        parseRideOfferHintCursor(
          "[]",
        ),
    );

    assert.throws(
      () =>
        parseRideOfferHintCursor(
          "[-1,\"driver-a\"]",
        ),
    );

    assert.throws(
      () =>
        serializeRideOfferHintCursor({
          expiresAtMillis: 1,
          driverId: " driver-a",
        }),
    );
  },
);

test(
  "task IDs are deterministic hashed values",
  () => {
    const input = {
      dispatchId: "event-a",
      kind: "page",
      cursor: {
        expiresAtMillis: 1000,
        driverId: "driver-a",
      },
    };

    const first =
      buildRideOfferHintTaskId(
        input,
      );

    const second =
      buildRideOfferHintTaskId(
        input,
      );

    assert.equal(
      first,
      second,
    );

    assert.match(
      first,
      /^[0-9a-f]{64}$/,
    );

    assert.notEqual(
      first,
      buildRideOfferHintTaskId({
        ...input,
        cursor: {
          expiresAtMillis: 1000,
          driverId: "driver-b",
        },
      }),
    );

    assert.notEqual(
      first,
      buildRideOfferHintTaskId({
        ...input,
        kind: "other",
      }),
    );
  },
);

test(
  "task duplicate classification is exact",
  () => {
    assert.equal(
      RIDE_OFFER_HINT_TASK_ALREADY_EXISTS_CODE,
      "functions/task-already-exists",
    );

    assert.equal(
      isRideOfferHintTaskAlreadyExistsCode(
        "functions/task-already-exists",
      ),
      true,
    );

    assert.equal(
      isRideOfferHintTaskAlreadyExistsCode(
        "functions/internal",
      ),
      false,
    );
  },
);

test(
  "only current explicitly unregistered FID is deletable",
  () => {
    assert.equal(
      RIDE_OFFER_HINT_UNREGISTERED_FID_CODE,
      "messaging/installation-id-not-registered",
    );

    assert.equal(
      shouldDeleteRideOfferHintPushTarget({
        errorCode:
          "messaging/installation-id-not-registered",
        failedFid: "fid-a",
        currentFid: "fid-a",
      }),
      true,
    );

    assert.equal(
      shouldDeleteRideOfferHintPushTarget({
        errorCode:
          "messaging/installation-id-not-registered",
        failedFid: "fid-a",
        currentFid: "fid-new",
      }),
      false,
    );

    assert.equal(
      shouldDeleteRideOfferHintPushTarget({
        errorCode:
          "messaging/invalid-argument",
        failedFid: "fid-a",
        currentFid: "fid-a",
      }),
      false,
    );

    assert.equal(
      shouldDeleteRideOfferHintPushTarget({
        errorCode:
          "messaging/server-unavailable",
        failedFid: "fid-a",
        currentFid: "fid-a",
      }),
      false,
    );
  },
);

test(
  "full query page schedules continuation",
  () => {
    assert.equal(
      shouldEnqueueNextRideOfferHintPage(
        500,
      ),
      true,
    );

    assert.equal(
      shouldEnqueueNextRideOfferHintPage(
        499,
      ),
      false,
    );

    assert.equal(
      shouldEnqueueNextRideOfferHintPage(
        0,
      ),
      false,
    );

    assert.throws(
      () =>
        shouldEnqueueNextRideOfferHintPage(
          501,
        ),
    );

    assert.throws(
      () =>
        shouldEnqueueNextRideOfferHintPage(
          -1,
        ),
    );

    assert.throws(
      () =>
        shouldEnqueueNextRideOfferHintPage(
          1.5,
        ),
    );
  },
);

test(
  "task retry and launch rate limits are bounded",
  () => {
    assert.equal(
      RIDE_OFFER_HINT_TASK_MAX_ATTEMPTS,
      2,
    );

    assert.equal(
      RIDE_OFFER_HINT_TASK_MIN_BACKOFF_SECONDS,
      60,
    );

    assert.equal(
      RIDE_OFFER_HINT_TASK_MAX_BACKOFF_SECONDS,
      60,
    );

    assert.equal(
      RIDE_OFFER_HINT_TASK_TIMEOUT_SECONDS,
      120,
    );

    assert.equal(
      RIDE_OFFER_HINT_TASK_MAX_CONCURRENT_DISPATCHES,
      1,
    );

    assert.equal(
      RIDE_OFFER_HINT_TASK_MAX_DISPATCHES_PER_SECOND,
      1,
    );
  },
);

test(
  "dispatch chain remains current only for the same matching round",
  () => {
    const current = {
      expectedMatchRound: 3,
      currentStatus: "matching",
      currentDriverId: null,
      currentMatchRound: 3,
    };

    assert.equal(
      isRideOfferHintDispatchStillCurrent(
        current,
      ),
      true,
    );

    assert.equal(
      isRideOfferHintDispatchStillCurrent({
        ...current,
        currentStatus: "driverEnRoute",
      }),
      false,
    );

    assert.equal(
      isRideOfferHintDispatchStillCurrent({
        ...current,
        currentDriverId: "driver-a",
      }),
      false,
    );

    assert.equal(
      isRideOfferHintDispatchStillCurrent({
        ...current,
        currentMatchRound: 4,
      }),
      false,
    );

    assert.equal(
      isRideOfferHintDispatchStillCurrent({
        ...current,
        currentMatchRound: null,
      }),
      false,
    );

    assert.throws(
      () =>
        isRideOfferHintDispatchStillCurrent({
          ...current,
          expectedMatchRound: 0,
        }),
    );
  },
);

test(
  "only zero-success batch responses request whole-page retry",
  () => {
    assert.equal(
      shouldRetryRideOfferHintBatchResponse({
        successCount: 0,
        failureCount: 500,
      }),
      true,
    );

    assert.equal(
      shouldRetryRideOfferHintBatchResponse({
        successCount: 499,
        failureCount: 1,
      }),
      false,
    );

    assert.equal(
      shouldRetryRideOfferHintBatchResponse({
        successCount: 500,
        failureCount: 0,
      }),
      false,
    );

    assert.throws(
      () =>
        shouldRetryRideOfferHintBatchResponse({
          successCount: 0,
          failureCount: 0,
        }),
    );

    assert.throws(
      () =>
        shouldRetryRideOfferHintBatchResponse({
          successCount: -1,
          failureCount: 1,
        }),
    );
  },
);

test(
  "task payload builder emits exact JSON-safe initial boundary",
  () => {
    assert.deepEqual(
      buildRideOfferHintTaskPayload({
        dispatchId:
          "event-1",
        rideId:
          "ride-1",
        expectedMatchRound:
          3,
        dispatchNowMillis:
          1_800_000_000_000,
        cursor:
          null,
      }),
      {
        dispatchId:
          "event-1",
        rideId:
          "ride-1",
        expectedMatchRound:
          3,
        dispatchNowMillis:
          1_800_000_000_000,
        cursor:
          null,
      },
    );
  },
);

test(
  "task payload parser round-trips an initial page",
  () => {
    const wire =
      buildRideOfferHintTaskPayload({
        dispatchId:
          "event-1",
        rideId:
          "ride-1",
        expectedMatchRound:
          2,
        dispatchNowMillis:
          1234,
        cursor:
          null,
      });

    assert.deepEqual(
      parseRideOfferHintTaskPayload(
        wire,
      ),
      {
        dispatchId:
          "event-1",
        rideId:
          "ride-1",
        expectedMatchRound:
          2,
        dispatchNowMillis:
          1234,
        cursor:
          null,
      },
    );
  },
);

test(
  "task payload cursor is serialized on wire and parsed back",
  () => {
    const wire =
      buildRideOfferHintTaskPayload({
        dispatchId:
          "event-2",
        rideId:
          "ride-2",
        expectedMatchRound:
          4,
        dispatchNowMillis:
          5000,
        cursor: {
          expiresAtMillis:
            7000,
          driverId:
            "driver-a",
        },
      });

    assert.equal(
      typeof wire.cursor,
      "string",
    );

    assert.deepEqual(
      Object.keys(wire).sort(),
      [
        "cursor",
        "dispatchId",
        "dispatchNowMillis",
        "expectedMatchRound",
        "rideId",
      ],
    );

    assert.deepEqual(
      parseRideOfferHintTaskPayload(
        wire,
      ),
      {
        dispatchId:
          "event-2",
        rideId:
          "ride-2",
        expectedMatchRound:
          4,
        dispatchNowMillis:
          5000,
        cursor: {
          expiresAtMillis:
            7000,
          driverId:
            "driver-a",
        },
      },
    );
  },
);

test(
  "task payload parser rejects missing extra and non-record values",
  () => {
    assert.equal(
      parseRideOfferHintTaskPayload({
        dispatchId:
          "event-1",
        rideId:
          "ride-1",
        expectedMatchRound:
          1,
        dispatchNowMillis:
          1,
      }),
      null,
    );

    assert.equal(
      parseRideOfferHintTaskPayload({
        dispatchId:
          "event-1",
        rideId:
          "ride-1",
        expectedMatchRound:
          1,
        dispatchNowMillis:
          1,
        cursor:
          null,
        driverId:
          "forbidden",
      }),
      null,
    );

    for (
      const value of [
        null,
        [],
        "task",
        1,
      ]
    ) {
      assert.equal(
        parseRideOfferHintTaskPayload(
          value,
        ),
        null,
      );
    }
  },
);

test(
  "task payload parser rejects invalid scalar authority fields",
  () => {
    const valid = {
      dispatchId:
        "event-1",
      rideId:
        "ride-1",
      expectedMatchRound:
        1,
      dispatchNowMillis:
        1,
      cursor:
        null,
    };

    assert.equal(
      parseRideOfferHintTaskPayload({
        ...valid,
        dispatchId:
          " event-1",
      }),
      null,
    );

    assert.equal(
      parseRideOfferHintTaskPayload({
        ...valid,
        rideId:
          "",
      }),
      null,
    );

    assert.equal(
      parseRideOfferHintTaskPayload({
        ...valid,
        expectedMatchRound:
          0,
      }),
      null,
    );

    assert.equal(
      parseRideOfferHintTaskPayload({
        ...valid,
        expectedMatchRound:
          1.5,
      }),
      null,
    );

    assert.equal(
      parseRideOfferHintTaskPayload({
        ...valid,
        dispatchNowMillis:
          -1,
      }),
      null,
    );

    assert.equal(
      parseRideOfferHintTaskPayload({
        ...valid,
        dispatchNowMillis:
          Number.MAX_SAFE_INTEGER + 1,
      }),
      null,
    );
  },
);

test(
  "task payload parser rejects malformed or non-string cursor",
  () => {
    const valid = {
      dispatchId:
        "event-1",
      rideId:
        "ride-1",
      expectedMatchRound:
        1,
      dispatchNowMillis:
        1,
    };

    assert.equal(
      parseRideOfferHintTaskPayload({
        ...valid,
        cursor:
          "not-json",
      }),
      null,
    );

    assert.equal(
      parseRideOfferHintTaskPayload({
        ...valid,
        cursor:
          "[]",
      }),
      null,
    );

    assert.equal(
      parseRideOfferHintTaskPayload({
        ...valid,
        cursor: {
          expiresAtMillis:
            1,
          driverId:
            "driver-a",
        },
      }),
      null,
    );
  },
);

test(
  "initial dispatch envelope derives deterministic event-time payload",
  () => {
    const envelope =
      buildRideOfferHintInitialDispatchEnvelope({
        eventId:
          "event-1",
        eventTime:
          "2026-09-09T12:34:56.789Z",
        rideId:
          "ride-1",
        matchRound:
          3,
      });

    assert.ok(
      envelope,
    );

    assert.deepEqual(
      envelope.payload,
      {
        dispatchId:
          "event-1",
        rideId:
          "ride-1",
        expectedMatchRound:
          3,
        dispatchNowMillis:
          1_788_957_296_789,
        cursor:
          null,
      },
    );

    assert.equal(
      envelope.taskId,
      buildRideOfferHintTaskId({
        dispatchId:
          "event-1",
        kind:
          "page",
        cursor:
          null,
      }),
    );

    assert.match(
      envelope.taskId,
      /^[0-9a-f]{64}$/,
    );
  },
);

test(
  "initial dispatch envelope is stable across event redelivery",
  () => {
    const input = {
      eventId:
        "event-redelivery",
      eventTime:
        "2026-09-09T12:34:56.789Z",
      rideId:
        "ride-redelivery",
      matchRound:
        2,
    };

    assert.deepEqual(
      buildRideOfferHintInitialDispatchEnvelope(
        input,
      ),
      buildRideOfferHintInitialDispatchEnvelope(
        input,
      ),
    );
  },
);

test(
  "initial dispatch envelope rejects invalid event time",
  () => {
    const valid = {
      eventId:
        "event-1",
      rideId:
        "ride-1",
      matchRound:
        1,
    };

    assert.equal(
      buildRideOfferHintInitialDispatchEnvelope({
        ...valid,
        eventTime:
          "not-a-time",
      }),
      null,
    );

    assert.equal(
      buildRideOfferHintInitialDispatchEnvelope({
        ...valid,
        eventTime:
          " 2026-09-09T12:34:56.789Z",
      }),
      null,
    );

    assert.equal(
      buildRideOfferHintInitialDispatchEnvelope({
        ...valid,
        eventTime:
          "1969-12-31T23:59:59.999Z",
      }),
      null,
    );
  },
);

test(
  "initial dispatch envelope rejects malformed authority inputs",
  () => {
    const valid = {
      eventId:
        "event-1",
      eventTime:
        "2026-09-09T12:34:56.789Z",
      rideId:
        "ride-1",
      matchRound:
        1,
    };

    assert.equal(
      buildRideOfferHintInitialDispatchEnvelope({
        ...valid,
        eventId:
          "",
      }),
      null,
    );

    assert.equal(
      buildRideOfferHintInitialDispatchEnvelope({
        ...valid,
        eventId:
          " event-1",
      }),
      null,
    );

    assert.equal(
      buildRideOfferHintInitialDispatchEnvelope({
        ...valid,
        rideId:
          "",
      }),
      null,
    );

    assert.equal(
      buildRideOfferHintInitialDispatchEnvelope({
        ...valid,
        matchRound:
          0,
      }),
      null,
    );

    assert.equal(
      buildRideOfferHintInitialDispatchEnvelope({
        ...valid,
        matchRound:
          1.5,
      }),
      null,
    );
  },
);
