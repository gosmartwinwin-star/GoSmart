import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";

const indexSource =
  readFileSync(
    "src/index.ts",
    "utf8",
  );

const authoritySource =
  readFileSync(
    "src/ride-background-offer-dispatch-task-worker-authority.ts",
    "utf8",
  );

const workerMarker =
  "export const dispatchRideOfferHintPage =";

const workerStart =
  indexSource.indexOf(
    workerMarker,
  );

const workerSource =
  workerStart < 0 ?
    "" :
    indexSource.slice(
      workerStart,
    );

const executionSource =
  authoritySource;

const countText = (
  source: string,
  needle: string,
): number =>
  source.split(
    needle,
  ).length - 1;

test(
  "worker delegates execution core and keeps production adapters",
  () => {
    assert.notEqual(
      workerStart,
      -1,
    );

    assert.equal(
      indexSource.includes(
        "from \"./ride-background-offer-dispatch-task-worker-authority.js\"",
      ),
      true,
    );

    assert.equal(
      workerSource.includes(
        "executeRideOfferHintPageTask(",
      ),
      true,
    );

    assert.equal(
      workerSource.includes(
        "getFunctions()",
      ),
      true,
    );

    assert.equal(
      workerSource.includes(
        "getMessaging()",
      ),
      true,
    );

    assert.match(
      executionSource,
      /dependencies\s*\.getTaskQueue\s*\(\s*\)/,
    );

    assert.match(
      executionSource,
      /dependencies\s*\.getMessaging\s*\(\s*\)/,
    );

    const wrapperForbidden = [
      "\"driverReturnRouteCorridorIndexes\"",
      "\"driverPushTargets\"",
      "parsePersistedDriverPushTarget(",
      "shouldDeleteRideOfferHintPushTarget(",
      "shouldRetryRideOfferHintBatchResponse(",
    ];

    for (const fragment of wrapperForbidden) {
      assert.equal(
        workerSource.includes(
          fragment,
        ),
        false,
      );
    }
  },
);
test(
  "task worker keeps frozen retry rate and timeout",
  () => {
    assert.match(
      workerSource,
      /onTaskDispatched\(/,
    );

    assert.match(
      workerSource,
      /region:\s*"europe-west1"/,
    );

    assert.match(
      workerSource,
      /maxAttempts:\s*RIDE_OFFER_HINT_TASK_MAX_ATTEMPTS/,
    );

    assert.match(
      workerSource,
      /minBackoffSeconds:\s*RIDE_OFFER_HINT_TASK_MIN_BACKOFF_SECONDS/,
    );

    assert.match(
      workerSource,
      /maxBackoffSeconds:\s*RIDE_OFFER_HINT_TASK_MAX_BACKOFF_SECONDS/,
    );

    assert.match(
      workerSource,
      /timeoutSeconds:\s*RIDE_OFFER_HINT_TASK_TIMEOUT_SECONDS/,
    );
  },
);

test(
  "ride gate query continuation load and send stay ordered",
  () => {
    const rideRead =
      executionSource.indexOf(
        "collection(\"rides\")",
      );

    const staleGate =
      executionSource.indexOf(
        "isRideOfferHintDispatchStillCurrent(",
      );

    const corridorRead =
      executionSource.indexOf(
        "\"driverReturnRouteCorridorIndexes\"",
      );

    const queryGet =
      executionSource.indexOf(
        "await corridorQuery.get()",
      );

    const continuation =
      executionSource.indexOf(
        "shouldEnqueueNextRideOfferHintPage(",
      );

    const enqueueCall =
      executionSource.indexOf(
        ".enqueue(",
      );

    const targetLoad =
      executionSource.indexOf(
        "\"driverPushTargets\"",
      );

    const sendCall =
      executionSource.indexOf(
        ".sendEachForMulticast(",
      );

    assert.equal(
      rideRead >= 0,
      true,
    );

    assert.equal(
      rideRead < staleGate,
      true,
    );

    assert.equal(
      staleGate < corridorRead,
      true,
    );

    assert.equal(
      corridorRead < queryGet,
      true,
    );

    assert.equal(
      queryGet < continuation,
      true,
    );

    assert.equal(
      continuation < enqueueCall,
      true,
    );

    assert.equal(
      enqueueCall < targetLoad,
      true,
    );

    assert.equal(
      targetLoad < sendCall,
      true,
    );
  },
);

test(
  "corridor query keeps frozen page contract",
  () => {
    assert.equal(
      countText(
        executionSource,
        "\"array-contains-any\"",
      ),
      1,
    );

    assert.match(
      executionSource,
      /RIDE_OFFER_HINT_QUERY_PAGE_SIZE/,
    );

    assert.match(
      executionSource,
      /payload\.dispatchNowMillis/,
    );

    assert.match(
      executionSource,
      /FieldPath\.documentId\(\)/,
    );
  },
);

test(
  "recipient load parses all targets but sends Android only",
  () => {
    assert.equal(
      countText(
        executionSource,
        "\"driverPushTargets\"",
      ),
      1,
    );

    assert.equal(
      countText(
        executionSource,
        "firestore.getAll(",
      ),
      1,
    );

    assert.equal(
      executionSource.includes(
        "pushTarget.platform !== \"android\"",
      ),
      true,
    );

    const required = [
      "pushTarget.driverId",
      "pushTarget.fid",
      "pushTarget.platform",
      "sendRecipients.length === 0",
    ];

    for (const fragment of required) {
      assert.equal(
        executionSource.includes(
          fragment,
        ),
        true,
      );
    }
  },
);

test(
  "send is generic FID multicast with no offer authority",
  () => {
    const sendStart =
      executionSource.indexOf(
        ".sendEachForMulticast({",
      );

    assert.equal(
      sendStart >= 0,
      true,
    );

    const sendEnd =
      executionSource.indexOf(
        "});",
        sendStart,
      );

    assert.equal(
      sendEnd > sendStart,
      true,
    );

    const sendSource =
      executionSource.slice(
        sendStart,
        sendEnd + 3,
      );

    assert.equal(
      countText(
        executionSource,
        "getMessaging()",
      ),
      1,
    );

    assert.equal(
      countText(
        executionSource,
        ".sendEachForMulticast(",
      ),
      1,
    );

    assert.equal(
      sendSource.includes(
        "fids:",
      ),
      true,
    );

    assert.equal(
      sendSource.includes(
        "\"ride_offer_available\"",
      ),
      true,
    );

    const forbidden = [
      /notification\s*:/,
      /priority\s*:/,
      /\bandroid\s*:/,
      /\brideId\s*:/,
      /\bdriverId\s*:/,
      /\bpassengerId\s*:/,
      /acceptRide/,
    ];

    for (const pattern of forbidden) {
      assert.equal(
        pattern.test(
          sendSource,
        ),
        false,
      );
    }
  },
);

test(
  "batch policy prevents partial-success whole-task replay",
  () => {
    assert.equal(
      countText(
        executionSource,
        "shouldRetryRideOfferHintBatchResponse(",
      ),
      1,
    );

    assert.equal(
      executionSource.includes(
        "batchResponse.successCount",
      ),
      true,
    );

    assert.equal(
      executionSource.includes(
        "batchResponse.failureCount",
      ),
      true,
    );

    assert.equal(
      executionSource.includes(
        "batchResponse.responses.length !==",
      ),
      true,
    );

    assert.equal(
      executionSource.includes(
        "if (retryWholeTask)",
      ),
      true,
    );
  },
);

test(
  "unregistered cleanup is transactionally FID conditional",
  () => {
    assert.equal(
      countText(
        executionSource,
        "firestore.runTransaction(",
      ),
      1,
    );

    assert.equal(
      countText(
        executionSource,
        "transaction.getAll(",
      ),
      1,
    );

    assert.equal(
      countText(
        executionSource,
        "shouldDeleteRideOfferHintPushTarget(",
      ),
      1,
    );

    assert.equal(
      countText(
        executionSource,
        "transaction.delete(",
      ),
      1,
    );

    const required = [
      "failedRecipient.driverId",
      "response.error?.code",
      "currentTarget.fid",
      "cleanupCandidate.reference",
    ];

    for (const fragment of required) {
      assert.equal(
        executionSource.includes(
          fragment,
        ),
        true,
      );
    }

    assert.match(
      executionSource,
      /failedRecipient\s*\.fid/,
    );
  },
);

test(
  "partial cleanup failure warns without replay",
  () => {
    assert.equal(
      executionSource.includes(
        "await cleanupFailedRecipients();",
      ),
      true,
    );

    assert.equal(
      executionSource.includes(
        "\"ride_offer_hint_push_target_cleanup_failed\"",
      ),
      true,
    );

    assert.equal(
      executionSource.includes(
        "\"Ride offer hint batch requires retry.\"",
      ),
      true,
    );
  },
);

test(
  "worker adds no routes accept or notification authority",
  () => {
    const forbidden = [
      /notification\s*:/,
      /priority\s*:/,
      /googlemaps/i,
      /computeTrafficAwareDriving/,
      /acceptRide/,
    ];

    for (const pattern of forbidden) {
      assert.equal(
        pattern.test(
          executionSource,
        ),
        false,
      );
    }
  },
);
