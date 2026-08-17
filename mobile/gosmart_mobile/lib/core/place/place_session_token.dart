import 'dart:math';

typedef PlaceSessionBytesFactory = List<int> Function(int length);

String createPlaceSessionToken({PlaceSessionBytesFactory? bytesFactory}) {
  final factory = bytesFactory ?? _secureBytes;
  final bytes = factory(16);

  if (bytes.length != 16 || bytes.any((value) => value < 0 || value > 255)) {
    throw ArgumentError.value(
      bytes,
      'bytes',
      'Exactly 16 byte values are required.',
    );
  }

  final normalized = List<int>.from(bytes);

  normalized[6] = (normalized[6] & 0x0f) | 0x40;

  normalized[8] = (normalized[8] & 0x3f) | 0x80;

  final hex = normalized
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();

  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

List<int> _secureBytes(int length) {
  final random = Random.secure();

  return List<int>.generate(
    length,
    (_) => random.nextInt(256),
    growable: false,
  );
}
