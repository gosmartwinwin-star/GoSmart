import '../models/taxi_model.dart';
import '../services/taxi_service.dart';

class TaxiRepository {
  TaxiRepository();

  List<TaxiModel> getNearbyTaxis({
    required double centerLatitude,
    required double centerLongitude,
  }) {
    return TaxiService.getNearbyTaxis(
      centerLatitude: centerLatitude,
      centerLongitude: centerLongitude,
    );
  }
}
