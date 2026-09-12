import assert from "node:assert/strict";
import test from "node:test";
import {
  Timestamp,
} from "firebase-admin/firestore";
import type {
  Firestore,
} from "firebase-admin/firestore";
import {
  executeRideOfferHintPageTask,
} from "./ride-background-offer-dispatch-task-worker-authority.js";
import type {
  RideOfferHintPageTaskBatchResponse,
  RideOfferHintPageTaskDependencies,
  RideOfferHintPageTaskMessage,
} from "./ride-background-offer-dispatch-task-worker-authority.js";
import type {
  RideOfferHintTaskPayload,
} from "./ride-background-offer-dispatch-policy.js";

const noNetworkDependencies = (
  firestore: Firestore,
  warnings: string[],
): RideOfferHintPageTaskDependencies => ({
  firestore,
  getTaskQueue: () => {
    throw new Error(
      "Unexpected task queue access.",
    );
  },
  getMessaging: () => {
    throw new Error(
      "Unexpected messaging access.",
    );
  },
  warn: (message) => {
    warnings.push(message);
  },
});

test(
  "invalid task payload warns and performs zero external IO",
  async () => {
    const warnings: string[] = [];

    const firestore =
      {} as Firestore;

    await executeRideOfferHintPageTask(
      {},
      noNetworkDependencies(
        firestore,
        warnings,
      ),
    );

    assert.deepEqual(
      warnings,
      [
        "ride_offer_hint_task_invalid_payload",
      ],
    );
  },
);

test(
  "missing ride stops before corridor queue target load or messaging",
  async () => {
    const warnings: string[] = [];
    const reads: string[] = [];

    const firestore = {
      collection: (name: string) => ({
        doc: (documentId: string) => ({
          get: async () => {
            reads.push(
              `${name}/${documentId}`,
            );

            return {
              exists: false,
              data: () => undefined,
            };
          },
        }),
      }),
    } as unknown as Firestore;

    await executeRideOfferHintPageTask(
      {
        dispatchId: "dispatch-r147",
        rideId: "ride-r147",
        expectedMatchRound: 1,
        dispatchNowMillis: 1,
        cursor: null,
      },
      noNetworkDependencies(
        firestore,
        warnings,
      ),
    );

    assert.deepEqual(
      reads,
      [
        "rides/ride-r147",
      ],
    );

    assert.deepEqual(
      warnings,
      [],
    );
  },
);

test(
  "stale matching round stops before corridor queue target load or messaging",
  async () => {
    const warnings: string[] = [];
    const reads: string[] = [];

    const firestore = {
      collection: (name: string) => ({
        doc: (documentId: string) => ({
          get: async () => {
            reads.push(
              `${name}/${documentId}`,
            );

            return {
              exists: true,
              data: () => ({
                status: "matching",
                driverId: null,
                matchRound: 2,
              }),
            };
          },
        }),
      }),
    } as unknown as Firestore;

    await executeRideOfferHintPageTask(
      {
        dispatchId: "dispatch-r147-stale",
        rideId: "ride-r147-stale",
        expectedMatchRound: 1,
        dispatchNowMillis: 1,
        cursor: null,
      },
      noNetworkDependencies(
        firestore,
        warnings,
      ),
    );

    assert.deepEqual(
      reads,
      [
        "rides/ride-r147-stale",
      ],
    );

    assert.deepEqual(
      warnings,
      [],
    );
  },
);
type R148FakeDocumentReference =
  Readonly<{
    id: string;
  }>;

type R148FakePushTarget =
  Readonly<{
    fid: string;
    platform: "android" | "ios";
    updatedAtMillis: number;
  }>;

type R148EnqueueRecord =
  Readonly<{
    payload: RideOfferHintTaskPayload;
    id: string;
  }>;

type R148FullPathHarnessInput =
  Readonly<{
    rideData: Readonly<Record<string, unknown>>;
    corridorDriverIds: ReadonlyArray<string>;
    corridorExpiresAtMillis:
      ReadonlyArray<number>;
    pushTargets:
      ReadonlyMap<
        string,
        R148FakePushTarget | null
      >;
    currentPushTargets?:
      ReadonlyMap<
        string,
        R148FakePushTarget | null
      >;
    batchResponse:
      RideOfferHintPageTaskBatchResponse | null;
  }>;

type R148FullPathHarness =
  Readonly<{
    dependencies:
      RideOfferHintPageTaskDependencies;
    events: string[];
    queryOperations: string[];
    enqueues: R148EnqueueRecord[];
    messages:
      RideOfferHintPageTaskMessage[];
    deletedDriverIds: string[];
    warnings: string[];
  }>;

const r148MatchingRideData =
  (): Readonly<Record<string, unknown>> => ({
    passengerId: "passenger-r148",
    driverId: null,
    status: "matching",
    matchRound: 1,
    version: 1,
    createdAt:
      Timestamp.fromMillis(
        1700000000000,
      ),
    pickup: {
      latitude: 41.0082,
      longitude: 28.9784,
      addressLabel: "Pickup",
    },
    dropoff: {
      latitude: 41.0151,
      longitude: 28.9795,
      addressLabel: "Dropoff",
    },
    route: {
      distanceMeters: 10000,
      durationSeconds: 1200,
      encodedPolyline:
        "passenger_route",
      computedAt:
        Timestamp.fromMillis(
          1700000000000,
        ),
    },
  });

const r148PushTargetData = (
  driverId: string,
  target: R148FakePushTarget | null,
): unknown => {
  if (target === null) {
    return undefined;
  }

  return {
    driverId,
    fid: target.fid,
    platform: target.platform,
    updatedAt:
      Timestamp.fromMillis(
        target.updatedAtMillis,
      ),
  };
};

/** In-memory corridor-query fake. */
class R148FakeCorridorQuery {
  /** Creates the fake corridor query. */
  constructor(
    private readonly driverIds:
      ReadonlyArray<string>,
    private readonly expiresAtMillis:
      ReadonlyArray<number>,
    private readonly events:
      string[],
    private readonly queryOperations:
      string[],
  ) {}

  /**
   * Records a where clause.
   * @param {*} field Queried field.
   * @param {*} operator Query operator.
   * @param {*} _value Query operand.
   * @return {R148FakeCorridorQuery} This fake query.
   */
  where(
    field: unknown,
    operator: unknown,
    _value: unknown,
  ): this {
    this.queryOperations.push(
      `where:${String(field)}:${String(operator)}`,
    );

    return this;
  }

  /**
   * Records an order-by clause.
   * @param {*} field Ordered field.
   * @param {*} direction Sort direction.
   * @return {R148FakeCorridorQuery} This fake query.
   */
  orderBy(
    field: unknown,
    direction: unknown,
  ): this {
    this.queryOperations.push(
      `orderBy:${String(field)}:${String(direction)}`,
    );

    return this;
  }

  /**
   * Records the requested page limit.
   * @param {number} value Requested page size.
   * @return {R148FakeCorridorQuery} This fake query.
   */
  limit(
    value: number,
  ): this {
    this.queryOperations.push(
      `limit:${value}`,
    );

    return this;
  }

  /**
   * Records the continuation cursor.
   * @return {R148FakeCorridorQuery} This fake query.
   */
  startAfter(
    ...values: unknown[]
  ): this {
    this.queryOperations.push(
      `startAfter:${values.length}`,
    );

    return this;
  }

  /** Returns the deterministic fake query page. */
  async get(): Promise<
    Readonly<{
      docs:
        ReadonlyArray<
          Readonly<{
            id: string;
            ref:
              R148FakeDocumentReference;
            exists: true;
            data: () => unknown;
            get: (
              field: string,
            ) => unknown;
          }>
        >;
      size: number;
    }>
    > {
    this.events.push(
      "corridor:get",
    );

    const docs =
      this.driverIds.map(
        (driverId, index) => {
          const expiresAtMillis =
            this.expiresAtMillis[index];

          if (
            expiresAtMillis === undefined
          ) {
            throw new Error(
              "Missing fake corridor expiry.",
            );
          }

          const reference:
            R148FakeDocumentReference = {
              id: driverId,
            };

          return {
            id: driverId,
            ref: reference,
            exists: true as const,
            data: () => ({}),
            get: (
              field: string,
            ): unknown => {
              if (field === "expiresAt") {
                return Timestamp.fromMillis(
                  expiresAtMillis,
                );
              }

              return undefined;
            },
          };
        },
      );

    return {
      docs,
      size: docs.length,
    };
  }
}

const r148BuildFullPathHarness = (
  input: R148FullPathHarnessInput,
): R148FullPathHarness => {
  const events: string[] = [];
  const queryOperations:
    string[] = [];
  const enqueues:
    R148EnqueueRecord[] = [];
  const messages:
    RideOfferHintPageTaskMessage[] = [];
  const deletedDriverIds:
    string[] = [];
  const warnings: string[] = [];

  const currentTargets =
    input.currentPushTargets ??
    input.pushTargets;

  const makePushSnapshot = (
    reference:
      R148FakeDocumentReference,
    targets:
      ReadonlyMap<
        string,
        R148FakePushTarget | null
      >,
  ) => {
    const target =
      targets.get(
        reference.id,
      ) ?? null;

    return {
      id: reference.id,
      exists: target !== null,
      data: () =>
        r148PushTargetData(
          reference.id,
          target,
        ),
    };
  };

  const corridorQuery =
    new R148FakeCorridorQuery(
      input.corridorDriverIds,
      input.corridorExpiresAtMillis,
      events,
      queryOperations,
    );

  const firestore = {
    collection: (
      name: string,
    ): unknown => {
      if (name === "rides") {
        return {
          doc: (
            documentId: string,
          ) => ({
            id: documentId,
            get: async () => {
              events.push(
                `ride:get:${documentId}`,
              );

              return {
                id: documentId,
                exists: true,
                data: () =>
                  input.rideData,
              };
            },
          }),
        };
      }

      if (
        name ===
        "driverReturnRouteCorridorIndexes"
      ) {
        return corridorQuery;
      }

      if (
        name ===
        "driverPushTargets"
      ) {
        return {
          doc: (
            documentId: string,
          ): R148FakeDocumentReference => ({
            id: documentId,
          }),
        };
      }

      throw new Error(
        `Unexpected fake collection: ${name}`,
      );
    },

    getAll: async (
      ...references: unknown[]
    ) => {
      events.push(
        "targets:getAll",
      );

      return references.map(
        (rawReference) => {
          const reference =
            rawReference as
              R148FakeDocumentReference;

          return makePushSnapshot(
            reference,
            input.pushTargets,
          );
        },
      );
    },

    runTransaction: async (
      handler: (
        transaction:
          Readonly<{
            getAll: (
              ...references: unknown[]
            ) => Promise<
              ReadonlyArray<unknown>
            >;
            delete: (
              reference: unknown,
            ) => void;
          }>,
      ) => Promise<unknown>,
    ) => {
      events.push(
        "cleanup:transaction",
      );

      const transaction = {
        getAll: async (
          ...references: unknown[]
        ): Promise<
          ReadonlyArray<unknown>
        > => {
          events.push(
            "cleanup:getAll",
          );

          return references.map(
            (rawReference) => {
              const reference =
                rawReference as
                  R148FakeDocumentReference;

              return makePushSnapshot(
                reference,
                currentTargets,
              );
            },
          );
        },

        delete: (
          rawReference: unknown,
        ): void => {
          const reference =
            rawReference as
              R148FakeDocumentReference;

          events.push(
            `cleanup:delete:${reference.id}`,
          );

          deletedDriverIds.push(
            reference.id,
          );
        },
      };

      return handler(
        transaction,
      );
    },
  } as unknown as Firestore;

  const dependencies:
    RideOfferHintPageTaskDependencies = {
      firestore,

      getTaskQueue: () => {
        events.push(
          "queue:get",
        );

        return {
          enqueue: async (
            payload,
            options,
          ) => {
            events.push(
              "queue:enqueue",
            );

            enqueues.push({
              payload,
              id: options.id,
            });
          },
        };
      },

      getMessaging: () => {
        events.push(
          "messaging:get",
        );

        return {
          sendEachForMulticast:
            async (
              message,
            ) => {
              events.push(
                "messaging:send",
              );

              messages.push(
                message,
              );

              if (
                input.batchResponse ===
                null
              ) {
                throw new Error(
                  "Unexpected fake messaging call.",
                );
              }

              return input.batchResponse;
            },
        };
      },

      warn: (
        message: string,
      ) => {
        warnings.push(
          message,
        );
      },
    };

  return {
    dependencies,
    events,
    queryOperations,
    enqueues,
    messages,
    deletedDriverIds,
    warnings,
  };
};

const r148TaskPayload = (
  dispatchId: string,
  rideId: string,
): Readonly<{
  dispatchId: string;
  rideId: string;
  expectedMatchRound: number;
  dispatchNowMillis: number;
  cursor: null;
}> => ({
  dispatchId,
  rideId,
  expectedMatchRound: 1,
  dispatchNowMillis: 1000,
  cursor: null,
});

test(
  "full page enqueues continuation before current-page target load",
  async () => {
    const driverIds =
      Array.from(
        {
          length: 500,
        },
        (_, index) =>
          `driver-${index
            .toString()
            .padStart(3, "0")}`,
      );

    const expiresAtMillis =
      driverIds.map(
        (_, index) =>
          10_000 + index,
      );

    const harness =
      r148BuildFullPathHarness({
        rideData:
          r148MatchingRideData(),
        corridorDriverIds:
          driverIds,
        corridorExpiresAtMillis:
          expiresAtMillis,
        pushTargets:
          new Map(
            driverIds.map(
              (driverId) =>
                [
                  driverId,
                  null,
                ] as const,
            ),
          ),
        batchResponse: null,
      });

    await executeRideOfferHintPageTask(
      r148TaskPayload(
        "dispatch-r148-full",
        "ride-r148-full",
      ),
      harness.dependencies,
    );

    assert.equal(
      harness.enqueues.length,
      1,
    );

    assert.equal(
      harness.enqueues[0]?.payload.cursor,
      "[10499,\"driver-499\"]",
    );

    assert.equal(
      typeof harness.enqueues[0]?.id,
      "string",
    );

    assert.equal(
      (
        harness.enqueues[0]?.id
          .length ?? 0
      ) > 0,
      true,
    );

    const enqueueIndex =
      harness.events.indexOf(
        "queue:enqueue",
      );

    const targetLoadIndex =
      harness.events.indexOf(
        "targets:getAll",
      );

    assert.notEqual(
      enqueueIndex,
      -1,
    );

    assert.notEqual(
      targetLoadIndex,
      -1,
    );

    assert.equal(
      enqueueIndex <
        targetLoadIndex,
      true,
    );

    assert.equal(
      harness.messages.length,
      0,
    );

    assert.deepEqual(
      harness.deletedDriverIds,
      [],
    );

    assert.deepEqual(
      harness.warnings,
      [],
    );

    assert.equal(
      harness.queryOperations.includes(
        "limit:500",
      ),
      true,
    );
  },
);

test(
  "partial page sends only generic Android hint without continuation",
  async () => {
    const androidDriver =
      "driver-r148-android";

    const iosDriver =
      "driver-r148-ios";

    const harness =
      r148BuildFullPathHarness({
        rideData:
          r148MatchingRideData(),
        corridorDriverIds: [
          androidDriver,
          iosDriver,
        ],
        corridorExpiresAtMillis: [
          10_000,
          10_001,
        ],
        pushTargets:
          new Map([
            [
              androidDriver,
              {
                fid:
                  "fid-r148-android-0001",
                platform:
                  "android",
                updatedAtMillis:
                  900,
              },
            ],
            [
              iosDriver,
              {
                fid:
                  "fid-r148-ios-0002",
                platform:
                  "ios",
                updatedAtMillis:
                  900,
              },
            ],
          ]),
        batchResponse: {
          successCount: 1,
          failureCount: 0,
          responses: [
            {
              success: true,
            },
          ],
        },
      });

    await executeRideOfferHintPageTask(
      r148TaskPayload(
        "dispatch-r148-send",
        "ride-r148-send",
      ),
      harness.dependencies,
    );

    assert.deepEqual(
      harness.enqueues,
      [],
    );

    assert.deepEqual(
      harness.messages,
      [
        {
          fids: [
            "fid-r148-android-0001",
          ],
          data: {
            type:
              "ride_offer_available",
          },
        },
      ],
    );

    assert.equal(
      harness.messages[0]?.fids.includes(
        "fid-r148-ios-0002",
      ),
      false,
    );

    assert.deepEqual(
      harness.deletedDriverIds,
      [],
    );

    assert.deepEqual(
      harness.warnings,
      [],
    );

    assert.equal(
      harness.events.includes(
        "cleanup:transaction",
      ),
      false,
    );
  },
);

test(
  "partial success deletes only exact current failed FID and ACKs",
  async () => {
    const successDriver =
      "driver-r148-success";

    const failedDriver =
      "driver-r148-failed";

    const successFid =
      "fid-r148-success-0001";

    const failedFid =
      "fid-r148-failed-0002";

    const pushTargets =
      new Map<
        string,
        R148FakePushTarget | null
      >([
        [
          successDriver,
          {
            fid: successFid,
            platform:
              "android",
            updatedAtMillis:
              900,
          },
        ],
        [
          failedDriver,
          {
            fid: failedFid,
            platform:
              "android",
            updatedAtMillis:
              900,
          },
        ],
      ]);

    const harness =
      r148BuildFullPathHarness({
        rideData:
          r148MatchingRideData(),
        corridorDriverIds: [
          successDriver,
          failedDriver,
        ],
        corridorExpiresAtMillis: [
          10_000,
          10_001,
        ],
        pushTargets,
        currentPushTargets:
          pushTargets,
        batchResponse: {
          successCount: 1,
          failureCount: 1,
          responses: [
            {
              success: true,
            },
            {
              success: false,
              error: {
                code:
                  "messaging/" +
                  "installation-id-" +
                  "not-registered",
              },
            },
          ],
        },
      });

    await executeRideOfferHintPageTask(
      r148TaskPayload(
        "dispatch-r148-partial",
        "ride-r148-partial",
      ),
      harness.dependencies,
    );

    assert.equal(
      harness.messages.length,
      1,
    );

    assert.deepEqual(
      harness.messages[0]?.fids,
      [
        successFid,
        failedFid,
      ],
    );

    assert.deepEqual(
      harness.deletedDriverIds,
      [
        failedDriver,
      ],
    );

    assert.deepEqual(
      harness.warnings,
      [],
    );

    assert.equal(
      harness.events.includes(
        "cleanup:transaction",
      ),
      true,
    );

    assert.equal(
      harness.events.includes(
        `cleanup:delete:${successDriver}`,
      ),
      false,
    );

    assert.equal(
      harness.events.includes(
        `cleanup:delete:${failedDriver}`,
      ),
      true,
    );
  },
);

test(
  "partial success preserves push target when current FID changed",
  async () => {
    const successDriver =
      "driver-r148-stable";

    const failedDriver =
      "driver-r148-changed";

    const successFid =
      "fid-r148-stable-0001";

    const failedFid =
      "fid-r148-old-0002";

    const initialTargets =
      new Map<
        string,
        R148FakePushTarget | null
      >([
        [
          successDriver,
          {
            fid: successFid,
            platform:
              "android",
            updatedAtMillis:
              900,
          },
        ],
        [
          failedDriver,
          {
            fid: failedFid,
            platform:
              "android",
            updatedAtMillis:
              900,
          },
        ],
      ]);

    const currentTargets =
      new Map<
        string,
        R148FakePushTarget | null
      >([
        [
          successDriver,
          {
            fid: successFid,
            platform:
              "android",
            updatedAtMillis:
              900,
          },
        ],
        [
          failedDriver,
          {
            fid:
              "fid-r148-new-0003",
            platform:
              "android",
            updatedAtMillis:
              950,
          },
        ],
      ]);

    const harness =
      r148BuildFullPathHarness({
        rideData:
          r148MatchingRideData(),
        corridorDriverIds: [
          successDriver,
          failedDriver,
        ],
        corridorExpiresAtMillis: [
          10_000,
          10_001,
        ],
        pushTargets:
          initialTargets,
        currentPushTargets:
          currentTargets,
        batchResponse: {
          successCount: 1,
          failureCount: 1,
          responses: [
            {
              success: true,
            },
            {
              success: false,
              error: {
                code:
                  "messaging/" +
                  "installation-id-" +
                  "not-registered",
              },
            },
          ],
        },
      });

    await executeRideOfferHintPageTask(
      r148TaskPayload(
        "dispatch-r148-changed",
        "ride-r148-changed",
      ),
      harness.dependencies,
    );

    assert.equal(
      harness.messages.length,
      1,
    );

    assert.deepEqual(
      harness.messages[0]?.fids,
      [
        successFid,
        failedFid,
      ],
    );

    assert.deepEqual(
      harness.deletedDriverIds,
      [],
    );

    assert.equal(
      harness.events.includes(
        "cleanup:transaction",
      ),
      true,
    );

    assert.equal(
      harness.events.includes(
        `cleanup:delete:${failedDriver}`,
      ),
      false,
    );

    assert.deepEqual(
      harness.warnings,
      [],
    );
  },
);

test(
  "zero-success batch cleans exact current failed FID then requests retry",
  async () => {
    const driverId =
      "driver-r148-zero";

    const fid =
      "fid-r148-zero-0001";

    const pushTargets =
      new Map<
        string,
        R148FakePushTarget | null
      >([
        [
          driverId,
          {
            fid,
            platform:
              "android",
            updatedAtMillis:
              900,
          },
        ],
      ]);

    const harness =
      r148BuildFullPathHarness({
        rideData:
          r148MatchingRideData(),
        corridorDriverIds: [
          driverId,
        ],
        corridorExpiresAtMillis: [
          10_000,
        ],
        pushTargets,
        currentPushTargets:
          pushTargets,
        batchResponse: {
          successCount: 0,
          failureCount: 1,
          responses: [
            {
              success: false,
              error: {
                code:
                  "messaging/" +
                  "installation-id-" +
                  "not-registered",
              },
            },
          ],
        },
      });

    await assert.rejects(
      async () => {
        await executeRideOfferHintPageTask(
          r148TaskPayload(
            "dispatch-r148-zero",
            "ride-r148-zero",
          ),
          harness.dependencies,
        );
      },
      /Ride offer hint batch requires retry\./,
    );

    assert.deepEqual(
      harness.deletedDriverIds,
      [
        driverId,
      ],
    );

    assert.equal(
      harness.events.includes(
        "cleanup:transaction",
      ),
      true,
    );

    assert.equal(
      harness.events.indexOf(
        "messaging:send",
      ) <
        harness.events.indexOf(
          "cleanup:transaction",
        ),
      true,
    );

    assert.deepEqual(
      harness.warnings,
      [],
    );
  },
);
