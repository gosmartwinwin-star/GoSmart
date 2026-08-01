class RideModel {
  final String pickupAddress;

  final String destinationAddress;

  final double distanceKm;

  final int estimatedMinutes;

  final double estimatedPrice;

  final bool searchingDriver;

  const RideModel({
    required this.pickupAddress,
    required this.destinationAddress,
    required this.distanceKm,
    required this.estimatedMinutes,
    required this.estimatedPrice,
    required this.searchingDriver,
  });

  RideModel copyWith({
    String? pickupAddress,
    String? destinationAddress,
    double? distanceKm,
    int? estimatedMinutes,
    double? estimatedPrice,
    bool? searchingDriver,
  }) {
    return RideModel(
      pickupAddress:
          pickupAddress ?? this.pickupAddress,
      destinationAddress:
          destinationAddress ??
              this.destinationAddress,
      distanceKm:
          distanceKm ?? this.distanceKm,
      estimatedMinutes:
          estimatedMinutes ??
              this.estimatedMinutes,
      estimatedPrice:
          estimatedPrice ??
              this.estimatedPrice,
      searchingDriver:
          searchingDriver ??
              this.searchingDriver,
    );
  }
}
