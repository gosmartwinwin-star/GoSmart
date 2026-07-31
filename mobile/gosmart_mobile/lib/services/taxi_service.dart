import '../models/taxi_model.dart';

class TaxiService {
  static List<TaxiModel> getNearbyTaxis({
    required double centerLatitude,
    required double centerLongitude,
  }) {
    return [
      TaxiModel(
        id: "taxi_001",
        driverName: "Ahmet Yılmaz",
        plateNumber: "34 T 1001",
        vehicleType: "Sedan",
        latitude: centerLatitude + 0.0012,
        longitude: centerLongitude - 0.0015,
        online: true,
        rating: 4.9,
      ),

      TaxiModel(
        id: "taxi_002",
        driverName: "Mehmet Demir",
        plateNumber: "34 T 2022",
        vehicleType: "Sedan",
        latitude: centerLatitude - 0.0018,
        longitude: centerLongitude + 0.0014,
        online: true,
        rating: 4.8,
      ),

      TaxiModel(
        id: "taxi_003",
        driverName: "Ali Kaya",
        plateNumber: "34 T 3033",
        vehicleType: "VIP",
        latitude: centerLatitude + 0.0024,
        longitude: centerLongitude + 0.0020,
        online: true,
        rating: 5.0,
      ),

      TaxiModel(
        id: "taxi_004",
        driverName: "Hasan Çelik",
        plateNumber: "34 T 4044",
        vehicleType: "Van",
        latitude: centerLatitude - 0.0030,
        longitude: centerLongitude - 0.0025,
        online: false,
        rating: 4.7,
      ),

      TaxiModel(
        id: "taxi_005",
        driverName: "Mustafa Arslan",
        plateNumber: "34 T 5055",
        vehicleType: "Sedan",
        latitude: centerLatitude + 0.0036,
        longitude: centerLongitude - 0.0032,
        online: true,
        rating: 4.9,
      ),
    ];
  }
}
