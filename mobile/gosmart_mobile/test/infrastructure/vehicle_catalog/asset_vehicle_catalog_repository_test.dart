import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/infrastructure/vehicle_catalog/asset_vehicle_catalog_repository.dart';

class Bundle extends CachingAssetBundle {
  final String value;
  Bundle(this.value);
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode(value)));
}

void main() {
  test('geçerli JSON parse edilir', () async {
    final catalog = await AssetVehicleCatalogRepository(
      bundle: Bundle(
        '{"version":1,"brands":[{"name":"Fiat","models":["Egea"]}]}',
      ),
    ).load();
    expect(catalog.brands.single.models, ['Egea']);
  });

  for (final invalid in [
    '{}',
    '{"version":1,"brands":{}}',
    '{"version":1,"brands":[{"name":"Fiat","models":{}}]}',
    '{broken',
  ]) {
    test('bozuk katalog reddedilir: $invalid', () async {
      await expectLater(
        AssetVehicleCatalogRepository(bundle: Bundle(invalid)).load(),
        throwsFormatException,
      );
    });
  }

  testWidgets('gerçek asset kataloğu yüklenir ve sentinel içermez', (
    tester,
  ) async {
    final catalog = await AssetVehicleCatalogRepository().load();
    expect(catalog.version, 1);
    expect(catalog.brands.length, 14);
    expect(catalog.brands.any((brand) => brand.name == 'Listede yok'), isFalse);
    expect(
      catalog.brands.expand((brand) => brand.models).contains('Diğer model'),
      isFalse,
    );
  });
}
