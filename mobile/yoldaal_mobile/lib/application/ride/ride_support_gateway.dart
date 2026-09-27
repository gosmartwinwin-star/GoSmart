const rideSupportCategories = <String>[
  'safety',
  'behavior',
  'fare',
  'route',
  'pickup',
  'no-show',
  'cancel',
  'vehicle',
  'technical',
  'lost-item',
];

const rideSupportUiCategories = <String>[
  'safety',
  'behavior',
  'route',
  'technical',
  'lost-item',
];

const rideSupportNoteMaxCodePoints = 500;

String rideSupportCategoryLabel(String category) => switch (category) {
  'safety' => 'G\u00FCvenlik',
  'behavior' => 'Davran\u0131\u015F / ileti\u015Fim',
  'fare' => '\u00DCcret',
  'route' => 'Yolculuk / rota sorunu',
  'pickup' => 'Al\u0131m noktas\u0131',
  'no-show' => 'Kar\u015F\u0131 taraf gelmedi',
  'cancel' => '\u0130ptal',
  'vehicle' => 'Ara\u00E7',
  'technical' => 'Teknik sorun',
  'lost-item' => 'Unutulan e\u015Fya',
  _ => category,
};

String? normalizeRideSupportNote(String? value) {
  if (value == null) {
    return null;
  }

  final normalized = value.trim();

  if (normalized.isEmpty) {
    return null;
  }

  final codePoints = normalized.runes;

  if (codePoints.length > rideSupportNoteMaxCodePoints ||
      codePoints.any(
        (codePoint) =>
            (codePoint <= 31 &&
                codePoint != 9 &&
                codePoint != 10 &&
                codePoint != 13) ||
            codePoint == 127,
      )) {
    throw ArgumentError.value(value, 'note', 'Invalid ride support note.');
  }

  return normalized;
}

class RideSupportCaseResult {
  const RideSupportCaseResult({
    required this.rideId,
    required this.caseId,
    required this.category,
    required this.createdAt,
  });

  final String rideId;
  final String caseId;
  final String category;
  final DateTime createdAt;
}

abstract interface class RideSupportGateway {
  Future<RideSupportCaseResult> createCase({
    required String rideId,
    required String category,
    required String requestId,
    String? note,
  });
}

abstract interface class RideActiveSupportGateway {
  Future<RideSupportCaseResult> createActiveCase({
    required String rideId,
    required String category,
    required String requestId,
    String? note,
  });
}
