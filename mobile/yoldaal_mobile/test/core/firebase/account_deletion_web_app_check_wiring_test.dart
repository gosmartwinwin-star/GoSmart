import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dedicated web entrypoint wires enterprise App Check fail closed', () {
    final source = File(
      'lib/account_deletion_web_main.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('ACCOUNT_DELETION_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY'),
    );
    expect(
      source,
      contains('providerWeb: ReCaptchaEnterpriseProvider(_appCheckSiteKey)'),
    );
    expect(source, contains("if (_appCheckSiteKey.trim().isEmpty)"));
    expect(source, contains('FirebaseFunctionsRegistry.configure(app: app)'));
    expect(source, isNot(contains('AndroidProvider.debug')));
    expect(source, isNot(contains('AppleProvider.debug')));
  });

  test(
    'web auth service uses browser Firebase Auth without direct deletion',
    () {
      final source = File(
        'lib/services/account_deletion_web_auth_service.dart',
      ).readAsStringSync();

      expect(source, contains('signInWithPopup(GoogleAuthProvider())'));
      expect(source, contains('signInWithPhoneNumber(phoneNumber)'));
      expect(source, contains('confirmation.confirm(normalized)'));
      expect(source, isNot(contains('currentUser.delete')));
      expect(source, isNot(contains('.delete()')));
    },
  );

  test('web screen keeps backend UID authority and exact service sequence', () {
    final source = File(
      'lib/screens/account_deletion_web/account_deletion_web_screen.dart',
    ).readAsStringSync();

    final requestIndex = source.indexOf('await widget.requestDeletion()');
    final executeIndex = source.indexOf('await widget.executeDeletion()');
    final signOutIndex = source.lastIndexOf('await widget.signOut()');

    expect(requestIndex, greaterThanOrEqualTo(0));
    expect(executeIndex, greaterThan(requestIndex));
    expect(signOutIndex, greaterThan(executeIndex));
    expect(source, isNot(contains('FirebaseAuth.currentUser.delete')));
    expect(source, isNot(contains('driverId:')));
    expect(source, isNot(contains('uid:')));
  });

  test('existing deletion services keep exact empty callable payloads', () {
    final request = File(
      'lib/services/account_deletion_request_service.dart',
    ).readAsStringSync();
    final execution = File(
      'lib/services/account_deletion_execution_service.dart',
    ).readAsStringSync();

    expect(
      request,
      contains('FirebaseFunctionsRegistry.requestAccountDeletion'),
    );
    expect(request, contains('call(<String, dynamic>{})'));
    expect(
      execution,
      contains('FirebaseFunctionsRegistry.executeAccountDeletion'),
    );
    expect(execution, contains('<String, dynamic>{}'));
  });
}
