import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final driver = File(
    'lib/screens/driver/driver_center_screen.dart',
  ).readAsStringSync();
  final home = File('lib/screens/home/home_screen.dart').readAsStringSync();
  final controller = File(
    'lib/controllers/ride_voice_call_recovery_controller.dart',
  ).readAsStringSync();

  test('driver reuses existing lifecycle observer for Voice recovery', () {
    expect(
      driver,
      contains(
        "import '../../controllers/ride_voice_call_recovery_controller.dart';",
      ),
    );
    expect(
      driver,
      contains(
        'final RideVoiceCallRecoveryController? voiceCallRecoveryController;',
      ),
    );
    expect(driver, contains('_initializeVoiceCallRecoveryController();'));
    expect(driver, contains('_voiceCallRecoveryController?.authChanged();'));
    expect(driver, contains('_voiceCallRecoveryController?.appResumed();'));
    expect(driver, contains('_disposeVoiceCallRecoveryController();'));
    expect(driver, contains('with WidgetsBindingObserver'));
  });

  test('passenger HomeScreen gains minimal lifecycle recovery ownership', () {
    expect(
      home,
      contains(
        "import '../../controllers/ride_voice_call_recovery_controller.dart';",
      ),
    );
    expect(
      home,
      contains(
        'class _HomeScreenState extends State<HomeScreen> '
        'with WidgetsBindingObserver {',
      ),
    );
    expect(home, contains('WidgetsBinding.instance.addObserver(this);'));
    expect(home, contains('WidgetsBinding.instance.removeObserver(this);'));
    expect(home, contains('_initializeVoiceCallRecoveryController();'));
    expect(home, contains('_voiceCallRecoveryController?.authChanged();'));
    expect(home, contains('_voiceCallRecoveryController?.appResumed();'));
  });

  test(
    'screens consume only shared controller, never push payload authority',
    () {
      for (final source in <String>[driver, home]) {
        expect(source, isNot(contains('RideVoiceCallRecoveryService(')));
        expect(source, isNot(contains('isRideVoiceCallPushHintData')));
        expect(source, isNot(contains('getMyActiveRideVoiceCall')));
        expect(source, isNot(contains('ride_voice_call_available')));
        expect(source.toLowerCase(), isNot(contains('agora')));
      }

      expect(controller, contains('RideVoiceCallPushHintSource? hintSource'));
      expect(
        controller,
        contains('recoveryService ?? RideVoiceCallRecoveryService()'),
      );
      expect(controller, contains('hintSource ?? rideVoiceCallPushHintBus'));
      expect(controller, contains('void _handleHintRevision(int revision)'));
      expect(controller, contains('void appResumed()'));
      expect(controller, isNot(contains('ride_voice_call_available')));
      expect(controller.toLowerCase(), isNot(contains('agora')));
    },
  );

  test('both screens mount shared Voice panel without direct callables', () {
    expect(
      driver,
      contains(
        "import '../../widgets/ride/ride_voice_call_status_panel.dart';",
      ),
    );
    expect(
      home,
      contains(
        "import '../../widgets/ride/ride_voice_call_status_panel.dart';",
      ),
    );
    expect(driver, contains('RideVoiceCallStatusPanel('));
    expect(
      driver,
      contains('viewerRole: RideVoiceCallStatusViewerRole.driver'),
    );
    expect(home, contains('RideVoiceCallStatusPanel('));
    expect(
      home,
      contains('viewerRole: RideVoiceCallStatusViewerRole.passenger'),
    );

    for (final source in <String>[driver, home]) {
      expect(source, isNot(contains('createRideVoiceCall')));
      expect(source, isNot(contains('transitionRideVoiceCall')));
      expect(source, isNot(contains('ride_voice_call_available')));
      expect(source.toLowerCase(), isNot(contains('agora')));
    }
  });

  test('screen Voice ride probes expose only eligible current ride IDs', () {
    for (final source in <String>[driver, home]) {
      expect(source, contains('String? _currentEligibleVoiceRideId()'));
      expect(
        source,
        contains('currentEligibleRideId: _currentEligibleVoiceRideId'),
      );
      expect(source, contains('RideStatus.driverEnRoute'));
      expect(source, contains('RideStatus.driverArrived'));
      expect(source, contains('RideStatus.inProgress'));
      expect(source, contains('if (!eligible) return null;'));
      expect(source, contains('return rideId.isEmpty ? null : rideId;'));
      expect(
        source,
        isNot(contains('FirebaseFunctionsRegistry.createRideVoiceCall')),
      );
      expect(source, isNot(contains('httpsCallable(')));
    }
  });
  test(
    'default screen wiring is production-only when core controllers inject',
    () {
      expect(
        driver,
        contains('widget.controller == null && widget.rideController == null'),
      );
      expect(home, contains('widget.rideController == null'));
    },
  );
}
