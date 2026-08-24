import 'dart:convert';
import 'dart:math';

String secureRideRequestId() {
  final random = Random.secure();
  return base64Url.encode(List<int>.generate(24, (_) => random.nextInt(256))).replaceAll('=', '');
}
