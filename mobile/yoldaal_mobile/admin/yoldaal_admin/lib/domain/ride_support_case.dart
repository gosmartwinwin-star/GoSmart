enum RideSupportCategory {
  safety('safety', 'Güvenlik'),
  behavior('behavior', 'Davranış / iletişim'),
  fare('fare', 'Ücret'),
  route('route', 'Yolculuk / rota sorunu'),
  pickup('pickup', 'Alış noktası'),
  noShow('no-show', 'Gelmedi'),
  cancel('cancel', 'İptal'),
  vehicle('vehicle', 'Araç'),
  technical('technical', 'Teknik sorun'),
  lostItem('lost-item', 'Unutulan eşya');

  const RideSupportCategory(this.wireName, this.label);
  final String wireName;
  final String label;

  static RideSupportCategory fromWire(String value) =>
      values.firstWhere((item) => item.wireName == value);
}

enum RideSupportReporterRole {
  passenger('passenger', 'Yolcu'),
  driver('driver', 'Sürücü');

  const RideSupportReporterRole(this.wireName, this.label);
  final String wireName;
  final String label;

  static RideSupportReporterRole fromWire(String value) =>
      values.firstWhere((item) => item.wireName == value);
}

final class RideSupportCaseSummary {
  const RideSupportCaseSummary({
    required this.rideId,
    required this.caseId,
    required this.reporterRole,
    required this.reporterId,
    required this.counterpartyId,
    required this.category,
    required this.reporterNote,
    required this.createdAt,
    required this.updatedAt,
  });

  final String rideId;
  final String caseId;
  final RideSupportReporterRole reporterRole;
  final String reporterId;
  final String? counterpartyId;
  final RideSupportCategory category;
  final String? reporterNote;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class RideSupportCaseCursor {
  const RideSupportCaseCursor({
    required this.createdAt,
    required this.rideId,
    required this.caseId,
  });

  final DateTime createdAt;
  final String rideId;
  final String caseId;
}

final class RideSupportCasePage {
  const RideSupportCasePage({
    required this.items,
    required this.nextCursor,
  });

  final List<RideSupportCaseSummary> items;
  final RideSupportCaseCursor? nextCursor;
}
