import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";

const indexSource =
  readFileSync(
    "src/index.ts",
    "utf8",
  );

const producerMarker =
  "const RIDE_OFFER_HINT_TASK_QUEUE_TARGET =";

const triggerMarker =
  "export const onRideBackgroundOfferHintWritten =";

const workerMarker =
  "export const dispatchRideOfferHintPage =";

const producerStart =
  indexSource.indexOf(
    producerMarker,
  );

const triggerStart =
  indexSource.indexOf(
    triggerMarker,
  );

const workerStart =
  indexSource.indexOf(
    workerMarker,
  );

const producerSource =
  producerStart < 0 ||
  workerStart < 0 ?
    "" :
    indexSource.slice(
      producerStart,
      workerStart,
    );

const countText = (
  source: string,
  needle: string,
): number =>
  source.split(
    needle,
  ).length - 1;

test(
  "index imports Eventarc Admin Functions and enqueue authority once",
  () => {
    assert.equal(
      countText(
        indexSource,
        "import {getFunctions} from \"firebase-admin/functions\";",
      ),
      1,
    );

    assert.equal(
      countText(
        indexSource,
        "from \"firebase-functions/v2/firestore\";",
      ),
      1,
    );

    assert.equal(
      countText(
        indexSource,
        "ride-background-offer-dispatch-enqueue-authority.js",
      ),
      1,
    );
  },
);

test(
  "producer is before the frozen R134 task receiver",
  () => {
    assert.notEqual(
      producerStart,
      -1,
    );

    assert.notEqual(
      triggerStart,
      -1,
    );

    assert.notEqual(
      workerStart,
      -1,
    );

    assert.equal(
      producerStart < triggerStart,
      true,
    );

    assert.equal(
      triggerStart < workerStart,
      true,
    );
  },
);

test(
  "ride write trigger uses frozen document region and retry",
  () => {
    assert.equal(
      producerSource.includes(
        "document: \"rides/{rideId}\"",
      ),
      true,
    );

    assert.equal(
      producerSource.includes(
        "region: \"europe-west1\"",
      ),
      true,
    );

    assert.equal(
      producerSource.includes(
        "retry: true",
      ),
      true,
    );

    assert.equal(
      producerSource.includes(
        "onDocumentWritten(",
      ),
      true,
    );
  },
);

test(
  "trigger forwards only authoritative event envelope inputs",
  () => {
    const expected = [
      "event.data?.before.data()",
      "event.data?.after.data()",
      "event.id",
      "event.time",
      "event.params.rideId",
    ];

    for (const fragment of expected) {
      assert.equal(
        producerSource.includes(
          fragment,
        ),
        true,
      );
    }

    assert.equal(
      producerSource.includes(
        "enqueueRideBackgroundOfferInitialDispatch(",
      ),
      true,
    );
  },
);

test(
  "real enqueue targets europe-west1 worker with explicit plan task id",
  () => {
    assert.equal(
      producerSource.includes(
        "\"locations/europe-west1/functions/" +
        "dispatchRideOfferHintPage\"",
      ),
      true,
    );

    assert.equal(
      countText(
        producerSource,
        "getFunctions()",
      ),
      1,
    );

    assert.equal(
      countText(
        producerSource,
        ".taskQueue(",
      ),
      1,
    );

    assert.equal(
      countText(
        producerSource,
        ".enqueue(",
      ),
      1,
    );

    assert.equal(
      producerSource.includes(
        "id: taskId",
      ),
      true,
    );
  },
);

test(
  "producer has no corridor query FID messaging or Google Routes authority",
  () => {
    const forbidden = [
      /array-contains-any/,
      /sendEachForMulticast/,
      /getMessaging\s*\(/,
      /\.collection\s*\(/,
      /driverPushTargets/,
      /googlemaps/i,
      /computeTrafficAwareDriving/,
    ];

    for (const pattern of forbidden) {
      assert.equal(
        pattern.test(
          producerSource,
        ),
        false,
      );
    }
  },
);
