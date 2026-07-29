import 'dart:async';
import 'dart:math';

import '../models/taxi_model.dart';
import '../repositories/taxi_repository.dart';

class TaxiController {
  TaxiController();

  final TaxiRepository _repository = TaxiRepository();

  final Random _random = Random();

  List<TaxiModel> taxis = [];

  Timer? _timer;

  /// Yakındaki taksileri yükle
  void loadTaxis() {
    taxis = _repository.getNearbyTaxis();
  }

  /// Test amaçlı taksileri hareket ettir
  void startSimulation(VoidCallback onUpdate) {
    _timer?.cancel();

    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) {
        taxis = taxis.map((taxi) {
          return TaxiModel(
            id: taxi.id,
            driverName: taxi.driverName,
            plateNumber: taxi.plateNumber,
            vehicleType: taxi.vehicleType,
            latitude: taxi.latitude +
                ((_random.nextDouble() - 0.5) * 0.0006),
            longitude: taxi.longitude +
                ((_random.nextDouble() - 0.5) * 0.0006),
            online: taxi.online,
            rating: taxi.rating,
          );
        }).toList();

        onUpdate();
      },
    );
  }

  /// Simülasyonu durdur
  void stopSimulation() {
    _timer?.cancel();
    _timer = null;
  }
}