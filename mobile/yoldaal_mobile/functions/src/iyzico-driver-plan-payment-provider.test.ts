/* eslint-disable max-len, require-jsdoc */

import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {
  DriverPlanPaymentInitializeInput,
  DriverPlanPaymentProviderException,
} from "./driver-plan-payment-provider.js";
import {
  buildIyzicoAuthorization,
  IyzicoCheckoutFormDependencies,
  IyzicoCheckoutFormDriverPlanPaymentProvider,
  IyzicoHttpRequest,
} from "./iyzico-driver-plan-payment-provider.js";

const input = (): DriverPlanPaymentInitializeInput => ({
  purchaseOperationId: "purchase-op-123456",
  conversationId: "conversation-123456",
  amountDecimal: "10.50",
  currency: "TRY",
  callbackUrl: "https://example.com/iyzico/callback",
  buyer: {
    id: "driver-1",
    name: "Test",
    surname: "Driver",
    identityNumber: "11111111111",
    email: "driver@example.com",
    gsmNumber: "+905350000000",
    registrationAddress: "Test Address 1",
    city: "Istanbul",
    country: "Turkey",
    ip: "203.0.113.10",
    zipCode: "34000",
  },
  billingAddress: {
    address: "Test Billing Address 1",
    contactName: "Test Driver",
    city: "Istanbul",
    country: "Turkey",
    zipCode: "34000",
  },
  basketItem: {
    id: "driver-plan-daily",
    name: "Driver access plan",
    category1: "Driver access",
  },
});

const successBody = (
  conversationId = "conversation-123456",
) => JSON.stringify({
  status: "success",
  locale: "tr",
  systemTime: 1770000000000,
  conversationId,
  token: "checkout-token-123",
  paymentPageUrl:
    "https://sandbox-cpp.iyzipay.com?token=checkout-token-123",
  signature: "provider-signature-not-consumed-here",
});

const dependencies = (
  caller: (
    request: IyzicoHttpRequest,
  ) => Promise<{
    statusCode: number;
    body: string;
  }>,
): IyzicoCheckoutFormDependencies => ({
  apiKey: "api-key",
  secretKey: "secret-key",
  baseUrl: "https://sandbox-api.iyzipay.com",
  randomKey: () => "random-123",
  postJson: caller,
});

const reasonIs = (
  expected: string,
) => (error: unknown): boolean =>
  error instanceof DriverPlanPaymentProviderException &&
  error.reason === expected;

test("IYZWSv2 authorization follows deterministic HMAC contract", () => {
  const authorization = buildIyzicoAuthorization({
    apiKey: "api-key",
    secretKey: "secret-key",
    randomKey: "random-123",
    uriPath:
      "/payment/iyzipos/checkoutform/initialize/auth/ecom",
    rawBody: "{\"price\":\"10.50\"}",
  });

  assert.equal(
    authorization,
    "IYZWSv2 YXBpS2V5OmFwaS1rZXkmcmFuZG9tS2V5OnJhbmRvbS0xMjMmc2lnbmF0dXJlOjFjYzI1MjMyNDRhNWE1YzgxYzgyOGU0YzIyNDQxYWNhYjQxOTkxNjAzNWViMmVjYWIzYzE2N2YyZGUxMWUxYTY=",
  );
});

test("checkout initialize sends signed server-side virtual basket request", async () => {
  let captured: IyzicoHttpRequest | undefined;

  const provider =
    new IyzicoCheckoutFormDriverPlanPaymentProvider(
      dependencies(async (request) => {
        captured = request;
        return {
          statusCode: 200,
          body: successBody(),
        };
      }),
    );

  const result = await provider.initialize(
    input(),
  );

  assert.ok(captured);

  assert.equal(
    captured.method,
    "POST",
  );

  assert.equal(
    captured.url,
    "https://sandbox-api.iyzipay.com/payment/iyzipos/checkoutform/initialize/auth/ecom",
  );

  assert.equal(
    captured.headers["Content-Type"],
    "application/json",
  );

  assert.equal(
    captured.headers["x-iyzi-rnd"],
    "random-123",
  );

  assert.match(
    captured.headers.Authorization,
    /^IYZWSv2 /u,
  );

  const body = JSON.parse(
    captured.body,
  ) as Record<string, unknown>;

  assert.equal(
    body.locale,
    "tr",
  );

  assert.equal(
    body.price,
    "10.50",
  );

  assert.equal(
    body.paidPrice,
    "10.50",
  );

  assert.equal(
    body.currency,
    "TRY",
  );

  assert.equal(
    body.basketId,
    "purchase-op-123456",
  );

  assert.equal(
    body.paymentGroup,
    "PRODUCT",
  );

  assert.equal(
    Object.prototype.hasOwnProperty.call(
      body,
      "shippingAddress",
    ),
    false,
  );

  const basketItems =
    body.basketItems as Array<Record<string, unknown>>;

  assert.equal(
    basketItems.length,
    1,
  );

  assert.equal(
    basketItems[0].price,
    "10.50",
  );

  assert.equal(
    basketItems[0].itemType,
    "VIRTUAL",
  );

  assert.deepEqual(
    result,
    {
      provider: "iyzico_checkout_form",
      purchaseOperationId:
        "purchase-op-123456",
      conversationId:
        "conversation-123456",
      token: "checkout-token-123",
      paymentPageUrl:
        "https://sandbox-cpp.iyzipay.com?token=checkout-token-123",
    },
  );
});

test("adapter does not derive provider amount from minor units", async () => {
  let captured: IyzicoHttpRequest | undefined;

  const provider =
    new IyzicoCheckoutFormDriverPlanPaymentProvider(
      dependencies(async (request) => {
        captured = request;
        return {
          statusCode: 200,
          body: successBody(),
        };
      }),
    );

  await provider.initialize(
    input(),
  );

  assert.ok(captured);

  assert.match(
    captured.body,
    /"price":"10\.50"/u,
  );

  assert.equal(
    captured.body.includes("amountMinor"),
    false,
  );
});

test("unsupported iyzico currency fails before transport", async () => {
  let calls = 0;

  const provider =
    new IyzicoCheckoutFormDriverPlanPaymentProvider(
      dependencies(async () => {
        calls += 1;
        return {
          statusCode: 200,
          body: successBody(),
        };
      }),
    );

  await assert.rejects(
    () => provider.initialize({
      ...input(),
      currency: "XYZ",
    }),
    reasonIs(
      "unsupported_iyzico_currency",
    ),
  );

  assert.equal(calls, 0);
});

test("non-canonical decimal amount fails before transport", async () => {
  let calls = 0;

  const provider =
    new IyzicoCheckoutFormDriverPlanPaymentProvider(
      dependencies(async () => {
        calls += 1;
        return {
          statusCode: 200,
          body: successBody(),
        };
      }),
    );

  await assert.rejects(
    () => provider.initialize({
      ...input(),
      amountDecimal: "1e2",
    }),
    reasonIs(
      "invalid_amount_decimal",
    ),
  );

  assert.equal(calls, 0);
});

test("non-https callback fails before transport", async () => {
  let calls = 0;

  const provider =
    new IyzicoCheckoutFormDriverPlanPaymentProvider(
      dependencies(async () => {
        calls += 1;
        return {
          statusCode: 200,
          body: successBody(),
        };
      }),
    );

  await assert.rejects(
    () => provider.initialize({
      ...input(),
      callbackUrl: "http://example.com/callback",
    }),
    reasonIs(
      "invalid_callback_url",
    ),
  );

  assert.equal(calls, 0);
});

test("provider base URL is restricted to iyzico API hosts", async () => {
  const provider =
    new IyzicoCheckoutFormDriverPlanPaymentProvider({
      ...dependencies(async () => ({
        statusCode: 200,
        body: successBody(),
      })),
      baseUrl: "https://attacker.example.com",
    });

  await assert.rejects(
    () => provider.initialize(input()),
    reasonIs(
      "invalid_iyzico_api_host",
    ),
  );
});

test("transport failures are sanitized", async () => {
  const provider =
    new IyzicoCheckoutFormDriverPlanPaymentProvider(
      dependencies(async () => {
        throw new Error(
          "raw transport details",
        );
      }),
    );

  await assert.rejects(
    () => provider.initialize(input()),
    reasonIs(
      "iyzico_transport_failure",
    ),
  );
});

test("provider failure response cannot create a checkout session", async () => {
  const provider =
    new IyzicoCheckoutFormDriverPlanPaymentProvider(
      dependencies(async () => ({
        statusCode: 200,
        body: JSON.stringify({
          status: "failure",
          errorCode: "provider-internal-code",
          errorMessage: "raw provider error",
        }),
      })),
    );

  await assert.rejects(
    () => provider.initialize(input()),
    reasonIs(
      "iyzico_checkout_initialize_rejected",
    ),
  );
});

test("conversation mismatch fails closed", async () => {
  const provider =
    new IyzicoCheckoutFormDriverPlanPaymentProvider(
      dependencies(async () => ({
        statusCode: 200,
        body: successBody(
          "different-conversation",
        ),
      })),
    );

  await assert.rejects(
    () => provider.initialize(input()),
    reasonIs(
      "iyzico_conversation_id_mismatch",
    ),
  );
});

test("non-iyzico payment page URL fails closed", async () => {
  const provider =
    new IyzicoCheckoutFormDriverPlanPaymentProvider(
      dependencies(async () => ({
        statusCode: 200,
        body: JSON.stringify({
          status: "success",
          conversationId:
            "conversation-123456",
          token: "checkout-token-123",
          paymentPageUrl:
            "https://attacker.example.com/pay",
        }),
      })),
    );

  await assert.rejects(
    () => provider.initialize(input()),
    reasonIs(
      "iyzico_payment_page_url_invalid",
    ),
  );
});

test("malformed provider JSON fails closed", async () => {
  const provider =
    new IyzicoCheckoutFormDriverPlanPaymentProvider(
      dependencies(async () => ({
        statusCode: 200,
        body: "{not-json",
      })),
    );

  await assert.rejects(
    () => provider.initialize(input()),
    reasonIs(
      "iyzico_response_not_json",
    ),
  );
});

test("server-only adapter contains no settlement or entitlement wiring", () => {
  const source = readFileSync(
    "src/iyzico-driver-plan-payment-provider.ts",
    "utf8",
  );

  assert.equal(
    source.includes(
      "settleDriverPlanPurchase",
    ),
    false,
  );

  assert.equal(
    source.includes(
      "driverAccessPasses",
    ),
    false,
  );

  assert.equal(
    source.includes(
      "amountMinor",
    ),
    false,
  );

  assert.equal(
    source.includes(
      "firebase-functions",
    ),
    false,
  );
});
const retrieveOperationId =
  "a".repeat(64);

const retrieveResponseSignature =
  "b40df2ec04458f9e9cd3388bc2b960f39caf30c345b2235d37debf6d7507e0d6";

test("checkout form retrieve verifies signed response and canonical prices", async () => {
  let captured:
    IyzicoHttpRequest | undefined;

  const provider =
    new IyzicoCheckoutFormDriverPlanPaymentProvider({
      apiKey: "api-key",
      secretKey: "secret-key",
      baseUrl:
        "https://sandbox-api.iyzipay.com",
      randomKey: () =>
        "retrieve-random-key",
      postJson: async (request) => {
        captured = request;

        return {
          statusCode: 200,
          body: JSON.stringify({
            status: "success",
            paymentStatus: "SUCCESS",
            paymentId: "payment-123",
            fraudStatus: 1,
            currency: "TRY",
            basketId:
              retrieveOperationId,
            conversationId:
              "conversation-123",
            paidPrice: 123.45,
            price: "123.450",
            token:
              "checkout-token-123",
            signature:
              retrieveResponseSignature,
          }),
        };
      },
    });

  const result =
    await provider.retrieve({
      conversationId:
        "conversation-123",
      token:
        "checkout-token-123",
    });

  assert.ok(captured);

  assert.equal(
    captured.url,
    "https://sandbox-api.iyzipay.com/payment/iyzipos/checkoutform/auth/ecom/detail",
  );

  assert.equal(
    captured.method,
    "POST",
  );

  assert.equal(
    captured.headers[
      "x-iyzi-rnd"
    ],
    "retrieve-random-key",
  );

  assert.match(
    captured.headers.Authorization,
    /^IYZWSv2 /u,
  );

  assert.deepEqual(
    JSON.parse(captured.body),
    {
      locale: "tr",
      conversationId:
        "conversation-123",
      token:
        "checkout-token-123",
    },
  );

  assert.deepEqual(
    result,
    {
      provider:
        "iyzico_checkout_form",
      conversationId:
        "conversation-123",
      token:
        "checkout-token-123",
      paymentStatus: "SUCCESS",
      paymentId:
        "payment-123",
      fraudStatus: 1,
      basketId:
        retrieveOperationId,
      currency: "TRY",
      priceDecimal:
        "123.45",
      paidPriceDecimal:
        "123.45",
    },
  );
});

test("checkout form retrieve rejects invalid response signature", async () => {
  const provider =
    new IyzicoCheckoutFormDriverPlanPaymentProvider({
      apiKey: "api-key",
      secretKey: "secret-key",
      baseUrl:
        "https://sandbox-api.iyzipay.com",
      randomKey: () =>
        "retrieve-random-key",
      postJson: async () => ({
        statusCode: 200,
        body: JSON.stringify({
          status: "success",
          paymentStatus: "SUCCESS",
          paymentId: "payment-123",
          fraudStatus: 1,
          currency: "TRY",
          basketId:
            retrieveOperationId,
          conversationId:
            "conversation-123",
          paidPrice: "123.45",
          price: "123.45",
          token:
            "checkout-token-123",
          signature:
            "0".repeat(64),
        }),
      }),
    });

  await assert.rejects(
    () =>
      provider.retrieve({
        conversationId:
          "conversation-123",
        token:
          "checkout-token-123",
      }),
    (error: unknown) =>
      error instanceof
        DriverPlanPaymentProviderException &&
      error.reason ===
        "iyzico_checkout_retrieve_signature_invalid",
  );
});

test("checkout form retrieve transport failure remains unavailable", async () => {
  const provider =
    new IyzicoCheckoutFormDriverPlanPaymentProvider({
      apiKey: "api-key",
      secretKey: "secret-key",
      baseUrl:
        "https://sandbox-api.iyzipay.com",
      randomKey: () =>
        "retrieve-random-key",
      postJson: async () => {
        throw new Error(
          "simulated transport failure",
        );
      },
    });

  await assert.rejects(
    () =>
      provider.retrieve({
        conversationId:
          "conversation-123",
        token:
          "checkout-token-123",
      }),
    (error: unknown) =>
      error instanceof
        DriverPlanPaymentProviderException &&
      error.code ===
        "unavailable" &&
      error.reason ===
        "iyzico_checkout_retrieve_transport_failure",
  );
});
