import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/domain/driver_application/vehicle_catalog.dart';

void main() {
  test('geçerli katalog immutable oluşturulur', () {
    final catalog = VehicleCatalog(
      version: 1,
      brands: [
        VehicleBrand(name: 'Fiat', models: ['Egea']),
      ],
    );
    expect(catalog.version, 1);
    expect(
      () => catalog.brands.add(VehicleBrand(name: 'Ford', models: ['Focus'])),
      throwsUnsupportedError,
    );
    expect(
      () => catalog.brands.first.models.add('Linea'),
      throwsUnsupportedError,
    );
  });

  test('geçersiz ve tekrarlı katalog değerleri reddedilir', () {
    expect(
      () => VehicleCatalog(version: 0, brands: const []),
      throwsFormatException,
    );
    expect(
      () => VehicleBrand(name: ' ', models: ['Egea']),
      throwsFormatException,
    );
    expect(
      () => VehicleBrand(name: 'Fiat', models: [' ']),
      throwsFormatException,
    );
    expect(
      () => VehicleBrand(name: 'Fiat', models: ['Egea', 'egea']),
      throwsFormatException,
    );
    expect(
      () => VehicleCatalog(
        version: 1,
        brands: [
          VehicleBrand(name: 'Fiat', models: ['Egea']),
          VehicleBrand(name: 'FIAT', models: ['Linea']),
        ],
      ),
      throwsFormatException,
    );
  });

  test('arama aksan ve Türkçe karakterlerden bağımsızdır, yazımı korur', () {
    expect(filterVehicleOptions(['Citroën'], ' Citroen '), ['Citroën']);
    expect(filterVehicleOptions(['Škoda'], 'skoda'), ['Škoda']);
    expect(filterVehicleOptions(['Çağdaş'], 'cagdas'), ['Çağdaş']);
    expect(filterVehicleOptions(['Fiat', 'Ford'], ''), ['Fiat', 'Ford']);
  });

  test('model yılı seçenekleri azalan ve immutable olur', () {
    final years = VehicleModelYearOptions.build(currentUtcYear: 2026);
    expect(years.first, 2027);
    expect(years.last, 1950);
    expect(years.toSet().length, years.length);
    expect(() => years.add(1949), throwsUnsupportedError);
  });
}
