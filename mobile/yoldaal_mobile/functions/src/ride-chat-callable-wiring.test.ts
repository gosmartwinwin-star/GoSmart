import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import test from "node:test";

const indexSource =
  readFileSync(
    resolve(process.cwd(), "src", "index.ts"),
    "utf8",
  );

test(
  "ride chat authority is wired into the production functions entrypoint",
  () => {
    assert.match(
      indexSource,
      /from "\.\/ride-chat-authority\.js";/u,
    );

    assert.equal(
      (
        indexSource.match(
          /export const sendRideChatMessage = onCall\(/gu,
        ) ?? []
      ).length,
      1,
    );

    assert.equal(
      (
        indexSource.match(
          /export const listRideChatMessages = onCall\(/gu,
        ) ?? []
      ).length,
      1,
    );

    assert.match(
      indexSource,
      /sendRideChatMessageForActor\(/u,
    );

    assert.match(
      indexSource,
      /listRideChatMessagesForActor\(/u,
    );
  },
);
