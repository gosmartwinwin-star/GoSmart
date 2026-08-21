import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/firebase_sandbox_options.dart';

void main() {
  test('all sandbox options use only the sandbox project', () {
    final options = [
      FirebaseSandboxOptions.web,
      FirebaseSandboxOptions.android,
      FirebaseSandboxOptions.ios,
      FirebaseSandboxOptions.windows,
    ];

    for (final option in options) {
      expect(option.projectId, 'gosmart-sandbox-fd8f6');

      expect(option.projectId, isNot('gosmart-fd8f6'));

      expect(option.messagingSenderId, '428312240805');
    }
  });

  test('sandbox app IDs match the registered Firebase apps', () {
    expect(
      FirebaseSandboxOptions.android.appId,
      '1:428312240805:android:14c826254f9185b74ea34c',
    );

    expect(
      FirebaseSandboxOptions.ios.appId,
      '1:428312240805:ios:49720560db2e8a584ea34c',
    );

    expect(
      FirebaseSandboxOptions.web.appId,
      '1:428312240805:web:ca44fe447e3622554ea34c',
    );

    expect(
      FirebaseSandboxOptions.windows.appId,
      '1:428312240805:web:0170f522af9604554ea34c',
    );
  });

  test('sandbox project constant is exact', () {
    expect(FirebaseSandboxOptions.projectId, 'gosmart-sandbox-fd8f6');
  });
}
