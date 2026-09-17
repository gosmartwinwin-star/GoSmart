import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/ride/ride_chat_gateway.dart';
import 'package:yoldaal_mobile/application/ride/ride_gateway.dart';
import 'package:yoldaal_mobile/controllers/ride_chat_controller.dart';
import 'package:yoldaal_mobile/domain/ride/canonical_ride.dart';

void main() {
  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'active chat performs immediate read and five-second cursor polling',
    () async {
      final gateway = _Gateway();
      final timers = _PeriodicTimerFactory();

      gateway.pages
        ..add(
          RideChatPage(
            rideId: 'ride_1',
            messages: [
              _message(
                id: 'message_1',
                createdAtMillis: 1000,
                expiresAtMillis: 2000,
              ),
            ],
            nextCursor: const RideChatCursor(
              expiresAtMillis: 2000,
              createdAtMillis: 1000,
              messageId: 'message_1',
            ),
          ),
        )
        ..add(
          RideChatPage(
            rideId: 'ride_1',
            messages: [
              _message(
                id: 'message_2',
                createdAtMillis: 3000,
                expiresAtMillis: 4000,
              ),
            ],
            nextCursor: null,
          ),
        )
        ..add(
          const RideChatPage(
            rideId: 'ride_1',
            messages: <RideChatMessage>[],
            nextCursor: null,
          ),
        );

      final controller = RideChatController(
        gateway: gateway,
        periodicTimerFactory: timers.create,
      );

      controller.updateContext(
        rideId: 'ride_1',
        status: RideStatus.driverEnRoute,
      );

      await settle();

      expect(gateway.listCalls, 1);
      expect(controller.messages.map((item) => item.messageId), ['message_1']);
      expect(timers.duration, rideChatPollInterval);
      expect(controller.polling, isTrue);
      expect(gateway.cursors.single, isNull);

      timers.fire();
      await settle();

      expect(gateway.listCalls, 2);
      expect(
        gateway.cursors[1],
        const RideChatCursor(
          expiresAtMillis: 2000,
          createdAtMillis: 1000,
          messageId: 'message_1',
        ),
      );
      expect(controller.messages.map((item) => item.messageId), [
        'message_1',
        'message_2',
      ]);

      timers.fire();
      await settle();

      expect(gateway.listCalls, 3);
      expect(
        gateway.cursors[2],
        const RideChatCursor(
          expiresAtMillis: 4000,
          createdAtMillis: 3000,
          messageId: 'message_2',
        ),
      );

      controller.dispose();
    },
  );

  test('poll tick never overlaps an in-flight list callable', () async {
    final gateway = _Gateway();
    final timers = _PeriodicTimerFactory();
    final pending = Completer<RideChatPage>();

    gateway.pendingPage = pending.future;

    final controller = RideChatController(
      gateway: gateway,
      periodicTimerFactory: timers.create,
    );

    controller.updateContext(rideId: 'ride_1', status: RideStatus.inProgress);

    await settle();

    expect(gateway.listCalls, 1);

    timers.fire();
    timers.fire();
    await settle();

    expect(
      gateway.listCalls,
      1,
      reason: 'Periodic polling must never overlap an in-flight callable.',
    );

    pending.complete(
      const RideChatPage(
        rideId: 'ride_1',
        messages: <RideChatMessage>[],
        nextCursor: null,
      ),
    );

    await settle();

    timers.fire();
    await settle();

    expect(gateway.listCalls, 2);

    controller.dispose();
  });

  test('terminal ride catches up once and stops polling at tail', () async {
    final gateway = _Gateway()
      ..pages.add(
        RideChatPage(
          rideId: 'ride_terminal',
          messages: [
            _message(
              id: 'terminal_message',
              createdAtMillis: 1000,
              expiresAtMillis: 2000,
            ),
          ],
          nextCursor: null,
        ),
      );

    final timers = _PeriodicTimerFactory();

    final controller = RideChatController(
      gateway: gateway,
      periodicTimerFactory: timers.create,
    );

    controller.updateContext(
      rideId: 'ride_terminal',
      status: RideStatus.completed,
    );

    await settle();

    expect(gateway.listCalls, 1);
    expect(controller.messages.single.messageId, 'terminal_message');
    expect(controller.canSend, isFalse);
    expect(controller.polling, isFalse);

    timers.fire();
    await settle();

    expect(gateway.listCalls, 1);

    controller.dispose();
  });

  test('participant or read-window closure clears cached transcript', () async {
    final gateway = _Gateway()
      ..pages.add(
        RideChatPage(
          rideId: 'ride_1',
          messages: [
            _message(
              id: 'private_message',
              createdAtMillis: 1000,
              expiresAtMillis: 2000,
            ),
          ],
          nextCursor: null,
        ),
      );

    final timers = _PeriodicTimerFactory();

    final controller = RideChatController(
      gateway: gateway,
      periodicTimerFactory: timers.create,
    );

    controller.updateContext(
      rideId: 'ride_1',
      status: RideStatus.driverEnRoute,
    );

    await settle();

    expect(controller.messages, hasLength(1));

    gateway.listError = const RideGatewayException(
      'permission-denied',
      reason: 'ride_chat_participant_required',
    );

    timers.fire();
    await settle();

    expect(controller.messages, isEmpty);
    expect(controller.accessClosed, isTrue);
    expect(controller.polling, isFalse);

    controller.dispose();
  });

  test('duplicate message ids are deduplicated in canonical order', () async {
    final gateway = _Gateway()
      ..pages.add(
        RideChatPage(
          rideId: 'ride_1',
          messages: [
            _message(
              id: 'message_2',
              createdAtMillis: 3000,
              expiresAtMillis: 4000,
            ),
            _message(
              id: 'message_1',
              createdAtMillis: 1000,
              expiresAtMillis: 2000,
            ),
            _message(
              id: 'message_1',
              createdAtMillis: 1000,
              expiresAtMillis: 2000,
            ),
          ],
          nextCursor: null,
        ),
      );

    final controller = RideChatController(
      gateway: gateway,
      periodicTimerFactory: _PeriodicTimerFactory().create,
    );

    controller.updateContext(
      rideId: 'ride_1',
      status: RideStatus.driverArrived,
    );

    await settle();

    expect(controller.messages.map((item) => item.messageId), [
      'message_1',
      'message_2',
    ]);

    controller.dispose();
  });
}

RideChatMessage _message({
  required String id,
  required int createdAtMillis,
  required int expiresAtMillis,
}) => RideChatMessage(
  messageId: id,
  senderRole: RideChatSenderRole.passenger,
  assignmentRound: 1,
  text: id,
  createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMillis, isUtc: true),
  expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAtMillis, isUtc: true),
);

class _Gateway implements RideChatGateway {
  final pages = <RideChatPage>[];
  final cursors = <RideChatCursor?>[];

  int listCalls = 0;
  Future<RideChatPage>? pendingPage;
  RideGatewayException? listError;

  @override
  Future<RideChatPage> listMessages({
    required String rideId,
    int pageSize = 50,
    RideChatCursor? cursor,
  }) async {
    listCalls += 1;
    cursors.add(cursor);

    if (listError case final error?) {
      throw error;
    }

    if (pendingPage case final future?) {
      pendingPage = null;
      return future;
    }

    if (pages.isEmpty) {
      return RideChatPage(
        rideId: rideId,
        messages: const <RideChatMessage>[],
        nextCursor: null,
      );
    }

    return pages.removeAt(0);
  }

  @override
  Future<RideChatMessage> sendMessage({
    required String rideId,
    required String requestId,
    required String text,
  }) => throw UnimplementedError();
}

class _PeriodicTimerFactory {
  _FakeTimer? timer;
  Duration? duration;

  Timer create(Duration duration, void Function(Timer timer) callback) {
    this.duration = duration;
    timer = _FakeTimer(callback);
    return timer!;
  }

  void fire() {
    timer?.fire();
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this._callback);

  final void Function(Timer timer) _callback;

  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) {
      return;
    }

    _tick += 1;
    _callback(this);
  }

  @override
  void cancel() {
    _active = false;
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}
