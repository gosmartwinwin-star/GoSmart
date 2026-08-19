/* eslint-disable max-len, require-jsdoc */

import {createHmac} from "node:crypto";
import {
  DriverPlanPaymentInitializeInput,
  DriverPlanPaymentProvider,
  DriverPlanPaymentProviderException,
  DriverPlanPaymentSession,
} from "./driver-plan-payment-provider.js";

const CHECKOUT_FORM_PATH =
  "/payment/iyzipos/checkoutform/initialize/auth/ecom";

const ALLOWED_API_HOSTS = new Set([
  "api.iyzipay.com",
  "sandbox-api.iyzipay.com",
]);

const ALLOWED_CURRENCIES = new Set([
  "TRY",
  "USD",
  "EUR",
  "GBP",
  "NOK",
  "CHF",
]);

const DECIMAL_PATTERN = /^(0|[1-9][0-9]*)(?:\.[0-9]+)?$/u;
const hasControlCharacter = (value: string): boolean => {
  for (const character of value) {
    const codePoint = character.codePointAt(0);

    if (
      codePoint !== undefined &&
      ((codePoint >= 0 && codePoint <= 31) || codePoint === 127)
    ) {
      return true;
    }
  }

  return false;
};

export interface IyzicoHttpRequest {
  method: "POST";
  url: string;
  headers: Readonly<Record<string, string>>;
  body: string;
}

export interface IyzicoHttpResponse {
  statusCode: number;
  body: string;
}

export type IyzicoHttpCaller = (
  request: IyzicoHttpRequest,
) => Promise<IyzicoHttpResponse>;

export interface IyzicoCheckoutFormDependencies {
  apiKey: string;
  secretKey: string;
  baseUrl: string;
  randomKey: () => string;
  postJson: IyzicoHttpCaller;
}

const failure = (
  code: string,
  reason: string,
): DriverPlanPaymentProviderException =>
  new DriverPlanPaymentProviderException(code, reason);

const requireCredential = (
  value: unknown,
  reason: string,
): string => {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > 2048 ||
    hasControlCharacter(value)
  ) {
    throw failure("configuration-error", reason);
  }

  return value;
};

const requireText = (
  value: unknown,
  field: string,
  maxLength = 1024,
): string => {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > maxLength ||
    value !== value.trim() ||
    hasControlCharacter(value)
  ) {
    throw failure(
      "invalid-request",
      `invalid_${field}`,
    );
  }

  return value;
};

const requireHttpsUrl = (
  value: unknown,
  field: string,
): URL => {
  const raw = requireText(value, field, 4096);

  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch {
    throw failure(
      "invalid-request",
      `invalid_${field}`,
    );
  }

  if (
    parsed.protocol !== "https:" ||
    parsed.username.length !== 0 ||
    parsed.password.length !== 0
  ) {
    throw failure(
      "invalid-request",
      `invalid_${field}`,
    );
  }

  return parsed;
};

const requireProviderBaseUrl = (
  value: unknown,
): URL => {
  const parsed = requireHttpsUrl(
    value,
    "iyzico_base_url",
  );

  if (!ALLOWED_API_HOSTS.has(parsed.hostname)) {
    throw failure(
      "configuration-error",
      "invalid_iyzico_api_host",
    );
  }

  return parsed;
};

const requireAmountDecimal = (
  value: unknown,
): string => {
  const amount = requireText(
    value,
    "amount_decimal",
    128,
  );

  if (!DECIMAL_PATTERN.test(amount)) {
    throw failure(
      "invalid-request",
      "invalid_amount_decimal",
    );
  }

  return amount;
};

const requireCurrency = (
  value: unknown,
): string => {
  const currency = requireText(
    value,
    "currency",
    3,
  );

  if (!ALLOWED_CURRENCIES.has(currency)) {
    throw failure(
      "invalid-request",
      "unsupported_iyzico_currency",
    );
  }

  return currency;
};

const optionalObjectField = (
  value: string | undefined,
): string | undefined => value;

const responseRecord = (
  raw: string,
): Record<string, unknown> => {
  let decoded: unknown;

  try {
    decoded = JSON.parse(raw);
  } catch {
    throw failure(
      "provider-invalid-response",
      "iyzico_response_not_json",
    );
  }

  if (
    typeof decoded !== "object" ||
    decoded === null ||
    Array.isArray(decoded)
  ) {
    throw failure(
      "provider-invalid-response",
      "iyzico_response_not_object",
    );
  }

  return decoded as Record<string, unknown>;
};

const requireResponseText = (
  value: unknown,
  reason: string,
  maxLength = 4096,
): string => {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > maxLength ||
    hasControlCharacter(value)
  ) {
    throw failure(
      "provider-invalid-response",
      reason,
    );
  }

  return value;
};

const requirePaymentPageUrl = (
  value: unknown,
): string => {
  const raw = requireResponseText(
    value,
    "iyzico_payment_page_url_invalid",
    8192,
  );

  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch {
    throw failure(
      "provider-invalid-response",
      "iyzico_payment_page_url_invalid",
    );
  }

  const providerHost =
    parsed.hostname === "iyzipay.com" ||
    parsed.hostname.endsWith(".iyzipay.com");

  if (
    parsed.protocol !== "https:" ||
    !providerHost ||
    parsed.username.length !== 0 ||
    parsed.password.length !== 0
  ) {
    throw failure(
      "provider-invalid-response",
      "iyzico_payment_page_url_invalid",
    );
  }

  return raw;
};

export const buildIyzicoAuthorization = (input: {
  apiKey: string;
  secretKey: string;
  randomKey: string;
  uriPath: string;
  rawBody: string;
}): string => {
  const signaturePayload =
    input.randomKey +
    input.uriPath +
    input.rawBody;

  const signature = createHmac(
    "sha256",
    input.secretKey,
  )
    .update(signaturePayload, "utf8")
    .digest("hex");

  const authorizationSource =
    `apiKey:${input.apiKey}` +
    `&randomKey:${input.randomKey}` +
    `&signature:${signature}`;

  const encoded = Buffer
    .from(authorizationSource, "utf8")
    .toString("base64");

  return `IYZWSv2 ${encoded}`;
};

const validateInput = (
  input: DriverPlanPaymentInitializeInput,
): DriverPlanPaymentInitializeInput => {
  const purchaseOperationId = requireText(
    input.purchaseOperationId,
    "purchase_operation_id",
    256,
  );

  const conversationId = requireText(
    input.conversationId,
    "conversation_id",
    256,
  );

  const amountDecimal = requireAmountDecimal(
    input.amountDecimal,
  );

  const currency = requireCurrency(
    input.currency,
  );

  const callbackUrl = requireHttpsUrl(
    input.callbackUrl,
    "callback_url",
  ).toString();

  const buyer = {
    id: requireText(input.buyer.id, "buyer_id", 256),
    name: requireText(input.buyer.name, "buyer_name", 256),
    surname: requireText(
      input.buyer.surname,
      "buyer_surname",
      256,
    ),
    identityNumber: requireText(
      input.buyer.identityNumber,
      "buyer_identity_number",
      128,
    ),
    email: requireText(
      input.buyer.email,
      "buyer_email",
      512,
    ),
    gsmNumber: requireText(
      input.buyer.gsmNumber,
      "buyer_gsm_number",
      128,
    ),
    registrationAddress: requireText(
      input.buyer.registrationAddress,
      "buyer_registration_address",
      2048,
    ),
    city: requireText(
      input.buyer.city,
      "buyer_city",
      256,
    ),
    country: requireText(
      input.buyer.country,
      "buyer_country",
      256,
    ),
    ip: requireText(
      input.buyer.ip,
      "buyer_ip",
      128,
    ),
    zipCode: requireText(
      input.buyer.zipCode,
      "buyer_zip_code",
      64,
    ),
  };

  const billingAddress = {
    address: requireText(
      input.billingAddress.address,
      "billing_address",
      2048,
    ),
    contactName: requireText(
      input.billingAddress.contactName,
      "billing_contact_name",
      512,
    ),
    city: requireText(
      input.billingAddress.city,
      "billing_city",
      256,
    ),
    country: requireText(
      input.billingAddress.country,
      "billing_country",
      256,
    ),
    zipCode: requireText(
      input.billingAddress.zipCode,
      "billing_zip_code",
      64,
    ),
  };

  const basketItem = {
    id: requireText(
      input.basketItem.id,
      "basket_item_id",
      500,
    ),
    name: requireText(
      input.basketItem.name,
      "basket_item_name",
      512,
    ),
    category1: requireText(
      input.basketItem.category1,
      "basket_item_category_1",
      512,
    ),
    category2: input.basketItem.category2 === undefined ?
      undefined :
      requireText(
        input.basketItem.category2,
        "basket_item_category_2",
        512,
      ),
  };

  return {
    purchaseOperationId,
    conversationId,
    amountDecimal,
    currency,
    callbackUrl,
    buyer,
    billingAddress,
    basketItem,
  };
};

export class IyzicoCheckoutFormDriverPlanPaymentProvider
implements DriverPlanPaymentProvider {
  constructor(
    private readonly dependencies: IyzicoCheckoutFormDependencies,
  ) {}

  async initialize(
    rawInput: DriverPlanPaymentInitializeInput,
  ): Promise<DriverPlanPaymentSession> {
    const apiKey = requireCredential(
      this.dependencies.apiKey,
      "iyzico_api_key_unavailable",
    );

    const secretKey = requireCredential(
      this.dependencies.secretKey,
      "iyzico_secret_key_unavailable",
    );

    const baseUrl = requireProviderBaseUrl(
      this.dependencies.baseUrl,
    );

    const randomKey = requireCredential(
      this.dependencies.randomKey(),
      "iyzico_random_key_invalid",
    );

    const input = validateInput(rawInput);

    const basketItem: Record<string, string> = {
      id: input.basketItem.id,
      price: input.amountDecimal,
      name: input.basketItem.name,
      category1: input.basketItem.category1,
      itemType: "VIRTUAL",
    };

    const category2 = optionalObjectField(
      input.basketItem.category2,
    );

    if (category2 !== undefined) {
      basketItem.category2 = category2;
    }

    const requestBody = {
      locale: "tr",
      conversationId: input.conversationId,
      price: input.amountDecimal,
      paidPrice: input.amountDecimal,
      currency: input.currency,
      basketId: input.purchaseOperationId,
      paymentGroup: "PRODUCT",
      callbackUrl: input.callbackUrl,
      buyer: input.buyer,
      billingAddress: input.billingAddress,
      basketItems: [basketItem],
    };

    const rawBody = JSON.stringify(requestBody);

    const authorization = buildIyzicoAuthorization({
      apiKey,
      secretKey,
      randomKey,
      uriPath: CHECKOUT_FORM_PATH,
      rawBody,
    });

    const endpoint = new URL(
      CHECKOUT_FORM_PATH,
      baseUrl,
    ).toString();

    let response: IyzicoHttpResponse;

    try {
      response = await this.dependencies.postJson({
        method: "POST",
        url: endpoint,
        headers: {
          "Authorization": authorization,
          "Content-Type": "application/json",
          "x-iyzi-rnd": randomKey,
        },
        body: rawBody,
      });
    } catch {
      throw failure(
        "unavailable",
        "iyzico_transport_failure",
      );
    }

    if (
      !Number.isInteger(response.statusCode) ||
      typeof response.body !== "string"
    ) {
      throw failure(
        "provider-invalid-response",
        "iyzico_http_response_invalid",
      );
    }

    if (response.statusCode >= 500) {
      throw failure(
        "unavailable",
        "iyzico_provider_unavailable",
      );
    }

    if (response.statusCode !== 200) {
      throw failure(
        "provider-rejected",
        "iyzico_checkout_initialize_rejected",
      );
    }

    const decoded = responseRecord(
      response.body,
    );

    if (decoded.status !== "success") {
      throw failure(
        "provider-rejected",
        "iyzico_checkout_initialize_rejected",
      );
    }

    const responseConversationId =
      requireResponseText(
        decoded.conversationId,
        "iyzico_conversation_id_invalid",
        256,
      );

    if (
      responseConversationId !==
      input.conversationId
    ) {
      throw failure(
        "provider-invalid-response",
        "iyzico_conversation_id_mismatch",
      );
    }

    const token = requireResponseText(
      decoded.token,
      "iyzico_token_invalid",
      2048,
    );

    const paymentPageUrl =
      requirePaymentPageUrl(
        decoded.paymentPageUrl,
      );

    return {
      provider: "iyzico_checkout_form",
      purchaseOperationId:
        input.purchaseOperationId,
      conversationId:
        input.conversationId,
      token,
      paymentPageUrl,
    };
  }
}
