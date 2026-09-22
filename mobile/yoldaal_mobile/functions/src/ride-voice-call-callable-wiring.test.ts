import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {join} from "node:path";
import test from "node:test";

const source =
  readFileSync(
    join(
      process.cwd(),
      "src",
      "index.ts",
    ),
    "utf8",
  );

const count = (
  needle: string,
): number =>
  source.split(needle).length - 1;

const callableSource = (
  name: string,
): string => {
  const marker =
    `export const ${name} = onCall(`;

  const start =
    source.indexOf(marker);

  assert.ok(start >= 0);

  const next =
    source.indexOf(
      "\nexport const ",
      start + marker.length,
    );

  return source.slice(
    start,
    next < 0 ?
      source.length :
      next,
  );
};

const mapperSource = (): string => {
  const marker =
    "const toRideVoiceHttpsError =";

  const start =
    source.indexOf(marker);

  assert.ok(start >= 0);

  const end =
    source.indexOf(
      "export const createRideVoiceCall",
      start,
    );

  assert.ok(end > start);

  return source.slice(
    start,
    end,
  );
};

test(
  "index imports only participant voice authorities",
  () => {
    assert.equal(
      count(
        "from \"./ride-voice-call-authority.js\";",
      ),
      1,
    );

    assert.equal(
      count(
        "from \"./ride-voice-call-storage-authority.js\";",
      ),
      1,
    );

    assert.equal(
      count(
        "from \"./ride-voice-call-lifecycle-storage.js\";",
      ),
      1,
    );

    assert.equal(
      count(
        "transitionStoredRideVoiceCallForSystem",
      ),
      0,
    );
  },
);

test(
  "voice callables explicitly enforce App Check",
  () => {
    const names = [
      "createRideVoiceCall",
      "transitionRideVoiceCall",
    ];

    for (const name of names) {
      const callable =
        callableSource(name);

      assert.match(
        callable,
        /enforceAppCheck:\s*true/u,
      );

      assert.match(
        callable,
        /region:\s*"europe-west1"/u,
      );

      assert.match(
        callable,
        /timeoutSeconds:\s*15/u,
      );

      assert.match(
        callable,
        /memory:\s*"256MiB"/u,
      );

      assert.match(
        callable,
        /minInstances:\s*0/u,
      );

      assert.match(
        callable,
        /maxInstances:\s*3/u,
      );
    }
  },
);

test(
  "voice creation authenticates then delegates",
  () => {
    const callable =
      callableSource(
        "createRideVoiceCall",
      );

    assert.match(
      callable,
      /if \(!request\.auth\?\.uid\)/u,
    );

    assert.match(
      callable,
      /createStoredRideVoiceCallForActor/u,
    );

    assert.match(
      callable,
      /\{firestore\}/u,
    );

    assert.match(
      callable,
      /request\.auth\.uid/u,
    );

    assert.match(
      callable,
      /request\.data/u,
    );
  },
);

test(
  "voice transition authenticates then delegates",
  () => {
    const callable =
      callableSource(
        "transitionRideVoiceCall",
      );

    assert.match(
      callable,
      /if \(!request\.auth\?\.uid\)/u,
    );

    assert.match(
      callable,
      /transitionStoredRideVoiceCallForActor/u,
    );

    assert.match(
      callable,
      /\{firestore\}/u,
    );

    assert.match(
      callable,
      /request\.auth\.uid/u,
    );

    assert.match(
      callable,
      /request\.data/u,
    );
  },
);

test(
  "voice auth gates precede authority delegation",
  () => {
    const create =
      callableSource(
        "createRideVoiceCall",
      );

    const transition =
      callableSource(
        "transitionRideVoiceCall",
      );

    assert.ok(
      create.indexOf(
        "if (!request.auth?.uid)",
      ) <
      create.indexOf(
        "createStoredRideVoiceCallForActor",
      ),
    );

    assert.ok(
      transition.indexOf(
        "if (!request.auth?.uid)",
      ) <
      transition.indexOf(
        "transitionStoredRideVoiceCallForActor",
      ),
    );
  },
);

test(
  "public authority errors preserve safe codes",
  () => {
    const mapper =
      mapperSource();

    for (
      const code of [
        "invalid-argument",
        "not-found",
        "permission-denied",
        "failed-precondition",
        "already-exists",
      ]
    ) {
      assert.match(
        mapper,
        new RegExp(
          `case "${code}"`,
          "u",
        ),
      );
    }

    assert.match(
      mapper,
      /error\.message/u,
    );
  },
);

test(
  "internal authority failures are sanitized",
  () => {
    const mapper =
      mapperSource();

    assert.match(
      mapper,
      /case "data-invalid"[\s\S]*?"internal"/u,
    );

    assert.doesNotMatch(
      mapper,
      /case "data-invalid"[\s\S]*?error\.message/u,
    );

    assert.match(
      mapper,
      /Ride voice call data is invalid\./u,
    );
  },
);

test(
  "public callables expose no system FCM or Agora authority",
  () => {
    const combined =
      callableSource(
        "createRideVoiceCall",
      ) +
      callableSource(
        "transitionRideVoiceCall",
      );

    assert.doesNotMatch(
      combined,
      /transitionStoredRideVoiceCallForSystem/u,
    );

    assert.doesNotMatch(
      combined,
      /getMessaging|sendEachForMulticast/u,
    );

    assert.doesNotMatch(
      combined,
      /Agora|channelName|appCertificate|tokenWithUid/u,
    );
  },
);
