import '../../domain/driver_application/vehicle_catalog.dart';

abstract interface class VehicleCatalogRepository {
  Future<VehicleCatalog> load();
}
