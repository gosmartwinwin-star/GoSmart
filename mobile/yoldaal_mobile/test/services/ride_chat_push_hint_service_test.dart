import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/services/ride_chat_push_hint_service.dart';

void main() {
  test('classifier accepts only exact generic chat availability data', () {
    expect(
      isRideChatPushHintData(const <String, dynamic>{
        'type': rideChatMessageAvailablePushHintType,
      }),
      isTrue,
    );

    expect(
      isRideChatPushHintData(const <String, dynamic>{'type': 'other'}),
      isFalse,
    );

    expect(
      isRideChatPushHintData(const <String, dynamic>{
        'type': rideChatMessageAvailablePushHintType,
        'rideId': 'forbidden',
      }),
      isFalse,
    );

    expect(isRideChatPushHintData(const <String, dynamic>{}), isFalse);
  });

  test('bus emits monotonically increasing content-free revisions', () async {
    final bus = RideChatPushHintBus();
    final revisions = <int>[];
    final subscription = bus.revisions.listen(revisions.add);

    expect(bus.revision, 0);

    bus.publish();
    bus.publish();

    await Future<void>.delayed(Duration.zero);

    expect(bus.revision, 2);
    expect(revisions, <int>[1, 2]);

    await subscription.cancel();
    await bus.dispose();
  });
}
