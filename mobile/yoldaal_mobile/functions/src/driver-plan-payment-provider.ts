/* eslint-disable max-len, require-jsdoc */

export interface DriverPlanPaymentBuyer {
  id: string;
  name: string;
  surname: string;
  identityNumber: string;
  email: string;
  gsmNumber: string;
  registrationAddress: string;
  city: string;
  country: string;
  ip: string;
  zipCode: string;
}

export interface DriverPlanPaymentBillingAddress {
  address: string;
  contactName: string;
  city: string;
  country: string;
  zipCode: string;
}

export interface DriverPlanPaymentBasketItem {
  id: string;
  name: string;
  category1: string;
  category2?: string;
}

export interface DriverPlanPaymentInitializeInput {
  purchaseOperationId: string;
  conversationId: string;
  amountDecimal: string;
  currency: string;
  callbackUrl: string;
  buyer: DriverPlanPaymentBuyer;
  billingAddress: DriverPlanPaymentBillingAddress;
  basketItem: DriverPlanPaymentBasketItem;
}

export interface DriverPlanPaymentSession {
  provider: string;
  purchaseOperationId: string;
  conversationId: string;
  token: string;
  paymentPageUrl: string;
}

export class DriverPlanPaymentProviderException extends Error {
  constructor(
    readonly code: string,
    readonly reason: string,
  ) {
    super(reason);
    this.name = "DriverPlanPaymentProviderException";
  }
}

export interface DriverPlanPaymentRetrieveInput {
  conversationId: string;
  token: string;
}

export interface DriverPlanPaymentRetrieveResult {
  provider: string;
  conversationId: string;
  token: string;
  paymentStatus: "SUCCESS" | "FAILURE";
  paymentId: string;
  fraudStatus: -1 | 0 | 1;
  basketId: string;
  currency: string;
  priceDecimal: string;
  paidPriceDecimal: string;
}

export interface DriverPlanPaymentRetriever {
  retrieve(
    input: DriverPlanPaymentRetrieveInput,
  ): Promise<DriverPlanPaymentRetrieveResult>;
}

export interface DriverPlanPaymentProvider {
  initialize(
    input: DriverPlanPaymentInitializeInput,
  ): Promise<DriverPlanPaymentSession>;
}
