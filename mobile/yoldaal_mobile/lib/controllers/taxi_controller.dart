import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/taxi_model.dart';
import '../repositories/taxi_repository.dart';

class TaxiController {
  TaxiController();

  final TaxiRepository _repository = TaxiRepository();

  final Random _random = Random();

  List<TaxiModel> taxis = [];

  Timer? _simulationTimer;

  int _simulationTick = 0;

  double? _centerLatitude;
  double? _centerLongitude;

  /// Yakındaki taksileri yükle
  void loadTaxis() {
    loadTaxisAround(latitude: 41.0082, longitude: 28.9784);
  }

  /// Taksileri belirtilen merkezin çevresinde yeniden yükle
  void loadTaxisAround({required double latitude, required double longitude}) {
    _centerLatitude = latitude;
    _centerLongitude = longitude;
    taxis = _repository.getNearbyTaxis(
      centerLatitude: latitude,
      centerLongitude: longitude,
    );
  }

  /// Test amaçlı taksileri hareket ettir
  void startSimulation(VoidCallback onUpdate) {
    _simulationTimer?.cancel();
    _simulationTick = 0;

    _simulationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final centerLatitude = _centerLatitude;
      final centerLongitude = _centerLongitude;
      var updatedTaxiCount = 0;

      taxis = taxis.map((taxi) {
        if (!taxi.online) return taxi;

        final nextLatitude = _moveCoordinate(
          current: taxi.latitude,
          center: centerLatitude,
        );
        final nextLongitude = _moveCoordinate(
          current: taxi.longitude,
          center: centerLongitude,
        );

        updatedTaxiCount++;

        return TaxiModel(
          id: taxi.id,
          driverName: taxi.driverName,
          plateNumber: taxi.plateNumber,
          vehicleType: taxi.vehicleType,
          latitude: nextLatitude,
          longitude: nextLongitude,
          online: taxi.online,
          rating: taxi.rating,
        );
      }).toList();

      _simulationTick++;
      if (kDebugMode) {
        debugPrint("Taksi simülasyon adımı: $_simulationTick");
        debugPrint("Konumu güncellenen taksi sayısı: $updatedTaxiCount");
      }

      onUpdate();
    });
  }

  double _moveCoordinate({required double current, required double? center}) {
    final movement = _randomMovementDelta();
    final candidate = current + movement;

    if (center == null || (candidate - center).abs() <= 0.02) {
      return candidate;
    }

    final returnStep = movement.abs();
    return current + (center > current ? returnStep : -returnStep);
  }

  double _randomMovementDelta() {
    final magnitude = 0.00020 + (_random.nextDouble() * 0.00035);
    return _random.nextBool() ? magnitude : -magnitude;
  }

  /// Simülasyonu durdur
  void stopSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
  }
}
