/* eslint-disable max-len */
import assert from "node:assert/strict";
import {test} from "node:test";
import {readFileSync} from "node:fs";

const indexSource =
  readFileSync(
    "src/index.ts",
    "utf8",
  );

const authoritySource =
  readFileSync(
    "src/ride-chat-push-hint-authority.ts",
    "utf8",
  );

test(
  "chat wake trigger is create-only on exact nested ride message path",
  () => {
    assert.match(
      indexSource,
      /export const onRideChatMessageCreated =\s*onDocumentCreated\(/u,
    );

    assert.match(
      indexSource,
      /document:\s*"rides\/\{rideId\}\/messages\/\{messageId\}"/u,
    );

    assert.match(
      indexSource,
      /dispatchRideChatPushHint\(/u,
    );
  },
);

test(
  "trigger adapts internal FID list to Firebase Admin token list",
  () => {
    const start =
      indexSource.indexOf(
        "export const onRideChatMessageCreated",
      );

    const end =
      indexSource.indexOf(
        "const RIDE_OFFER_HINT_TASK_QUEUE_TARGET",
        start,
      );

    assert.ok(
      start >= 0 &&
      end > start,
    );

    const block =
      indexSource.slice(
        start,
        end,
      );

    assert.match(
      block,
      /tokens:\s*message\.fids/u,
    );

    assert.doesNotMatch(
      block,
      /notification\s*:/u,
    );

    assert.doesNotMatch(
      block,
      /retry:\s*true/u,
    );
  },
);

test(
  "authority sends only generic chat availability data",
  () => {
    assert.match(
      authoritySource,
      /sendEachForMulticast\(\{\s*fids:\s*\[\s*recipient\.fid,\s*\],\s*data:\s*\{\s*type:\s*RIDE_CHAT_MESSAGE_AVAILABLE_PUSH_HINT_TYPE,\s*\},\s*\}\)/u,
    );

    assert.doesNotMatch(
      authoritySource,
      /notification\s*:/u,
    );

    assert.doesNotMatch(
      authoritySource,
      /getFunctions|taskQueue|onTaskDispatched|retryConfig/u,
    );
  },
);
