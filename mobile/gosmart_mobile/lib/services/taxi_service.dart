import '../models/taxi_model.dart';

class TaxiService {
  static List<TaxiModel> getNearbyTaxis() {
    return [

      TaxiModel(
        id: "taxi_001",
        driverName: "Ahmet Yılmaz",
        plateNumber: "34 T 1001",
        vehicleType: "Sedan",
        latitude: 37.4223,
        longitude: -122.0841,
        online: true,
        rating: 4.9,
      ),

      TaxiModel(
        id: "taxi_002",
        driverName: "Mehmet Demir",
        plateNumber: "34 T 2022",
        vehicleType: "Sedan",
        latitude: 37.4215,
        longitude: -122.0828,
        online: true,
        rating: 4.8,
      ),

      TaxiModel(
        id: "taxi_003",
        driverName: "Ali Kaya",
        plateNumber: "34 T 3033",
        vehicleType: "VIP",
        latitude: 37.4209,
        longitude: -122.0836,
        online: true,
        rating: 5.0,
      ),

      TaxiModel(
        id: "taxi_004",
        driverName: "Hasan Çelik",
        plateNumber: "34 T 4044",
        vehicleType: "Van",
        latitude: 37.4230,
        longitude: -122.0850,
        online: false,
        rating: 4.7,
      ),

      TaxiModel(
        id: "taxi_005",
        driverName: "Mustafa Arslan",
        plateNumber: "34 T 5055",
        vehicleType: "Sedan",
        latitude: 37.4220,
        longitude: -122.0860,
        online: true,
        rating: 4.9,
      ),
    ];
  }
}