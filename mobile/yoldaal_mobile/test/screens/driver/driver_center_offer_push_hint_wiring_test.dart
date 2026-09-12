import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'main registers messaging bridge after Firebase bootstrap before runApp',
    () {
      final source = File('lib/main.dart').readAsStringSync();

      final firebaseIndex = source.indexOf('await initializeFirebase();');
      final backgroundIndex = source.indexOf(
        'registerDriverOfferPushBackgroundHandler();',
      );
      final bridgeIndex = source.indexOf(
        'await initializeDriverOfferPushHintBridge();',
      );
      final runAppIndex = source.indexOf('runApp(const YoldaAlApp());');

      expect(firebaseIndex, greaterThanOrEqualTo(0));
      expect(backgroundIndex, greaterThan(firebaseIndex));
      expect(bridgeIndex, greaterThan(backgroundIndex));
      expect(runAppIndex, greaterThan(bridgeIndex));
    },
  );

  test(
    'background handler is entry point and contains no Firebase bootstrap',
    () {
      final source = File(
        'lib/services/driver_offer_push_hint_service.dart',
      ).readAsStringSync();

      expect(source, contains("@pragma('vm:entry-point')"));
      expect(source, contains('yoldaAlFirebaseMessagingBackgroundHandler'));
      expect(
        source,
        contains('if (!isDriverOfferPushHintData(message.data)) return;'),
      );
      expect(source, isNot(contains('Firebase.initializeApp')));
      expect(source, isNot(contains('initializeFirebase()')));

      expect(source, contains('FirebaseMessaging.onMessage.map'));
      expect(source, contains('FirebaseMessaging.onMessageOpenedApp.map'));
      expect(source, contains('getInitialMessage()'));
    },
  );

  test(
    'driver center consumes pending revision only at existing offer eligibility seam',
    () {
      final source = File(
        'lib/screens/driver/driver_center_screen.dart',
      ).readAsStringSync();

      expect(
        source,
        contains('final DriverOfferPushHintSource? offerPushHintSource;'),
      );
      expect(source, contains('source.revisions.listen'));
      expect(
        source,
        contains('widget.controller == null ? driverOfferPushHintBus : null'),
      );
      expect(
        source,
        contains(
          'final pushHintRevision = _offerPushHintSource?.revision ?? 0;',
        ),
      );
      expect(
        source,
        contains('pushHintRevision > _handledOfferPushHintRevision'),
      );

      final eligibilityIndex = source.indexOf(
        'controller.status != DriverCenterStatus.ready',
      );

      final handledIndex = source.indexOf(
        '_handledOfferPushHintRevision = pushHintRevision;',
      );

      final loadIndex = source.indexOf(
        'unawaited(matches.load());',
        handledIndex,
      );

      expect(eligibilityIndex, greaterThanOrEqualTo(0));
      expect(handledIndex, greaterThan(eligibilityIndex));
      expect(loadIndex, greaterThan(handledIndex));

      expect(source, contains('_offerPushHintSubscription?.cancel();'));
    },
  );
}
