import {randomUUID} from "node:crypto";
import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {defineSecret, defineString} from "firebase-functions/params";
import {HttpsError, onCall, onRequest} from "firebase-functions/v2/https";

import {
  prepareDriverPlanPurchase as prepareDriverPlanPurchaseAuthority,
} from "./driver-plan-purchase-authority.js";
import {
  initializeDriverPlanCheckout as initializeDriverPlanCheckoutAuthority,
} from "./driver-plan-checkout-authority.js";
import {
  handleDriverPlanCheckoutCallback as driverPlanCheckoutCallbackAuthority,
} from "./driver-plan-checkout-callback-authority.js";
import {
  IyzicoCheckoutFormDriverPlanPaymentProvider,
} from "./iyzico-driver-plan-payment-provider.js";
import {
  getDriverPlanCatalogForActor as getDriverPlanCatalogAuthority,
} from "./driver-plan-catalog-read-authority.js";
import {
  getDriverPlanPaymentStatusForActor as getDriverPlanPaymentStatusAuthority,
} from "./driver-plan-payment-status-read-authority.js";
import {
  getMyLatestDriverPlanPaymentStatusForActor as
  getLatestDriverPlanPaymentStatusAuthority,
} from "./driver-plan-checkout-recovery-read-authority.js";

const iyzicoApiKey = defineSecret(
  "IYZICO_API_KEY",
);

const iyzicoSecretKey = defineSecret(
  "IYZICO_SECRET_KEY",
);

const iyzicoApiBaseUrl = defineString(
  "IYZICO_API_BASE_URL",
);

const iyzicoCheckoutCallbackUrl = defineString(
  "IYZICO_CHECKOUT_CALLBACK_URL",
);

const firestore =
  getFirestore(getApps()[0] ?? initializeApp());
const auth = getAuth();

export const getDriverPlanCatalog = onCall(
  {region: "europe-west1", timeoutSeconds: 15, memory: "256MiB",
    minInstances: 0, maxInstances: 3},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Driver plan catalog requires authentication.",
      );
    }

    return getDriverPlanCatalogAuthority(
      {firestore},
      request.auth.uid,
      request.data,
    );
  },
);

export const initializeDriverPlanCheckout = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
    minInstances: 0,
    maxInstances: 3,
    secrets: [
      iyzicoApiKey,
      iyzicoSecretKey,
    ],
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError(
        "unauthenticated",
        "Driver plan checkout requires authentication.",
      );
    }

    let phoneNumber:
      string | undefined;

    try {
      phoneNumber = (
        await auth.getUser(
          request.auth.uid,
        )
      ).phoneNumber;
    } catch {
      throw new HttpsError(
        "unavailable",
        "Driver identity could not be verified.",
        {
          reason:
            "driver_checkout_identity_unavailable",
        },
      );
    }

    if (
      typeof phoneNumber !== "string" ||
      phoneNumber.trim().length === 0
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Verified phone number is required.",
        {
          reason:
            "driver_verified_phone_required",
        },
      );
    }

    const ipAddress =
      request.rawRequest.ip;

    if (
      typeof ipAddress !== "string" ||
      ipAddress.trim().length === 0
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Checkout request address is unavailable.",
        {
          reason:
            "driver_checkout_ip_unavailable",
        },
      );
    }

    const provider =
      new IyzicoCheckoutFormDriverPlanPaymentProvider({
        apiKey:
          iyzicoApiKey.value(),
        secretKey:
          iyzicoSecretKey.value(),
        baseUrl:
          iyzicoApiBaseUrl.value(),
        randomKey:
          () => randomUUID(),
        postJson:
          async (providerRequest) => {
            const response =
              await fetch(
                providerRequest.url,
                {
                  method: "POST",
                  headers:
                    providerRequest.headers,
                  body:
                    providerRequest.body,
                },
              );

            return {
              statusCode:
                response.status,
              body:
                await response.text(),
            };
          },
      });

    return initializeDriverPlanCheckoutAuthority(
      {
        firestore,
        provider,
      },
      request.auth.uid,
      request.data,
      {
        gsmNumber:
          phoneNumber,
        ipAddress,
        callbackUrl:
          iyzicoCheckoutCallbackUrl.value(),
      },
    );
  },
);

export const getDriverPlanPaymentStatus = onCall(
  {region: "europe-west1", timeoutSeconds: 15, memory: "256MiB",
    minInstances: 0, maxInstances: 3},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Driver plan payment status requires authentication.",
      );
    }

    return getDriverPlanPaymentStatusAuthority(
      {firestore},
      request.auth.uid,
      request.data,
    );
  },
);

export const getMyLatestDriverPlanPaymentStatus = onCall(
  {region: "europe-west1", timeoutSeconds: 15, memory: "256MiB",
    minInstances: 0, maxInstances: 3},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Driver plan checkout recovery requires authentication.",
      );
    }

    return getLatestDriverPlanPaymentStatusAuthority(
      {firestore},
      request.auth.uid,
      request.data,
    );
  },
);

export const prepareDriverPlanPurchase = onCall(
  {region: "europe-west1", timeoutSeconds: 15, memory: "256MiB",
    minInstances: 0, maxInstances: 3},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Driver plan purchase requires authentication.",
      );
    }

    return prepareDriverPlanPurchaseAuthority(
      {firestore},
      request.auth.uid,
      request.data,
    );
  },
);

export const driverPlanCheckoutCallback = onRequest(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
    minInstances: 0,
    maxInstances: 3,
    secrets: [
      iyzicoApiKey,
      iyzicoSecretKey,
    ],
  },
  async (request, response) => {
    if (request.method !== "POST") {
      response.status(405).json({
        success: false,
      });
      return;
    }

    const retriever =
      new IyzicoCheckoutFormDriverPlanPaymentProvider({
        apiKey:
          iyzicoApiKey.value(),
        secretKey:
          iyzicoSecretKey.value(),
        baseUrl:
          iyzicoApiBaseUrl.value(),
        randomKey:
          () => randomUUID(),
        postJson:
          async (providerRequest) => {
            const providerResponse =
              await fetch(
                providerRequest.url,
                {
                  method: "POST",
                  headers:
                    providerRequest.headers,
                  body:
                    providerRequest.body,
                },
              );

            return {
              statusCode:
                providerResponse.status,
              body:
                await providerResponse.text(),
            };
          },
      });

    try {
      await driverPlanCheckoutCallbackAuthority(
        {
          firestore,
          retriever,
        },
        request.body,
      );

      response.status(200).json({
        success: true,
      });
      return;
    } catch (error: unknown) {
      let statusCode = 500;

      if (error instanceof HttpsError) {
        switch (error.code) {
        case "invalid-argument":
          statusCode = 400;
          break;
        case "not-found":
          statusCode = 404;
          break;
        case "failed-precondition":
          statusCode = 409;
          break;
        case "unavailable":
          statusCode = 503;
          break;
        default:
          statusCode = 500;
        }
      }

      response.status(statusCode).json({
        success: false,
      });
      return;
    }
  },
);
