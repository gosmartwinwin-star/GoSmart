import {
  isRideOfferHintTaskAlreadyExistsCode,
} from "./ride-background-offer-dispatch-policy.js";
import type {
  RideOfferHintTaskPayload,
} from "./ride-background-offer-dispatch-policy.js";
import {
  planRideBackgroundOfferInitialDispatch,
} from "./ride-background-offer-dispatch-trigger-authority.js";
import type {
  RideBackgroundOfferInitialDispatchPlanInput,
} from "./ride-background-offer-dispatch-trigger-authority.js";

export type RideBackgroundOfferInitialDispatchEnqueueResult =
  "skipped" |
  "enqueued" |
  "duplicate";

export type RideBackgroundOfferInitialDispatchEnqueueTask =
  (
    payload: RideOfferHintTaskPayload,
    taskId: string,
  ) => Promise<void>;

export type RideBackgroundOfferInitialDispatchEnqueueDependencies =
  Readonly<{
    enqueueTask:
      RideBackgroundOfferInitialDispatchEnqueueTask;
  }>;

const readStructuralErrorCode = (
  error: unknown,
): unknown => {
  if (
    typeof error !== "object" ||
    error === null
  ) {
    return undefined;
  }

  try {
    return (
      error as {
        code?: unknown;
      }
    ).code;
  } catch {
    return undefined;
  }
};

export const enqueueRideBackgroundOfferInitialDispatch = async (
  input: RideBackgroundOfferInitialDispatchPlanInput,
  dependencies:
    RideBackgroundOfferInitialDispatchEnqueueDependencies,
): Promise<RideBackgroundOfferInitialDispatchEnqueueResult> => {
  const plan =
    planRideBackgroundOfferInitialDispatch(
      input,
    );

  if (plan === null) {
    return "skipped";
  }

  try {
    await dependencies.enqueueTask(
      plan.payload,
      plan.taskId,
    );

    return "enqueued";
  } catch (error: unknown) {
    if (
      isRideOfferHintTaskAlreadyExistsCode(
        readStructuralErrorCode(
          error,
        ),
      )
    ) {
      return "duplicate";
    }

    throw error;
  }
};
