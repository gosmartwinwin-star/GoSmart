import {
  FieldPath,
  Timestamp,
} from "firebase-admin/firestore";
import type {
  Firestore,
} from "firebase-admin/firestore";
import {
  parsePersistedDriverPushTarget,
} from "./driver-push-target-authority.js";
import {
  parseMatchingRideCandidate,
} from "./ride-match-offer-discovery.js";
import {
  buildReturnRoutePickupQueryTerms,
} from "./return-route-corridor-prefix-helpers.js";
import {
  RIDE_OFFER_HINT_QUERY_PAGE_SIZE,
  buildRideOfferHintTaskId,
  buildRideOfferHintTaskPayload,
  isRideOfferHintDispatchStillCurrent,
  isRideOfferHintTaskAlreadyExistsCode,
  parseRideOfferHintTaskPayload,
  shouldDeleteRideOfferHintPushTarget,
  shouldEnqueueNextRideOfferHintPage,
  shouldRetryRideOfferHintBatchResponse,
} from "./ride-background-offer-dispatch-policy.js";
import type {
  RideOfferHintTaskPayload,
} from "./ride-background-offer-dispatch-policy.js";

export type RideOfferHintPageTaskBatchResponse =
  Readonly<{
    successCount: number;
    failureCount: number;
    responses:
      ReadonlyArray<
        Readonly<{
          success: boolean;
          error?: Readonly<{
            code?: unknown;
          }>;
        }>
      >;
  }>;

export type RideOfferHintPageTaskMessage =
  Readonly<{
    fids: string[];
    data: Readonly<{
      type: "ride_offer_available";
    }>;
  }>;

export type RideOfferHintPageTaskQueue =
  Readonly<{
    enqueue: (
      payload: RideOfferHintTaskPayload,
      options: Readonly<{
        id: string;
      }>,
    ) => Promise<void>;
  }>;

export type RideOfferHintPageTaskMessaging =
  Readonly<{
    sendEachForMulticast: (
      message: RideOfferHintPageTaskMessage,
    ) => Promise<RideOfferHintPageTaskBatchResponse>;
  }>;

export type RideOfferHintPageTaskDependencies =
  Readonly<{
    firestore: Firestore;
    getTaskQueue:
      () => RideOfferHintPageTaskQueue;
    getMessaging:
      () => RideOfferHintPageTaskMessaging;
    warn: (message: string) => void;
  }>;

export const executeRideOfferHintPageTask = async (
  rawInput: unknown,
  dependencies: RideOfferHintPageTaskDependencies,
): Promise<void> => {
  const payload =
    parseRideOfferHintTaskPayload(
      rawInput,
    );

  if (payload === null) {
    dependencies.warn(
      "ride_offer_hint_task_invalid_payload",
    );
    return;
  }

  const rideSnapshot =
    await dependencies.firestore
      .collection("rides")
      .doc(payload.rideId)
      .get();

  const rideData =
    rideSnapshot.data();

  if (
    !rideSnapshot.exists ||
    rideData === undefined ||
    !isRideOfferHintDispatchStillCurrent({
      expectedMatchRound:
        payload.expectedMatchRound,
      currentStatus:
        rideData.status,
      currentDriverId:
        rideData.driverId,
      currentMatchRound:
        rideData.matchRound,
    })
  ) {
    return;
  }

  const ride =
    parseMatchingRideCandidate(
      payload.rideId,
      rideData,
    );

  if (ride === null) {
    return;
  }

  const pickupTerms =
    buildReturnRoutePickupQueryTerms(
      ride.pickup,
    );

  let corridorQuery =
    dependencies.firestore
      .collection(
        "driverReturnRouteCorridorIndexes",
      )
      .where(
        "corridorPrefixes",
        "array-contains-any",
        pickupTerms,
      )
      .where(
        "expiresAt",
        ">",
        Timestamp.fromMillis(
          payload.dispatchNowMillis,
        ),
      )
      .orderBy(
        "expiresAt",
        "asc",
      )
      .orderBy(
        FieldPath.documentId(),
        "asc",
      )
      .limit(
        RIDE_OFFER_HINT_QUERY_PAGE_SIZE,
      );

  if (payload.cursor !== null) {
    corridorQuery =
      corridorQuery.startAfter(
        Timestamp.fromMillis(
          payload.cursor.expiresAtMillis,
        ),
        payload.cursor.driverId,
      );
  }

  const pageSnapshot =
    await corridorQuery.get();

  if (
    shouldEnqueueNextRideOfferHintPage(
      pageSnapshot.size,
    )
  ) {
    const lastDocument =
      pageSnapshot.docs[
        pageSnapshot.docs.length - 1
      ];

    if (lastDocument === undefined) {
      throw new Error(
        "Full corridor page has no last document.",
      );
    }

    const nextCursor = {
      expiresAtMillis:
        lastDocument
          .get("expiresAt")
          .toMillis(),
      driverId:
        lastDocument.id,
    };

    const nextPayload =
      buildRideOfferHintTaskPayload({
        dispatchId:
          payload.dispatchId,
        rideId:
          payload.rideId,
        expectedMatchRound:
          payload.expectedMatchRound,
        dispatchNowMillis:
          payload.dispatchNowMillis,
        cursor:
          nextCursor,
      });

    const nextTaskId =
      buildRideOfferHintTaskId({
        dispatchId:
          payload.dispatchId,
        kind:
          "page",
        cursor:
          nextCursor,
      });

    try {
      await dependencies
        .getTaskQueue()
        .enqueue(
          nextPayload,
          {
            id: nextTaskId,
          },
        );
    } catch (error) {
      let errorCode: unknown =
        undefined;

      if (
        typeof error === "object" &&
        error !== null
      ) {
        try {
          errorCode =
            (error as {code?: unknown})
              .code;
        } catch {
          throw error;
        }
      }

      if (
        !isRideOfferHintTaskAlreadyExistsCode(
          errorCode,
        )
      ) {
        throw error;
      }
    }
  }

  if (pageSnapshot.docs.length === 0) {
    return;
  }

  const candidateDriverIds =
    pageSnapshot.docs.map(
      (document) =>
        document.id,
    );

  const pushTargetReferences =
    candidateDriverIds.map(
      (driverId) =>
        dependencies.firestore
          .collection(
            "driverPushTargets",
          )
          .doc(driverId),
    );

  const pushTargetSnapshots =
    await dependencies.firestore.getAll(
      ...pushTargetReferences,
    );

  const pushTargetReferenceByDriverId =
    new Map(
      pushTargetReferences.map(
        (reference) =>
          [
            reference.id,
            reference,
          ] as const,
      ),
    );

  const sendRecipients:
    Array<{
      driverId: string;
      fid: string;
      platform: "android";
    }> = [];

  for (
    const pushTargetSnapshot of
    pushTargetSnapshots
  ) {
    if (!pushTargetSnapshot.exists) {
      continue;
    }

    const pushTarget =
      parsePersistedDriverPushTarget(
        pushTargetSnapshot.id,
        pushTargetSnapshot.data(),
      );

    if (
      pushTarget === null ||
      pushTarget.platform !== "android"
    ) {
      continue;
    }

    sendRecipients.push({
      driverId:
        pushTarget.driverId,
      fid:
        pushTarget.fid,
      platform:
        pushTarget.platform,
    });
  }

  if (sendRecipients.length === 0) {
    return;
  }

  const sendFids =
    sendRecipients.map(
      (recipient) =>
        recipient.fid,
    );

  const batchResponse =
    await dependencies.getMessaging()
      .sendEachForMulticast({
        fids:
          sendFids,
        data: {
          type:
            "ride_offer_available",
        },
      });

  const retryWholeTask =
    shouldRetryRideOfferHintBatchResponse({
      successCount:
        batchResponse.successCount,
      failureCount:
        batchResponse.failureCount,
    });

  if (
    batchResponse.responses.length !==
    sendRecipients.length
  ) {
    if (retryWholeTask) {
      throw new Error(
        "Ride offer hint batch response length mismatch.",
      );
    }

    dependencies.warn(
      "ride_offer_hint_batch_response_length_mismatch",
    );

    return;
  }

  const failedRecipients:
    Array<{
      driverId: string;
      fid: string;
      errorCode: unknown;
    }> = [];

  for (
    let responseIndex = 0;
    responseIndex <
      batchResponse.responses.length;
    responseIndex++
  ) {
    const response =
      batchResponse.responses[
        responseIndex
      ];

    const recipient =
      sendRecipients[
        responseIndex
      ];

    if (
      response === undefined ||
      recipient === undefined
    ) {
      if (retryWholeTask) {
        throw new Error(
          "Ride offer hint response mapping invalid.",
        );
      }

      dependencies.warn(
        "ride_offer_hint_response_mapping_invalid",
      );

      return;
    }

    if (response.success) {
      continue;
    }

    failedRecipients.push({
      driverId:
        recipient.driverId,
      fid:
        recipient.fid,
      errorCode:
        response.error?.code,
    });
  }

  const cleanupFailedRecipients =
    async (): Promise<void> => {
      if (failedRecipients.length === 0) {
        return;
      }

      const cleanupCandidates =
        failedRecipients.flatMap(
          (failedRecipient) => {
            const reference =
              pushTargetReferenceByDriverId
                .get(
                  failedRecipient.driverId,
                );

            if (reference === undefined) {
              return [];
            }

            return [
              {
                failedRecipient,
                reference,
              },
            ];
          },
        );

      const cleanupCandidateByDriverId =
        new Map(
          cleanupCandidates.map(
            (candidate) =>
              [
                candidate
                  .failedRecipient
                  .driverId,
                candidate,
              ] as const,
          ),
        );

      const uniqueCleanupCandidates =
        [
          ...cleanupCandidateByDriverId
            .values(),
        ];

      if (
        uniqueCleanupCandidates.length ===
        0
      ) {
        return;
      }

      await dependencies.firestore.runTransaction(
        async (transaction) => {
          const currentSnapshots =
            await transaction.getAll(
              ...uniqueCleanupCandidates
                .map(
                  (candidate) =>
                    candidate.reference,
                ),
            );

          for (
            const currentSnapshot of
            currentSnapshots
          ) {
            const cleanupCandidate =
              cleanupCandidateByDriverId
                .get(
                  currentSnapshot.id,
                );

            if (
              cleanupCandidate ===
                undefined ||
              !currentSnapshot.exists
            ) {
              continue;
            }

            const currentTarget =
              parsePersistedDriverPushTarget(
                currentSnapshot.id,
                currentSnapshot.data(),
              );

            if (currentTarget === null) {
              continue;
            }

            if (
              !shouldDeleteRideOfferHintPushTarget({
                errorCode:
                  cleanupCandidate
                    .failedRecipient
                    .errorCode,
                failedFid:
                  cleanupCandidate
                    .failedRecipient
                    .fid,
                currentFid:
                  currentTarget.fid,
              })
            ) {
              continue;
            }

            transaction.delete(
              cleanupCandidate.reference,
            );
          }
        },
      );
    };

  if (failedRecipients.length > 0) {
    if (retryWholeTask) {
      await cleanupFailedRecipients();
    } else {
      try {
        await cleanupFailedRecipients();
      } catch {
        dependencies.warn(
          "ride_offer_hint_push_target_cleanup_failed",
        );
      }
    }
  }

  if (retryWholeTask) {
    throw new Error(
      "Ride offer hint batch requires retry.",
    );
  }
};
