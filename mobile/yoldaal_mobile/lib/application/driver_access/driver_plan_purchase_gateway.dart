import '../../domain/subscription/driver_pass_plan.dart';

class PreparedDriverPlanPurchase {
  const PreparedDriverPlanPurchase({
    required this.purchaseOperationId,
    required this.status,
    required this.catalogVersion,
    required this.plan,
    required this.amountMinor,
    required this.currency,
  });

  final String purchaseOperationId;
  final String status;
  final String catalogVersion;
  final DriverPassPlan plan;
  final int amountMinor;
  final String currency;
}

class DriverPlanCheckoutBuyer {
  const DriverPlanCheckoutBuyer({
    required this.name,
    required this.surname,
    required this.identityNumber,
    required this.email,
    required this.registrationAddress,
    required this.city,
    required this.country,
    required this.zipCode,
  });

  final String name;
  final String surname;
  final String identityNumber;
  final String email;
  final String registrationAddress;
  final String city;
  final String country;
  final String zipCode;

  Map<String, Object?> toPayload() => <String, Object?>{
    'name': name,
    'surname': surname,
    'identityNumber': identityNumber,
    'email': email,
    'registrationAddress': registrationAddress,
    'city': city,
    'country': country,
    'zipCode': zipCode,
  };
}

class DriverPlanCheckoutBillingAddress {
  const DriverPlanCheckoutBillingAddress({
    required this.address,
    required this.contactName,
    required this.city,
    required this.country,
    required this.zipCode,
  });

  final String address;
  final String contactName;
  final String city;
  final String country;
  final String zipCode;

  Map<String, Object?> toPayload() => <String, Object?>{
    'address': address,
    'contactName': contactName,
    'city': city,
    'country': country,
    'zipCode': zipCode,
  };
}

class InitializedDriverPlanCheckout {
  const InitializedDriverPlanCheckout({
    required this.provider,
    required this.purchaseOperationId,
    required this.conversationId,
    required this.token,
    required this.paymentPageUrl,
  });

  final String provider;
  final String purchaseOperationId;
  final String conversationId;
  final String token;
  final Uri paymentPageUrl;
}

enum DriverPlanPaymentOutcome { pending, paymentFailed, paymentReview, settled }

class DriverPlanPaymentStatus {
  const DriverPlanPaymentStatus({
    required this.purchaseOperationId,
    required this.outcome,
  });

  final String purchaseOperationId;
  final DriverPlanPaymentOutcome outcome;
}

class DriverPlanPurchaseException implements Exception {
  const DriverPlanPurchaseException({required this.code, this.reason});

  final String code;
  final String? reason;
}

abstract interface class DriverPlanPurchaseGateway {
  Future<PreparedDriverPlanPurchase> prepare({
    required DriverPassPlan plan,
    required String requestId,
  });
}

abstract interface class DriverPlanCheckoutGateway {
  Future<InitializedDriverPlanCheckout> initializeCheckout({
    required String purchaseOperationId,
    required DriverPlanCheckoutBuyer buyer,
    required DriverPlanCheckoutBillingAddress billingAddress,
  });
}

abstract interface class DriverPlanPaymentStatusGateway {
  Future<DriverPlanPaymentStatus> getPaymentStatus({
    required String purchaseOperationId,
  });
}

abstract interface class DriverPlanPaymentStatusRecoveryGateway {
  Future<DriverPlanPaymentStatus?> getLatestPaymentStatus();
}
