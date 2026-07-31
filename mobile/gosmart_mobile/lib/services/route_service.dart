import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/route_result_model.dart';
import 'polyline_service.dart';

class RouteServiceException implements Exception {
  final String message;

  const RouteServiceException(this.message);

  @override
  String toString() => message;
}

class RouteService {
  final FirebaseFunctions _functions;
  final PolylineService _polylineService;

  RouteService({FirebaseFunctions? functions, PolylineService? polylineService})
    : _functions =
          functions ??
          FirebaseFunctions.instanceFor(
            app: Firebase.app(),
            region: "europe-west1",
          ),
      _polylineService = polylineService ?? PolylineService();

  Future<RouteResultModel> getRoute({
    required LatLng pickup,
    required LatLng destination,
  }) async {
    try {
      final callable = _functions.httpsCallable(
        "computeRoute",
        options: HttpsCallableOptions(timeout: const Duration(seconds: 35)),
      );

      final result = await callable.call(<String, dynamic>{
        "origin": {"latitude": pickup.latitude, "longitude": pickup.longitude},
        "destination": {
          "latitude": destination.latitude,
          "longitude": destination.longitude,
        },
      });

      final rawData = result.data;
      if (rawData is! Map) {
        throw const RouteServiceException(
          "Rota servisinden geçersiz bir yanıt alındı.",
        );
      }

      final data = Map<String, dynamic>.from(rawData);
      final encodedPolyline = data["encodedPolyline"];
      final distanceMeters = _toPositiveInt(data["distanceMeters"]);
      final durationSeconds = _toPositiveInt(data["durationSeconds"]);

      if (encodedPolyline is! String ||
          encodedPolyline.isEmpty ||
          distanceMeters == null ||
          durationSeconds == null) {
        throw const RouteServiceException(
          "Rota servisinden geçersiz bir yanıt alındı.",
        );
      }

      final points = _polylineService.decode(encodedPolyline);
      if (points.length < 2) {
        throw const RouteServiceException(
          "Rota servisinden geçersiz bir yanıt alındı.",
        );
      }

      return RouteResultModel(
        points: points,
        distanceMeters: distanceMeters,
        durationSeconds: durationSeconds,
      );
    } on FirebaseFunctionsException catch (error) {
      throw RouteServiceException(_messageForCode(error.code));
    } on RouteServiceException {
      rethrow;
    } catch (_) {
      throw const RouteServiceException(
        "Rota oluşturulurken beklenmeyen bir sorun oluştu.",
      );
    }
  }

  int? _toPositiveInt(Object? value) {
    int? converted;

    if (value is int) {
      converted = value;
    } else if (value is num && value.isFinite) {
      converted = value.round();
    } else if (value is String) {
      converted = int.tryParse(value);
    }

    if (converted == null || converted <= 0) {
      return null;
    }

    return converted;
  }

  String _messageForCode(String code) {
    switch (code) {
      case "unauthenticated":
        return "Rota hesaplamak için yeniden giriş yapmalısınız.";
      case "invalid-argument":
        return "Seçilen başlangıç veya varış bilgisi geçersiz.";
      case "not-found":
        return "Bu iki nokta arasında uygun bir sürüş rotası bulunamadı.";
      case "deadline-exceeded":
        return "Rota hesaplama isteği zaman aşımına uğradı.";
      case "unavailable":
        return "Rota servisine şu anda ulaşılamıyor. Lütfen tekrar deneyin.";
      case "resource-exhausted":
        return "Rota servisi şu anda yoğun. Lütfen biraz sonra tekrar deneyin.";
      case "permission-denied":
        return "Rota servisi sunucu tarafından yetkilendirilemedi.";
      default:
        return "Rota oluşturulurken beklenmeyen bir sorun oluştu.";
    }
  }
}
