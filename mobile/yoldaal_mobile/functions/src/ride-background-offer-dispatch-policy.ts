import {createHash} from "node:crypto";

export const RIDE_OFFER_HINT_QUERY_PAGE_SIZE = 500;

export const RIDE_OFFER_HINT_FCM_BATCH_MAX = 500;

export const RIDE_OFFER_HINT_TASK_ALREADY_EXISTS_CODE =
  "functions/task-already-exists";

export const RIDE_OFFER_HINT_UNREGISTERED_FID_CODE =
  "messaging/installation-id-not-registered";

export type RideOfferHintCursor = Readonly<{
  expiresAtMillis: number;
  driverId: string;
}>;

export type RideOfferHintTaskIdInput = Readonly<{
  dispatchId: string;
  kind: string;
  cursor: RideOfferHintCursor | null;
}>;

export type RideOfferHintFidDeleteInput = Readonly<{
  errorCode: unknown;
  failedFid: unknown;
  currentFid: unknown;
}>;

const requireNonEmptyString = (
  value: unknown,
  label: string,
): string => {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.trim() !== value
  ) {
    throw new Error(
      `${label} must be a non-empty trimmed string.`,
    );
  }

  return value;
};

const requireExpiresAtMillis = (
  value: unknown,
): number => {
  if (
    typeof value !== "number" ||
    !Number.isSafeInteger(value) ||
    value < 0
  ) {
    throw new Error(
      "expiresAtMillis must be a non-negative safe integer.",
    );
  }

  return value;
};

const normalizeCursor = (
  cursor: RideOfferHintCursor,
): RideOfferHintCursor => ({
  expiresAtMillis:
    requireExpiresAtMillis(
      cursor.expiresAtMillis,
    ),
  driverId:
    requireNonEmptyString(
      cursor.driverId,
      "driverId",
    ),
});

export const serializeRideOfferHintCursor = (
  cursor: RideOfferHintCursor,
): string => {
  const normalized =
    normalizeCursor(cursor);

  return JSON.stringify([
    normalized.expiresAtMillis,
    normalized.driverId,
  ]);
};

export const parseRideOfferHintCursor = (
  value: unknown,
): RideOfferHintCursor => {
  const serialized =
    requireNonEmptyString(
      value,
      "cursor",
    );

  const parsed: unknown =
    JSON.parse(serialized);

  if (
    !Array.isArray(parsed) ||
    parsed.length !== 2
  ) {
    throw new Error(
      "cursor must contain exactly two values.",
    );
  }

  return {
    expiresAtMillis:
      requireExpiresAtMillis(
        parsed[0],
      ),
    driverId:
      requireNonEmptyString(
        parsed[1],
        "driverId",
      ),
  };
};

export const buildRideOfferHintTaskId = (
  input: RideOfferHintTaskIdInput,
): string => {
  const dispatchId =
    requireNonEmptyString(
      input.dispatchId,
      "dispatchId",
    );

  const kind =
    requireNonEmptyString(
      input.kind,
      "kind",
    );

  const cursor =
    input.cursor === null ?
      null :
      serializeRideOfferHintCursor(
        input.cursor,
      );

  const canonical =
    JSON.stringify([
      dispatchId,
      kind,
      cursor,
    ]);

  return createHash("sha256")
    .update(canonical)
    .digest("hex");
};

export const isRideOfferHintTaskAlreadyExistsCode = (
  code: unknown,
): boolean =>
  code ===
  RIDE_OFFER_HINT_TASK_ALREADY_EXISTS_CODE;

export const shouldDeleteRideOfferHintPushTarget = (
  input: RideOfferHintFidDeleteInput,
): boolean =>
  input.errorCode ===
    RIDE_OFFER_HINT_UNREGISTERED_FID_CODE &&
  typeof input.failedFid === "string" &&
  input.failedFid.length > 0 &&
  input.failedFid === input.currentFid;

export const shouldEnqueueNextRideOfferHintPage = (
  pageLength: number,
): boolean => {
  if (
    !Number.isInteger(pageLength) ||
    pageLength < 0 ||
    pageLength >
      RIDE_OFFER_HINT_QUERY_PAGE_SIZE
  ) {
    throw new Error(
      "pageLength is outside the query page contract.",
    );
  }

  return pageLength ===
    RIDE_OFFER_HINT_QUERY_PAGE_SIZE;
};

export const RIDE_OFFER_HINT_TASK_MAX_ATTEMPTS = 2;

export const RIDE_OFFER_HINT_TASK_MIN_BACKOFF_SECONDS = 60;

export const RIDE_OFFER_HINT_TASK_MAX_BACKOFF_SECONDS = 60;

export const RIDE_OFFER_HINT_TASK_TIMEOUT_SECONDS = 120;

export const RIDE_OFFER_HINT_TASK_MAX_CONCURRENT_DISPATCHES = 1;

export const RIDE_OFFER_HINT_TASK_MAX_DISPATCHES_PER_SECOND = 1;

export type RideOfferHintDispatchRideState = Readonly<{
  expectedMatchRound: number;
  currentStatus: unknown;
  currentDriverId: unknown;
  currentMatchRound: unknown;
}>;

export type RideOfferHintBatchResult = Readonly<{
  successCount: number;
  failureCount: number;
}>;

const requirePositiveInteger = (
  value: unknown,
  label: string,
): number => {
  if (
    typeof value !== "number" ||
    !Number.isInteger(value) ||
    value <= 0
  ) {
    throw new Error(
      `${label} must be a positive integer.`,
    );
  }

  return value;
};

const requireNonNegativeInteger = (
  value: unknown,
  label: string,
): number => {
  if (
    typeof value !== "number" ||
    !Number.isInteger(value) ||
    value < 0
  ) {
    throw new Error(
      `${label} must be a non-negative integer.`,
    );
  }

  return value;
};

export const isRideOfferHintDispatchStillCurrent = (
  input: RideOfferHintDispatchRideState,
): boolean => {
  const expectedMatchRound =
    requirePositiveInteger(
      input.expectedMatchRound,
      "expectedMatchRound",
    );

  return (
    input.currentStatus === "matching" &&
    input.currentDriverId === null &&
    typeof input.currentMatchRound === "number" &&
    Number.isInteger(
      input.currentMatchRound,
    ) &&
    input.currentMatchRound > 0 &&
    input.currentMatchRound ===
      expectedMatchRound
  );
};

export const shouldRetryRideOfferHintBatchResponse = (
  input: RideOfferHintBatchResult,
): boolean => {
  const successCount =
    requireNonNegativeInteger(
      input.successCount,
      "successCount",
    );

  const failureCount =
    requireNonNegativeInteger(
      input.failureCount,
      "failureCount",
    );

  if (
    successCount === 0 &&
    failureCount === 0
  ) {
    throw new Error(
      "Batch response must contain at least one target.",
    );
  }

  return (
    successCount === 0 &&
    failureCount > 0
  );
};

export type RideOfferHintTaskPayload = Readonly<{
  dispatchId: string;
  rideId: string;
  expectedMatchRound: number;
  dispatchNowMillis: number;
  cursor: string | null;
}>;

export type ParsedRideOfferHintTaskPayload = Readonly<{
  dispatchId: string;
  rideId: string;
  expectedMatchRound: number;
  dispatchNowMillis: number;
  cursor: RideOfferHintCursor | null;
}>;

const plainTaskRecord = (
  value: unknown,
): Record<string, unknown> | null => {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value) ||
    Object.getPrototypeOf(value) !==
      Object.prototype
  ) {
    return null;
  }

  return value as Record<string, unknown>;
};

const requireDispatchNowMillis = (
  value: unknown,
): number => {
  if (
    typeof value !== "number" ||
    !Number.isSafeInteger(value) ||
    value < 0
  ) {
    throw new Error(
      "dispatchNowMillis must be a non-negative safe integer.",
    );
  }

  return value;
};

export const buildRideOfferHintTaskPayload = (
  input: ParsedRideOfferHintTaskPayload,
): RideOfferHintTaskPayload => ({
  dispatchId:
    requireNonEmptyString(
      input.dispatchId,
      "dispatchId",
    ),
  rideId:
    requireNonEmptyString(
      input.rideId,
      "rideId",
    ),
  expectedMatchRound:
    requirePositiveInteger(
      input.expectedMatchRound,
      "expectedMatchRound",
    ),
  dispatchNowMillis:
    requireDispatchNowMillis(
      input.dispatchNowMillis,
    ),
  cursor:
    input.cursor === null ?
      null :
      serializeRideOfferHintCursor(
        input.cursor,
      ),
});

export const parseRideOfferHintTaskPayload = (
  value: unknown,
): ParsedRideOfferHintTaskPayload | null => {
  const data =
    plainTaskRecord(value);

  if (data === null) {
    return null;
  }

  const keys =
    Object.keys(data).sort();

  if (
    keys.length !== 5 ||
    keys[0] !== "cursor" ||
    keys[1] !== "dispatchId" ||
    keys[2] !== "dispatchNowMillis" ||
    keys[3] !== "expectedMatchRound" ||
    keys[4] !== "rideId" ||
    (
      data.cursor !== null &&
      typeof data.cursor !== "string"
    )
  ) {
    return null;
  }

  try {
    return {
      dispatchId:
        requireNonEmptyString(
          data.dispatchId,
          "dispatchId",
        ),
      rideId:
        requireNonEmptyString(
          data.rideId,
          "rideId",
        ),
      expectedMatchRound:
        requirePositiveInteger(
          data.expectedMatchRound,
          "expectedMatchRound",
        ),
      dispatchNowMillis:
        requireDispatchNowMillis(
          data.dispatchNowMillis,
        ),
      cursor:
        data.cursor === null ?
          null :
          parseRideOfferHintCursor(
            data.cursor,
          ),
    };
  } catch {
    return null;
  }
};

export type RideOfferHintInitialDispatchInput = Readonly<{
  eventId: unknown;
  eventTime: unknown;
  rideId: unknown;
  matchRound: unknown;
}>;

export type RideOfferHintInitialDispatchEnvelope = Readonly<{
  taskId: string;
  payload: RideOfferHintTaskPayload;
}>;

export const buildRideOfferHintInitialDispatchEnvelope = (
  input: RideOfferHintInitialDispatchInput,
): RideOfferHintInitialDispatchEnvelope | null => {
  try {
    const dispatchId =
      requireNonEmptyString(
        input.eventId,
        "eventId",
      );

    const eventTime =
      requireNonEmptyString(
        input.eventTime,
        "eventTime",
      );

    const rideId =
      requireNonEmptyString(
        input.rideId,
        "rideId",
      );

    const expectedMatchRound =
      requirePositiveInteger(
        input.matchRound,
        "matchRound",
      );

    const dispatchNowMillis =
      Date.parse(eventTime);

    if (
      !Number.isSafeInteger(
        dispatchNowMillis,
      ) ||
      dispatchNowMillis < 0
    ) {
      return null;
    }

    const payload =
      buildRideOfferHintTaskPayload({
        dispatchId,
        rideId,
        expectedMatchRound,
        dispatchNowMillis,
        cursor: null,
      });

    return {
      taskId:
        buildRideOfferHintTaskId({
          dispatchId,
          kind: "page",
          cursor: null,
        }),
      payload,
    };
  } catch {
    return null;
  }
};
