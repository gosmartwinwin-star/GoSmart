import {protos, v2} from "@googlemaps/routing";
import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {randomUUID} from "node:crypto";
import {
  HttpsError,
  onCall,
  onRequest,
} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {
  CoordinateInput,
  coordinatesEqual,
  durationToSeconds,
  validateCoordinate,
  validateDirection,
  validateNonNegativeInteger,
  validateRouteIndex,
} from "./route-helpers.js";
import {
  isActivePass,
  requireExactKeys,
  validateProfileStatus,
  validateRouteValidity,
} from "./driver-access-helpers.js";
import {
  buildStagingDocumentPath,
  buildSubmissionDocumentPath,
  determineSubmissionTransition,
  getRequiredDocumentTypes,
  validateApplicationPayload,
  validateDocumentMetadata,
  validateVerifiedPhone,
} from "./driver-application-helpers.js";

type ComputeRouteInput = {
  origin: CoordinateInput;
  destination: CoordinateInput;
};

type ComputeRouteDeviationInput = {
  pickupAnchor: CoordinateInput;
  pickup: CoordinateInput;
  dropoff: CoordinateInput;
  dropoffAnchor: CoordinateInput;
  pickupRouteIndex: number;
  dropoffRouteIndex: number;
};

type PublishReturnRouteInput = {
  origin: CoordinateInput;
  destination: CoordinateInput;
  validForSeconds: number;
};

type SubmitDriverApplicationInput = {
  fullName: string;
  email?: string;
  driverTaxiStandName?: string;
  driverTaxiStandAddress?: string;
  workType: "vehicleOwner" | "employedDriver" | "shiftDriver";
  vehiclePlate: string;
  vehicleBrand: string;
  vehicleModel: string;
  vehicleModelYear: number;
  registrationOwnerType: "applicant" | "otherIndividual" | "company";
  hasVehicleUseAuthorization: boolean;
  vehicleTaxiStandName?: string;
  informationAccuracyAccepted: boolean;
  documentValidityNotificationAccepted: boolean;
  documentProcessingNoticeAccepted: boolean;
  kvkkNoticeAccepted: boolean;
  termsAccepted: boolean;
  marketingConsent?: boolean;
};

const routesClient = new v2.RoutesClient();
const routing = protos.google.maps.routing.v2;
const firestore = getFirestore(getApps()[0] ?? initializeApp());
const auth = getAuth();
const storageBucket = getStorage().bucket();

const toWaypoint = (coordinate: CoordinateInput) => ({
  location: {
    latLng: {
      latitude: coordinate.latitude,
      longitude: coordinate.longitude,
    },
  },
});

const computeDrivingMeasurement = async (
  origin: CoordinateInput,
  destination: CoordinateInput,
): Promise<{distanceMeters: number; durationSeconds: number}> => {
  if (coordinatesEqual(origin, destination)) {
    return {distanceMeters: 0, durationSeconds: 0};
  }

  const [response] = await routesClient.computeRoutes(
    {
      origin: toWaypoint(origin),
      destination: toWaypoint(destination),
      travelMode: routing.RouteTravelMode.DRIVE,
      routingPreference: routing.RoutingPreference.TRAFFIC_AWARE,
      computeAlternativeRoutes: false,
      languageCode: "tr-TR",
      regionCode: "TR",
      units: routing.Units.METRIC,
    },
    {
      otherArgs: {
        headers: {
          "X-Goog-FieldMask": "routes.duration,routes.distanceMeters",
        },
      },
    },
  );

  const route = response.routes?.[0];
  const distanceMeters = validateNonNegativeInteger(route?.distanceMeters);
  const durationSeconds = durationToSeconds(route?.duration);

  if (distanceMeters === null || durationSeconds === null) {
    throw new HttpsError(
      "internal",
      "Sürüş sapması ölçümü tamamlanamadı.",
    );
  }

  return {distanceMeters, durationSeconds};
};

const safePrecondition = (reason: string) => new HttpsError(
  "failed-precondition",
  "Sürücü erişim koşulları sağlanmıyor.",
  {reason},
);

const loadDriverAccess = async (
  uid: string,
  now: Timestamp,
  getDocuments: (query: FirebaseFirestore.Query) =>
    Promise<FirebaseFirestore.QuerySnapshot>,
): Promise<string> => {
  const profileQuery = firestore.collection("driverProfiles")
    .where("authUserId", "==", uid)
    .limit(2);
  const profiles = await getDocuments(profileQuery);
  if (profiles.empty) throw safePrecondition("driver_profile_required");
  if (profiles.size > 1) throw safePrecondition("duplicate_driver_profile");

  const profile = profiles.docs[0];
  validateProfileStatus(profile.get("status"));

  const passQuery = firestore.collection("driverAccessPasses")
    .where("driverId", "==", profile.id)
    .orderBy("purchasedAt", "desc")
    .limit(1);
  const passes = await getDocuments(passQuery);
  if (passes.empty || !isActivePass(passes.docs[0].data(), now)) {
    throw safePrecondition("subscription_required");
  }
  return profile.id;
};

const validatePublishInput = (value: unknown): PublishReturnRouteInput => {
  const input = requireExactKeys(value, [
    "origin", "destination", "validForSeconds",
  ]);
  try {
    requireExactKeys(input.origin, ["latitude", "longitude"]);
    requireExactKeys(input.destination, ["latitude", "longitude"]);
    const origin = validateCoordinate(input.origin);
    const destination = validateCoordinate(input.destination);
    if (coordinatesEqual(origin, destination)) throw new Error();
    return {
      origin,
      destination,
      validForSeconds: validateRouteValidity(input.validForSeconds),
    };
  } catch (error: unknown) {
    if (
      error instanceof HttpsError &&
      (error.details as {reason?: string} | undefined)?.reason ===
        "invalid_route_validity"
    ) {
      throw error;
    }
    throw new HttpsError(
      "invalid-argument",
      "Dönüş rotası koordinatları uygun değildir.",
      {reason: "invalid_route_coordinates"},
    );
  }
};

const computePublishedRoute = async (
  origin: CoordinateInput,
  destination: CoordinateInput,
): Promise<{
  distanceMeters: number;
  durationSeconds: number;
  encodedPolyline: string;
}> => {
  const [response] = await routesClient.computeRoutes({
    origin: toWaypoint(origin),
    destination: toWaypoint(destination),
    travelMode: routing.RouteTravelMode.DRIVE,
    routingPreference: routing.RoutingPreference.TRAFFIC_AWARE,
    computeAlternativeRoutes: false,
    polylineQuality: routing.PolylineQuality.OVERVIEW,
    polylineEncoding: routing.PolylineEncoding.ENCODED_POLYLINE,
    languageCode: "tr-TR",
    regionCode: "TR",
    units: routing.Units.METRIC,
  }, {
    otherArgs: {headers: {"X-Goog-FieldMask":
      "routes.duration,routes.distanceMeters," +
      "routes.polyline.encodedPolyline"}},
  });
  const route = response.routes?.[0];
  const distanceMeters = route?.distanceMeters;
  const durationSeconds = durationToSeconds(route?.duration);
  const encodedPolyline = route?.polyline?.encodedPolyline;
  if (
    typeof distanceMeters !== "number" ||
    !Number.isInteger(distanceMeters) ||
    distanceMeters <= 0 ||
    durationSeconds === null ||
    !Number.isInteger(durationSeconds) ||
    durationSeconds <= 0 ||
    typeof encodedPolyline !== "string" ||
    encodedPolyline.length === 0
  ) {
    throw new Error("Invalid route response");
  }
  return {distanceMeters, durationSeconds, encodedPolyline};
};

export const healthCheck = onRequest(
  {
    region: "europe-west1",
  },
  (request, response) => {
    logger.info("GoSmart functions health check", {
      method: request.method,
    });
    response.status(200).json({
      success: true,
      service: "gosmart-functions",
    });
  },
);

export const computeRoute = onCall<ComputeRouteInput>(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
    minInstances: 0,
    maxInstances: 3,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Rota hesaplamak için giriş yapmalısınız.",
      );
    }

    try {
      const origin = validateCoordinate(request.data?.origin);
      const destination = validateCoordinate(request.data?.destination);

      if (coordinatesEqual(origin, destination)) {
        throw new HttpsError(
          "invalid-argument",
          "Başlangıç ve varış noktaları aynı olamaz.",
        );
      }

      const [response] = await routesClient.computeRoutes(
        {
          origin: toWaypoint(origin),
          destination: toWaypoint(destination),
          travelMode: routing.RouteTravelMode.DRIVE,
          routingPreference: routing.RoutingPreference.TRAFFIC_AWARE,
          computeAlternativeRoutes: false,
          polylineQuality: routing.PolylineQuality.OVERVIEW,
          polylineEncoding: routing.PolylineEncoding.ENCODED_POLYLINE,
          languageCode: "tr-TR",
          regionCode: "TR",
          units: routing.Units.METRIC,
        },
        {
          otherArgs: {
            headers: {
              "X-Goog-FieldMask":
                "routes.duration,routes.distanceMeters," +
                "routes.polyline.encodedPolyline",
            },
          },
        },
      );

      const route = response.routes?.[0];
      const encodedPolyline = route?.polyline?.encodedPolyline;
      const distanceMeters = route?.distanceMeters;
      const durationSeconds = durationToSeconds(route?.duration);

      if (
        typeof encodedPolyline !== "string" ||
        encodedPolyline.length === 0 ||
        typeof distanceMeters !== "number" ||
        !Number.isFinite(distanceMeters) ||
        distanceMeters < 0 ||
        durationSeconds === null
      ) {
        throw new HttpsError(
          "not-found",
          "Bu iki nokta arasında uygun bir sürüş rotası bulunamadı.",
        );
      }

      logger.info("GoSmart route computed");

      return {
        encodedPolyline,
        distanceMeters,
        durationSeconds,
      };
    } catch (error: unknown) {
      if (error instanceof HttpsError) {
        throw error;
      }

      logger.error("Google Routes request failed", {
        errorType: error instanceof Error ? error.name : "UnknownError",
      });

      throw new HttpsError(
        "unavailable",
        "Rota servisine şu anda ulaşılamıyor. Lütfen tekrar deneyin.",
      );
    }
  },
);

export const computeRouteDeviation = onCall<ComputeRouteDeviationInput>(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
    minInstances: 0,
    maxInstances: 3,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Sürüş sapması hesaplamak için giriş yapmalısınız.",
      );
    }

    try {
      const pickupAnchor = validateCoordinate(request.data?.pickupAnchor);
      const pickup = validateCoordinate(request.data?.pickup);
      const dropoff = validateCoordinate(request.data?.dropoff);
      const dropoffAnchor = validateCoordinate(request.data?.dropoffAnchor);
      const pickupRouteIndex = validateRouteIndex(
        request.data?.pickupRouteIndex,
      );
      const dropoffRouteIndex = validateRouteIndex(
        request.data?.dropoffRouteIndex,
      );

      validateDirection(pickupRouteIndex, dropoffRouteIndex);

      const [pickupMeasurement, dropoffMeasurement] = await Promise.all([
        computeDrivingMeasurement(pickupAnchor, pickup),
        computeDrivingMeasurement(dropoff, dropoffAnchor),
      ]);

      logger.info("GoSmart route deviation computed");

      return {
        pickupDetourMeters: pickupMeasurement.distanceMeters,
        pickupDetourSeconds: pickupMeasurement.durationSeconds,
        dropoffDetourMeters: dropoffMeasurement.distanceMeters,
        dropoffDetourSeconds: dropoffMeasurement.durationSeconds,
      };
    } catch (error: unknown) {
      if (error instanceof HttpsError) {
        throw error;
      }

      logger.error("Google Routes deviation request failed", {
        errorType: error instanceof Error ? error.name : "UnknownError",
      });

      throw new HttpsError(
        "unavailable",
        "Sürüş sapması servisine şu anda ulaşılamıyor.",
      );
    }
  },
);

export const submitDriverApplication =
  onCall<SubmitDriverApplicationInput>(
    {
      region: "europe-west1",
      timeoutSeconds: 120,
      memory: "512MiB",
      minInstances: 0,
      maxInstances: 3,
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError(
          "unauthenticated",
          "Sürücü başvurusu göndermek için giriş yapmalısınız.",
          {reason: "authentication_required"},
        );
      }

      const input = validateApplicationPayload(request.data);
      const uid = request.auth.uid;
      const now = Timestamp.now();
      const applicationReference = firestore
        .collection("driverApplications").doc(uid);
      const profileQuery = firestore.collection("driverProfiles")
        .where("authUserId", "==", uid)
        .limit(2);
      let tokenPhone = request.auth.token.phone_number;
      if (typeof tokenPhone !== "string" || tokenPhone.trim().length === 0) {
        try {
          tokenPhone = (await auth.getUser(uid)).phoneNumber;
        } catch (_error: unknown) {
          tokenPhone = undefined;
        }
      }
      const verifiedPhoneNumber = validateVerifiedPhone(tokenPhone);

      try {
        const [profiles, application] = await Promise.all([
          profileQuery.get(), applicationReference.get(),
        ]);
        if (profiles.size > 1) {
          throw new HttpsError(
            "internal", "Sürücü profili verileri doğrulanamadı.",
            {reason: "driver_application_data_invalid"});
        }
        if (!profiles.empty) {
          throw new HttpsError(
            "failed-precondition", "Mevcut sürücü profili bulunmaktadır.",
            {reason: "driver_profile_exists"});
        }
        determineSubmissionTransition(
          application.exists ? application.data() ?? {} : null,
        );
      } catch (error: unknown) {
        if (error instanceof HttpsError) throw error;
        throw new HttpsError("unavailable",
          "Sürücü başvurusu şu anda doğrulanamadı.",
          {reason: "driver_application_persistence_failed"});
      }

      const documentTypes = getRequiredDocumentTypes();
      const stagingDocuments = await Promise.all(documentTypes.map(
        async (documentType) => {
          const path = buildStagingDocumentPath(uid, documentType);
          const file = storageBucket.file(path);
          try {
            const [metadata] = await file.getMetadata();
            return {
              documentType, file,
              metadata: validateDocumentMetadata(documentType, metadata, uid),
            };
          } catch (error: unknown) {
            if (error instanceof HttpsError) throw error;
            throw new HttpsError("failed-precondition",
              "Zorunlu sürücü başvurusu belgeleri eksiktir.",
              {reason: "required_documents_missing"});
          }
        },
      ));

      const documentSetId = randomUUID();
      const copiedDocuments: Array<{
        documentType: typeof documentTypes[number];
        path: string;
        metadata: ReturnType<typeof validateDocumentMetadata>;
      }> = [];
      const cleanupCopiedDocuments = async () => {
        await Promise.allSettled(copiedDocuments.map((item) =>
          storageBucket.file(item.path).delete({ignoreNotFound: true})));
      };

      try {
        for (const source of stagingDocuments) {
          const path = buildSubmissionDocumentPath(
            uid, documentSetId, source.documentType,
          );
          const destination = storageBucket.file(path);
          await source.file.copy(destination);
          const [metadata] = await destination.getMetadata();
          copiedDocuments.push({
            documentType: source.documentType,
            path,
            metadata: validateDocumentMetadata(
              source.documentType, metadata, uid,
            ),
          });
        }
      } catch (_error: unknown) {
        await cleanupCopiedDocuments();
        throw new HttpsError("unavailable",
          "Sürücü başvurusu belgeleri kopyalanamadı.",
          {reason: "driver_application_document_copy_failed"});
      }

      let submissionVersion: number;

      try {
        submissionVersion = await firestore.runTransaction(
          async (transaction) => {
            const [profiles, application] = await Promise.all([
              transaction.get(profileQuery),
              transaction.get(applicationReference),
            ]);
            if (profiles.size > 1) {
              throw new HttpsError(
                "internal",
                "Sürücü profili verileri doğrulanamadı.",
                {reason: "driver_application_data_invalid"},
              );
            }
            if (!profiles.empty) {
              throw new HttpsError(
                "failed-precondition",
                "Mevcut sürücü profili için yeni başvuru oluşturulamaz.",
                {reason: "driver_profile_exists"},
              );
            }

            const transition = determineSubmissionTransition(
              application.exists ? application.data() ?? {} : null,
            );
            transaction.set(applicationReference, {
              authUserId: uid,
              verifiedPhoneNumber,
              fullName: input.fullName,
              email: input.email,
              driverTaxiStandName: input.driverTaxiStandName,
              driverTaxiStandAddress: input.driverTaxiStandAddress,
              workType: input.workType,
              vehiclePlate: input.vehiclePlate,
              vehicleBrand: input.vehicleBrand,
              vehicleModel: input.vehicleModel,
              vehicleModelYear: input.vehicleModelYear,
              registrationOwnerType: input.registrationOwnerType,
              hasVehicleUseAuthorization: input.hasVehicleUseAuthorization,
              vehicleTaxiStandName: input.vehicleTaxiStandName,
              status: "pendingReview",
              submittedAt: now,
              updatedAt: now,
              reviewedAt: null,
              rejectionReasonCode: null,
              submissionVersion: transition.submissionVersion,
              documentSetId,
              informationAccuracyAccepted: true,
              documentValidityNotificationAccepted: true,
              documentProcessingNoticeAccepted: true,
              kvkkNoticeAccepted: true,
              termsAccepted: true,
              marketingConsent: input.marketingConsent,
            });
            for (const document of copiedDocuments) {
              transaction.set(
                applicationReference.collection("documents")
                  .doc(document.documentType),
                {
                  documentType: document.documentType,
                  storagePath: document.path,
                  contentType: document.metadata.contentType,
                  sizeBytes: document.metadata.sizeBytes,
                  uploadedAt: Timestamp.fromMillis(
                    document.metadata.uploadedAtMillis,
                  ),
                  reviewStatus: "pendingReview",
                  reviewedAt: null,
                  rejectionReasonCode: null,
                  documentSetId,
                  submissionVersion: transition.submissionVersion,
                  storageGeneration: document.metadata.generation ?? null,
                },
              );
            }
            return transition.submissionVersion;
          },
        );
      } catch (error: unknown) {
        await cleanupCopiedDocuments();
        if (error instanceof HttpsError) throw error;
        logger.error("Driver application persistence failed", {
          errorType: error instanceof Error ? error.name : "UnknownError",
        });
        throw new HttpsError(
          "unavailable",
          "Sürücü başvurusu şu anda kaydedilemedi.",
          {reason: "driver_application_persistence_failed"},
        );
      }

      await Promise.allSettled(stagingDocuments.map((item) =>
        item.file.delete({ignoreNotFound: true})));

      return {
        status: "pendingReview",
        submittedAtMillis: now.toMillis(),
        updatedAtMillis: now.toMillis(),
        submissionVersion,
      };
    },
  );

export const publishReturnRoute = onCall<PublishReturnRouteInput>(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
    minInstances: 0,
    maxInstances: 3,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Dönüş rotası yayımlamak için giriş yapmalısınız.",
      );
    }

    const uid = request.auth.uid;
    const input = validatePublishInput(request.data);
    let driverId: string;
    try {
      const accessNow = Timestamp.now();
      driverId = await loadDriverAccess(
        uid,
        accessNow,
        (query) => query.get(),
      );
    } catch (error: unknown) {
      if (error instanceof HttpsError) throw error;
      throw new HttpsError(
        "internal",
        "Sürücü erişimi doğrulanamadı.",
        {reason: "route_persistence_failed"},
      );
    }

    let routeMeasurement: Awaited<ReturnType<typeof computePublishedRoute>>;
    try {
      routeMeasurement = await computePublishedRoute(
        input.origin,
        input.destination,
      );
    } catch (_error: unknown) {
      throw new HttpsError(
        "unavailable",
        "Dönüş rotası şu anda hesaplanamadı.",
        {reason: "route_computation_failed"},
      );
    }

    const now = Timestamp.now();
    const expiresAt = Timestamp.fromMillis(
      now.toMillis() + input.validForSeconds * 1000,
    );
    const routeReference = firestore.collection("driverReturnRoutes").doc();
    const lockReference = firestore.collection("driverActiveReturnRoutes")
      .doc(driverId);

    try {
      await firestore.runTransaction(async (transaction) => {
        const verifiedDriverId = await loadDriverAccess(
          uid,
          now,
          (query) => transaction.get(query),
        );
        if (verifiedDriverId !== driverId) {
          throw new HttpsError(
            "internal",
            "Sürücü erişimi doğrulanamadı.",
            {reason: "route_persistence_failed"},
          );
        }

        const lock = await transaction.get(lockReference);
        const lockExpiresAt = lock.get("expiresAt");
        if (
          lock.exists &&
          lockExpiresAt instanceof Timestamp &&
          now.toMillis() < lockExpiresAt.toMillis()
        ) {
          throw safePrecondition("active_return_route_exists");
        }

        transaction.create(routeReference, {
          driverId,
          origin: input.origin,
          destination: input.destination,
          status: "active",
          createdAt: now,
          activatedAt: now,
          expiresAt,
          routeDistanceMeters: routeMeasurement.distanceMeters,
          routeDurationSeconds: routeMeasurement.durationSeconds,
          encodedPolyline: routeMeasurement.encodedPolyline,
          pricingVersion: null,
        });
        transaction.set(lockReference, {
          routeId: routeReference.id,
          activatedAt: now,
          expiresAt,
        });
      });
    } catch (error: unknown) {
      if (error instanceof HttpsError) throw error;
      throw new HttpsError(
        "internal",
        "Dönüş rotası kaydedilemedi.",
        {reason: "route_persistence_failed"},
      );
    }

    return {
      routeId: routeReference.id,
      driverId,
      status: "active",
      activatedAtMillis: now.toMillis(),
      expiresAtMillis: expiresAt.toMillis(),
      distanceMeters: routeMeasurement.distanceMeters,
      durationSeconds: routeMeasurement.durationSeconds,
      encodedPolyline: routeMeasurement.encodedPolyline,
    };
  },
);
