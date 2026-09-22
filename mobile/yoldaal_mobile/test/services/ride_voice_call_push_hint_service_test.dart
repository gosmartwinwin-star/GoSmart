import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/services/driver_offer_push_hint_service.dart';
import 'package:yoldaal_mobile/services/ride_voice_call_push_hint_service.dart';

void main() {
  test('classifier accepts only exact generic Voice availability data', () {
    expect(
      isRideVoiceCallPushHintData(const <String, dynamic>{
        'type': rideVoiceCallAvailablePushHintType,
      }),
      isTrue,
    );

    expect(
      isRideVoiceCallPushHintData(const <String, dynamic>{
        'type': rideVoiceCallAvailablePushHintType,
        'rideId': 'forbidden',
      }),
      isFalse,
    );

    expect(
      isRideVoiceCallPushHintData(const <String, dynamic>{'type': 'other'}),
      isFalse,
    );

    expect(isRideVoiceCallPushHintData(const <String, dynamic>{}), isFalse);
  });

  test('bus emits monotonically increasing content-free revisions', () async {
    final bus = RideVoiceCallPushHintBus();
    final revisions = <int>[];
    final subscription = bus.revisions.listen(revisions.add);

    expect(bus.revision, 0);

    bus.publish();
    bus.publish();

    expect(bus.revision, 2);
    expect(revisions, <int>[1, 2]);

    await subscription.cancel();
    await bus.dispose();
  });

  test(
    'shared bridge routes initial foreground and opened Voice hints',
    () async {
      final offerBus = DriverOfferPushHintBus();
      final voiceBus = RideVoiceCallPushHintBus();
      final foreground = StreamController<DriverOfferPushHintData>.broadcast();
      final opened = StreamController<DriverOfferPushHintData>.broadcast();

      final bridge = DriverOfferPushHintBridge(
        sink: offerBus,
        voiceSink: voiceBus,
        foregroundMessages: foreground.stream,
        openedMessages: opened.stream,
        initialMessageLoader: () async => const <String, dynamic>{
          'type': rideVoiceCallAvailablePushHintType,
        },
      );

      await bridge.start();

      expect(offerBus.revision, 0);
      expect(voiceBus.revision, 1);

      foreground.add(const <String, dynamic>{
        'type': rideVoiceCallAvailablePushHintType,
      });
      await Future<void>.delayed(Duration.zero);

      expect(offerBus.revision, 0);
      expect(voiceBus.revision, 2);

      foreground.add(const <String, dynamic>{
        'type': rideVoiceCallAvailablePushHintType,
        'rideId': 'forbidden',
      });
      await Future<void>.delayed(Duration.zero);

      expect(voiceBus.revision, 2);

      opened.add(const <String, dynamic>{
        'type': rideVoiceCallAvailablePushHintType,
      });
      await Future<void>.delayed(Duration.zero);

      expect(offerBus.revision, 0);
      expect(voiceBus.revision, 3);

      await bridge.dispose();
      await foreground.close();
      await opened.close();
      await offerBus.dispose();
      await voiceBus.dispose();
    },
  );

  test(
    'background handler remains authority-free and does not consume Voice',
    () {
      final source = File(
        'lib/services/driver_offer_push_hint_service.dart',
      ).readAsStringSync();
      final handlerStart = source.indexOf("@pragma('vm:entry-point')");

      expect(handlerStart, greaterThanOrEqualTo(0));

      final handlerSource = source.substring(handlerStart);

      expect(
        handlerSource,
        contains('if (!isDriverOfferPushHintData(message.data)) return;'),
      );
      expect(handlerSource, isNot(contains('isRideVoiceCallPushHintData')));
      expect(handlerSource, isNot(contains('FirebaseFunctions')));
      expect(handlerSource, isNot(contains('httpsCallable')));
      expect(handlerSource, isNot(contains('.publish()')));
    },
  );
}
