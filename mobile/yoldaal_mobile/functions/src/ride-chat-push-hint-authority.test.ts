/* eslint-disable max-len, require-jsdoc */
import assert from "node:assert/strict";
import {test} from "node:test";
import {
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";

import {
  dispatchRideChatPushHint,
} from "./ride-chat-push-hint-authority.js";
import type {
  RideChatPushHintBatchResponse,
  RideChatPushHintMessage,
} from "./ride-chat-push-hint-authority.js";

class FakeSnapshot {
  constructor(
    readonly id: string,
    private readonly value:
      Record<string, unknown> |
      undefined,
  ) {}

  get exists(): boolean {
    return this.value !== undefined;
  }

  data(): Record<string, unknown> | undefined {
    return this.value;
  }
}

class FakeDocumentReference {
  constructor(
    private readonly owner:
      FakeFirestore,
    readonly path: string,
    readonly id: string,
  ) {}

  async get(): Promise<FakeSnapshot> {
    return this.owner.snapshot(
      this.path,
      this.id,
    );
  }
}

class FakeTransaction {
  constructor(
    private readonly owner:
      FakeFirestore,
  ) {}

  async get(
    reference: unknown,
  ): Promise<FakeSnapshot> {
    return (
      reference as FakeDocumentReference
    ).get();
  }

  delete(
    reference: unknown,
  ): void {
    this.owner.delete(
      (
        reference as FakeDocumentReference
      ).path,
    );
  }
}

class FakeFirestore {
  readonly records =
    new Map<string, Record<string, unknown>>();

  readonly deleted:
    string[] = [];

  collection(name: string): {
    doc: (
      id: string,
    ) => FakeDocumentReference;
  } {
    return {
      doc: (id: string) =>
        new FakeDocumentReference(
          this,
          `${name}/${id}`,
          id,
        ),
    };
  }

  snapshot(
    path: string,
    id: string,
  ): FakeSnapshot {
    return new FakeSnapshot(
      id,
      this.records.get(path),
    );
  }

  set(
    path: string,
    value: Record<string, unknown>,
  ): void {
    this.records.set(
      path,
      value,
    );
  }

  delete(
    path: string,
  ): void {
    this.records.delete(path);
    this.deleted.push(path);
  }

  async runTransaction<T>(
    callback: (
      transaction: FakeTransaction,
    ) => Promise<T>,
  ): Promise<T> {
    return callback(
      new FakeTransaction(this),
    );
  }

  asFirestore(): Firestore {
    return this as unknown as Firestore;
  }
}

const now =
  Timestamp.fromMillis(
    1_700_000_000_000,
  );

const activeRide = (
  status:
    "driverEnRoute" |
    "driverArrived" |
    "inProgress" = "driverEnRoute",
): Record<string, unknown> => ({
  passengerId: "passenger-a",
  driverId: "driver-a",
  status,
  matchRound: 2,
});

const chatMessage = (
  senderRole:
    "passenger" |
    "driver",
  assignmentRound = 2,
): Record<string, unknown> => ({
  kind: "text",
  senderRole,
  assignmentRound,
  text: "secret-message-body",
  createdAt: now,
  expiresAt: now,
});

const driverTarget =
  (): Record<string, unknown> => ({
    driverId: "driver-a",
    fid: "driver-fid-0001",
    platform: "android",
    updatedAt: now,
  });

const passengerTarget =
  (): Record<string, unknown> => ({
    passengerId: "passenger-a",
    fid: "passenger-fid-0001",
    platform: "android",
    updatedAt: now,
  });

const successResponse =
  (): RideChatPushHintBatchResponse => ({
    successCount: 1,
    failureCount: 0,
    responses: [
      {
        success: true,
      },
    ],
  });

test(
  "passenger chat sends exactly one content-free Android wake hint to current driver",
  async () => {
    const fake =
      new FakeFirestore();

    fake.set(
      "rides/ride-a",
      activeRide(),
    );

    fake.set(
      "driverPushTargets/driver-a",
      driverTarget(),
    );

    const sent:
      RideChatPushHintMessage[] = [];

    const result =
      await dispatchRideChatPushHint(
        {
          firestore:
            fake.asFirestore(),
          getMessaging:
            () => ({
              sendEachForMulticast:
                async (message) => {
                  sent.push(message);
                  return successResponse();
                },
            }),
        },
        {
          rideId: "ride-a",
          messageId: "message-a",
          messageData:
            chatMessage("passenger"),
        },
      );

    assert.deepEqual(
      result,
      {outcome: "sent"},
    );

    assert.deepEqual(
      sent,
      [
        {
          fids: [
            "driver-fid-0001",
          ],
          data: {
            type:
              "ride_chat_message_available",
          },
        },
      ],
    );

    assert.deepEqual(
      Object.keys(
        sent[0]?.data ?? {},
      ),
      ["type"],
    );

    assert.equal(
      JSON.stringify(sent).includes(
        "secret-message-body",
      ),
      false,
    );
  },
);

test(
  "driver chat sends content-free Android wake hint to passenger",
  async () => {
    const fake =
      new FakeFirestore();

    fake.set(
      "rides/ride-a",
      activeRide("inProgress"),
    );

    fake.set(
      "passengerPushTargets/passenger-a",
      passengerTarget(),
    );

    const sent:
      RideChatPushHintMessage[] = [];

    const result =
      await dispatchRideChatPushHint(
        {
          firestore:
            fake.asFirestore(),
          getMessaging:
            () => ({
              sendEachForMulticast:
                async (message) => {
                  sent.push(message);
                  return successResponse();
                },
            }),
        },
        {
          rideId: "ride-a",
          messageId: "message-b",
          messageData:
            chatMessage("driver"),
        },
      );

    assert.equal(
      result.outcome,
      "sent",
    );

    assert.deepEqual(
      sent,
      [
        {
          fids: [
            "passenger-fid-0001",
          ],
          data: {
            type:
              "ride_chat_message_available",
          },
        },
      ],
    );
  },
);

test(
  "stale round matching terminal and iOS cases fail closed without send",
  async () => {
    const cases:
      Array<{
        ride: Record<string, unknown>;
        message: Record<string, unknown>;
        target: Record<string, unknown>;
      }> = [
        {
          ride:
            activeRide(),
          message:
            chatMessage(
              "passenger",
              1,
            ),
          target:
            driverTarget(),
        },
        {
          ride: {
            ...activeRide(),
            status: "matching",
          },
          message:
            chatMessage(
              "passenger",
            ),
          target:
            driverTarget(),
        },
        {
          ride: {
            ...activeRide(),
            status: "completed",
          },
          message:
            chatMessage(
              "passenger",
            ),
          target:
            driverTarget(),
        },
        {
          ride:
            activeRide(),
          message:
            chatMessage(
              "passenger",
            ),
          target: {
            ...driverTarget(),
            platform: "ios",
          },
        },
      ];

    for (const current of cases) {
      const fake =
        new FakeFirestore();

      fake.set(
        "rides/ride-a",
        current.ride,
      );

      fake.set(
        "driverPushTargets/driver-a",
        current.target,
      );

      let sendCount = 0;

      const result =
        await dispatchRideChatPushHint(
          {
            firestore:
              fake.asFirestore(),
            getMessaging:
              () => ({
                sendEachForMulticast:
                  async () => {
                    sendCount += 1;
                    return successResponse();
                  },
              }),
          },
          {
            rideId: "ride-a",
            messageId: "message-a",
            messageData:
              current.message,
          },
        );

      assert.equal(
        result.outcome,
        "ignored",
      );

      assert.equal(
        sendCount,
        0,
      );
    }
  },
);

test(
  "unregistered FID cleanup deletes only the still-current failed target",
  async () => {
    const fake =
      new FakeFirestore();

    fake.set(
      "rides/ride-a",
      activeRide(),
    );

    fake.set(
      "driverPushTargets/driver-a",
      driverTarget(),
    );

    const result =
      await dispatchRideChatPushHint(
        {
          firestore:
            fake.asFirestore(),
          getMessaging:
            () => ({
              sendEachForMulticast:
                async () => ({
                  successCount: 0,
                  failureCount: 1,
                  responses: [
                    {
                      success: false,
                      error: {
                        code:
                          "messaging/installation-id-not-registered",
                      },
                    },
                  ],
                }),
            }),
        },
        {
          rideId: "ride-a",
          messageId: "message-a",
          messageData:
            chatMessage("passenger"),
        },
      );

    assert.equal(
      result.outcome,
      "failed",
    );

    assert.deepEqual(
      fake.deleted,
      [
        "driverPushTargets/driver-a",
      ],
    );
  },
);

test(
  "new FID survives stale unregistered failure",
  async () => {
    const fake =
      new FakeFirestore();

    fake.set(
      "rides/ride-a",
      activeRide(),
    );

    fake.set(
      "driverPushTargets/driver-a",
      driverTarget(),
    );

    const result =
      await dispatchRideChatPushHint(
        {
          firestore:
            fake.asFirestore(),
          getMessaging:
            () => ({
              sendEachForMulticast:
                async () => {
                  fake.set(
                    "driverPushTargets/driver-a",
                    {
                      ...driverTarget(),
                      fid:
                        "driver-fid-new-0002",
                    },
                  );

                  return {
                    successCount: 0,
                    failureCount: 1,
                    responses: [
                      {
                        success: false,
                        error: {
                          code:
                            "messaging/registration-token-not-registered",
                        },
                      },
                    ],
                  };
                },
            }),
        },
        {
          rideId: "ride-a",
          messageId: "message-a",
          messageData:
            chatMessage("passenger"),
        },
      );

    assert.equal(
      result.outcome,
      "failed",
    );

    assert.deepEqual(
      fake.deleted,
      [],
    );

    assert.equal(
      fake.records.get(
        "driverPushTargets/driver-a",
      )?.fid,
      "driver-fid-new-0002",
    );
  },
);

test(
  "messaging failure remains fail-soft",
  async () => {
    const fake =
      new FakeFirestore();

    fake.set(
      "rides/ride-a",
      activeRide(),
    );

    fake.set(
      "driverPushTargets/driver-a",
      driverTarget(),
    );

    const warnings:
      string[] = [];

    const result =
      await dispatchRideChatPushHint(
        {
          firestore:
            fake.asFirestore(),
          getMessaging:
            () => ({
              sendEachForMulticast:
                async () => {
                  throw new Error(
                    "network failure",
                  );
                },
            }),
          warn:
            (message) => {
              warnings.push(message);
            },
        },
        {
          rideId: "ride-a",
          messageId: "message-a",
          messageData:
            chatMessage("passenger"),
        },
      );

    assert.deepEqual(
      result,
      {outcome: "failed"},
    );

    assert.deepEqual(
      fake.deleted,
      [],
    );

    assert.deepEqual(
      warnings,
      [
        "ride_chat_push_hint_send_failed",
      ],
    );
  },
);
