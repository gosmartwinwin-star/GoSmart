import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/services/driver_offer_push_hint_service.dart';
import 'package:yoldaal_mobile/services/ride_chat_push_hint_service.dart';

void main() {
  test(
    'shared push bridge forwards chat availability hints without offer authority',
    () async {
      final offerBus = DriverOfferPushHintBus();
      final chatBus = RideChatPushHintBus();
      final foreground = StreamController<DriverOfferPushHintData>.broadcast();
      final opened = StreamController<DriverOfferPushHintData>.broadcast();

      final bridge = DriverOfferPushHintBridge(
        voiceSink: null,
        sink: offerBus,
        chatSink: chatBus,
        foregroundMessages: foreground.stream,
        openedMessages: opened.stream,
        initialMessageLoader: () async => const <String, dynamic>{
          'type': rideChatMessageAvailablePushHintType,
        },
      );

      await bridge.start();
      await Future<void>.delayed(Duration.zero);

      expect(chatBus.revision, 1);
      expect(offerBus.revision, 0);

      foreground.add(const <String, dynamic>{
        'type': rideChatMessageAvailablePushHintType,
      });

      opened.add(const <String, dynamic>{
        'type': rideChatMessageAvailablePushHintType,
      });

      await Future<void>.delayed(Duration.zero);

      expect(chatBus.revision, 3);
      expect(offerBus.revision, 0);

      await bridge.dispose();
      await foreground.close();
      await opened.close();
      await offerBus.dispose();
      await chatBus.dispose();
    },
  );
  test('hint classifier accepts only ride offer available type', () {
    expect(
      isDriverOfferPushHintData(const <String, dynamic>{
        'type': driverRideOfferAvailablePushHintType,
      }),
      isTrue,
    );

    expect(
      isDriverOfferPushHintData(const <String, dynamic>{'type': 'other'}),
      isFalse,
    );

    expect(isDriverOfferPushHintData(const <String, dynamic>{}), isFalse);
  });

  test('hint bus publishes monotonic revisions', () async {
    final bus = DriverOfferPushHintBus();
    final revisions = <int>[];

    final subscription = bus.revisions.listen(revisions.add);

    bus.publish();
    bus.publish();

    expect(bus.revision, 2);
    expect(revisions, <int>[1, 2]);

    await subscription.cancel();
    await bus.dispose();
  });

  test(
    'bridge consumes initial foreground and opened hints but ignores unrelated data',
    () async {
      final bus = DriverOfferPushHintBus();

      final foreground = StreamController<DriverOfferPushHintData>.broadcast();
      final opened = StreamController<DriverOfferPushHintData>.broadcast();

      final bridge = DriverOfferPushHintBridge(
        voiceSink: null,
        sink: bus,
        foregroundMessages: foreground.stream,
        openedMessages: opened.stream,
        initialMessageLoader: () async => const <String, dynamic>{
          'type': driverRideOfferAvailablePushHintType,
        },
      );

      await bridge.start();

      expect(bus.revision, 1);

      foreground.add(const <String, dynamic>{'type': 'not-a-ride-offer'});

      opened.add(const <String, dynamic>{
        'type': driverRideOfferAvailablePushHintType,
      });

      foreground.add(const <String, dynamic>{
        'type': driverRideOfferAvailablePushHintType,
      });

      await pumpEventQueue();

      expect(bus.revision, 3);

      await bridge.dispose();
      await foreground.close();
      await opened.close();
      await bus.dispose();
    },
  );

  test('bridge start is idempotent', () async {
    final bus = DriverOfferPushHintBus();

    final foreground = StreamController<DriverOfferPushHintData>.broadcast();
    final opened = StreamController<DriverOfferPushHintData>.broadcast();

    var initialCalls = 0;

    final bridge = DriverOfferPushHintBridge(
      voiceSink: null,
      sink: bus,
      foregroundMessages: foreground.stream,
      openedMessages: opened.stream,
      initialMessageLoader: () async {
        initialCalls += 1;

        return const <String, dynamic>{
          'type': driverRideOfferAvailablePushHintType,
        };
      },
    );

    await bridge.start();
    await bridge.start();

    foreground.add(const <String, dynamic>{
      'type': driverRideOfferAvailablePushHintType,
    });

    await pumpEventQueue();

    expect(initialCalls, 1);
    expect(bus.revision, 2);

    await bridge.dispose();
    await foreground.close();
    await opened.close();
    await bus.dispose();
  });

  test(
    'initial message failure is fail-soft and live hints continue',
    () async {
      final bus = DriverOfferPushHintBus();

      final foreground = StreamController<DriverOfferPushHintData>.broadcast();
      final opened = StreamController<DriverOfferPushHintData>.broadcast();

      final bridge = DriverOfferPushHintBridge(
        voiceSink: null,
        sink: bus,
        foregroundMessages: foreground.stream,
        openedMessages: opened.stream,
        initialMessageLoader: () async {
          throw StateError('initial message unavailable');
        },
      );

      await bridge.start();

      expect(bus.revision, 0);

      foreground.add(const <String, dynamic>{
        'type': driverRideOfferAvailablePushHintType,
      });

      await pumpEventQueue();

      expect(bus.revision, 1);

      await bridge.dispose();
      await foreground.close();
      await opened.close();
      await bus.dispose();
    },
  );
}
