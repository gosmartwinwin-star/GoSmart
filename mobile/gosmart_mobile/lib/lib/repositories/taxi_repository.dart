import '../models/taxi_model.dart';
import '../services/taxi_service.dart';

class TaxiRepository {
  TaxiRepository();

  List<TaxiModel> getNearbyTaxis() {
    return TaxiService.getNearbyTaxis();
  }
}