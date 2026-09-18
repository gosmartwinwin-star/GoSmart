import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File('lib/screens/home/home_screen.dart').readAsStringSync();
  });

  test('Home owns a separate fail-soft passenger push target lifecycle', () {
    expect(
      source,
      contains(
        "import '../../controllers/passenger_push_target_lifecycle_controller.dart';",
      ),
    );
    expect(
      source,
      contains(
        "import '../../services/passenger_push_target_registration_service.dart';",
      ),
    );
    expect(
      source,
      contains('PassengerPushTargetLifecycle? _passengerPushTargetLifecycle;'),
    );
    expect(source, contains('bool _ownsPassengerPushTargetLifecycle = false;'));
    expect(source, contains('_initializePassengerPushTargetLifecycle();'));
    expect(source, contains('if (!_ownsRideController) {'));
    expect(source, contains('resolvePassengerPushTargetPlatform()'));
    expect(source, contains('PassengerPushTargetRegistrationService()'));
    expect(source, contains('PassengerPushTargetLifecycleController('));
    expect(
      source,
      contains(
        'lifecycle.setEligible(FirebaseAuth.instance.currentUser != null);',
      ),
    );
    expect(
      source,
      contains('_passengerPushTargetLifecycle?.setEligible(user != null);'),
    );
    expect(
      source,
      contains('_passengerPushTargetLifecycle?.setEligible(false);'),
    );
    expect(source, contains('_passengerPushTargetLifecycle?.dispose();'));
  });

  test('Home adds no direct FCM or Firestore chat authority', () {
    expect(source, isNot(contains('FirebaseMessaging')));
    expect(source, isNot(contains("collection('passengerPushTargets')")));
    expect(source, isNot(contains("collection('messages')")));
    expect(source, isNot(contains('.snapshots()')));
  });
}
