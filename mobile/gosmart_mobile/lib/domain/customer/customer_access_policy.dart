class CustomerAccessPolicy {
  static const double platformFee = 0.0;

  const CustomerAccessPolicy();

  bool canRequestRide({required String? authenticatedUserId}) =>
      authenticatedUserId?.trim().isNotEmpty == true;
}
