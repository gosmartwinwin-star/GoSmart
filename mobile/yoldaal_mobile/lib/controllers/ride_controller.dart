import '../models/ride_model.dart';

class RideController {
  RideModel? currentRide;

  /// Yeni yolculuk oluştur
  void createRide({
    required String pickupAddress,
    required String destinationAddress,
  }) {
    currentRide = RideModel(
      pickupAddress: pickupAddress,
      destinationAddress: destinationAddress,
      distanceKm: 0,
      estimatedMinutes: 0,
      estimatedPrice: 0,
      searchingDriver: false,
    );
  }

  /// Mesafeyi güncelle
  void updateDistance(double km) {
    if (currentRide == null) return;

    currentRide = currentRide!.copyWith(
      distanceKm: km,
    );
  }

  /// Tahmini süreyi güncelle
  void updateETA(int minutes) {
    if (currentRide == null) return;

    currentRide = currentRide!.copyWith(
      estimatedMinutes: minutes,
    );
  }

  /// Tahmini ücreti güncelle
  void updatePrice(double price) {
    if (currentRide == null) return;

    currentRide = currentRide!.copyWith(
      estimatedPrice: price,
    );
  }

  /// Sürücü aranıyor
  void startSearchingDriver() {
    if (currentRide == null) return;

    currentRide = currentRide!.copyWith(
      searchingDriver: true,
    );
  }

  /// Aramayı durdur
  void stopSearchingDriver() {
    if (currentRide == null) return;

    currentRide = currentRide!.copyWith(
      searchingDriver: false,
    );
  }

  /// Yolculuğu iptal et
  void cancelRide() {
    currentRide = null;
  }
}
