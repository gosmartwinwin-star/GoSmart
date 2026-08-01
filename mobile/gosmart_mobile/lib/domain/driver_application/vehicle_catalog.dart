import 'dart:collection';

class VehicleBrand {
  final String name;
  final List<String> models;

  VehicleBrand({required String name, required Iterable<String> models})
    : name = name.trim(),
      models = List.unmodifiable(models.map((value) => value.trim())) {
    if (this.name.isEmpty || this.models.any((value) => value.isEmpty)) {
      throw const FormatException('Araç kataloğu geçersiz.');
    }
    final unique = this.models.map((value) => value.toLowerCase()).toSet();
    if (unique.length != this.models.length) {
      throw const FormatException('Araç kataloğu geçersiz.');
    }
  }
}

class VehicleCatalog {
  final int version;
  final List<VehicleBrand> brands;

  VehicleCatalog({
    required this.version,
    required Iterable<VehicleBrand> brands,
  }) : brands = UnmodifiableListView(brands.toList()) {
    if (version <= 0) throw const FormatException('Araç kataloğu geçersiz.');
    final unique = this.brands.map((value) => value.name.toLowerCase()).toSet();
    if (unique.length != this.brands.length) {
      throw const FormatException('Araç kataloğu geçersiz.');
    }
  }
}

String normalizeVehicleSearch(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll('ı', 'i')
    .replaceAll('İ', 'i')
    .replaceAll('ç', 'c')
    .replaceAll('ğ', 'g')
    .replaceAll('ö', 'o')
    .replaceAll('ş', 's')
    .replaceAll('Š', 's')
    .replaceAll('š', 's')
    .replaceAll('ü', 'u')
    .replaceAll('ë', 'e');

List<String> filterVehicleOptions(Iterable<String> values, String query) {
  final normalized = normalizeVehicleSearch(query);
  return List.unmodifiable(
    values.where((value) => normalizeVehicleSearch(value).contains(normalized)),
  );
}

class VehicleModelYearOptions {
  static List<int> build({
    required int currentUtcYear,
    int minimumYear = 1950,
  }) {
    if (currentUtcYear < minimumYear || currentUtcYear > 9998) {
      throw ArgumentError.value(currentUtcYear, 'currentUtcYear');
    }
    return List.unmodifiable([
      for (var year = currentUtcYear + 1; year >= minimumYear; year--) year,
    ]);
  }
}
