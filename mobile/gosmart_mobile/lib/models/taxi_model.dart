class TaxiModel {
  final String id;

  final String driverName;

  final String plateNumber;

  final String vehicleType;

  final double latitude;

  final double longitude;

  final bool online;

  final double rating;

  TaxiModel({
    required this.id,
    required this.driverName,
    required this.plateNumber,
    required this.vehicleType,
    required this.latitude,
    required this.longitude,
    required this.online,
    required this.rating,
  });
}