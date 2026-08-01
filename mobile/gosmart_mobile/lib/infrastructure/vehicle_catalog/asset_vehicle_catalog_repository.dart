import 'dart:convert';

import 'package:flutter/services.dart';

import '../../application/driver_application/vehicle_catalog_repository.dart';
import '../../domain/driver_application/vehicle_catalog.dart';

class AssetVehicleCatalogRepository implements VehicleCatalogRepository {
  static const assetPath = 'assets/data/vehicle_catalog_tr.json';
  final AssetBundle _bundle;

  AssetVehicleCatalogRepository({AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  @override
  Future<VehicleCatalog> load() async {
    try {
      final root = jsonDecode(await _bundle.loadString(assetPath));
      if (root is! Map<String, dynamic> ||
          root['version'] is! int ||
          root['brands'] is! List) {
        throw const FormatException('Araç kataloğu geçersiz.');
      }
      return VehicleCatalog(
        version: root['version'] as int,
        brands: (root['brands'] as List).map((raw) {
          if (raw is! Map ||
              raw['name'] is! String ||
              raw['models'] is! List ||
              (raw['models'] as List).any((item) => item is! String)) {
            throw const FormatException('Araç kataloğu geçersiz.');
          }
          return VehicleBrand(
            name: raw['name'] as String,
            models: (raw['models'] as List).cast<String>(),
          );
        }),
      );
    } catch (error) {
      if (error is FormatException) rethrow;
      throw const FormatException('Araç kataloğu yüklenemedi.');
    }
  }
}
