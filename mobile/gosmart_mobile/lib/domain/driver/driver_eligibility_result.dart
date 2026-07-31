import 'dart:collection';

class DriverEligibilityResult {
  final bool authenticated;
  final bool driverProfilePresent;
  final bool identityCompatible;
  final bool driverApproved;
  final bool subscriptionActive;
  final List<String> rejectionReasons;

  DriverEligibilityResult({
    required this.authenticated,
    required this.driverProfilePresent,
    required this.identityCompatible,
    required this.driverApproved,
    required this.subscriptionActive,
    required Iterable<String> rejectionReasons,
  }) : rejectionReasons = List<String>.unmodifiable(
         LinkedHashSet<String>.from(rejectionReasons),
       );

  bool get canUseDriverPlatform =>
      authenticated &&
      driverProfilePresent &&
      identityCompatible &&
      driverApproved &&
      subscriptionActive &&
      rejectionReasons.isEmpty;
}
