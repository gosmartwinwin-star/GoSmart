import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String methodBody(String source, String signature) {
  final signatureIndex = source.indexOf(signature);
  expect(signatureIndex, isNonNegative);

  final openBraceIndex = source.indexOf('{', signatureIndex);
  expect(openBraceIndex, isNonNegative);

  var depth = 0;

  for (var index = openBraceIndex; index < source.length; index++) {
    final character = source[index];

    if (character == '{') {
      depth += 1;
      continue;
    }

    if (character == '}') {
      depth -= 1;

      if (depth == 0) {
        return source.substring(openBraceIndex + 1, index);
      }
    }
  }

  fail('Method body could not be resolved for $signature');
}

void main() {
  test('home resume retries location only when an issue is present', () {
    final source = File('lib/screens/home/home_screen.dart').readAsStringSync();

    final body = methodBody(
      source,
      'void didChangeAppLifecycleState(AppLifecycleState state)',
    );

    expect(body, contains('_voiceCallRecoveryController?.appResumed();'));
    expect(
      body,
      contains(
        RegExp(
          r'if\s*\(\s*_locationIssue\s*!=\s*null\s*\)\s*\{'
          r'\s*unawaited\(_getCurrentLocation\(\)\);\s*\}',
          multiLine: true,
        ),
      ),
    );
  });

  test('driver resume retries location only when an issue is present', () {
    final source = File(
      'lib/screens/driver/driver_center_screen.dart',
    ).readAsStringSync();

    final body = methodBody(
      source,
      'void didChangeAppLifecycleState(AppLifecycleState state)',
    );

    expect(body, contains('_liveTrackingController?.setAppResumed(resumed);'));
    expect(body, contains('_voiceCallRecoveryController?.appResumed();'));
    expect(
      body,
      contains('unawaited(_refreshDriverNotificationPermissionStatus());'),
    );
    expect(body, contains('_syncMatchOffers();'));
    expect(
      body,
      contains(
        RegExp(
          r'if\s*\(\s*controller\.locationIssue\s*!=\s*null\s*\)\s*\{'
          r'\s*unawaited\(controller\.loadLocation\(\)\);\s*\}',
          multiLine: true,
        ),
      ),
    );
  });
}
