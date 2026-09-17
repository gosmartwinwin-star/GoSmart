import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/ride/ride_chat_gateway.dart';
import 'package:yoldaal_mobile/application/ride/ride_gateway.dart';
import 'package:yoldaal_mobile/domain/ride/canonical_ride.dart';
import 'package:yoldaal_mobile/widgets/ride/ride_chat_panel.dart';

void main() {
  Future<void> pumpActive(
    WidgetTester tester, {
    required _Gateway gateway,
    required _PeriodicTimerFactory timers,
    required String Function() requestIdGenerator,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RideChatPanel(
            rideId: 'ride_1',
            status: RideStatus.driverEnRoute,
            viewerRole: RideChatSenderRole.passenger,
            gateway: gateway,
            requestIdGenerator: requestIdGenerator,
            periodicTimerFactory: timers.create,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
  }

  testWidgets('failed retry preserves the same logical request id', (
    tester,
  ) async {
    final gateway = _Gateway()..sendFailuresRemaining = 1;
    final timers = _PeriodicTimerFactory();

    var requestIdCalls = 0;

    await pumpActive(
      tester,
      gateway: gateway,
      timers: timers,
      requestIdGenerator: () {
        requestIdCalls += 1;
        return 'chat_request_retry_1234567890';
      },
    );

    await tester.enterText(
      find.byKey(const ValueKey('ride-chat-input-ride_1')),
      '  Merhaba  ',
    );

    await tester.tap(find.byKey(const ValueKey('ride-chat-send-ride_1')));

    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('ride-chat-send-error-ride_1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('ride-chat-send-ride_1')));

    await tester.pump();
    await tester.pump();

    expect(requestIdCalls, 1);
    expect(gateway.sendRequestIds, [
      'chat_request_retry_1234567890',
      'chat_request_retry_1234567890',
    ]);
    expect(gateway.sendTexts, ['Merhaba', 'Merhaba']);

    expect(
      find.byKey(const ValueKey('ride-chat-message-sent_2')),
      findsOneWidget,
    );
  });

  testWidgets('editing the failed logical message creates a new request id', (
    tester,
  ) async {
    final gateway = _Gateway()..sendFailuresRemaining = 1;
    final timers = _PeriodicTimerFactory();

    var requestIdCalls = 0;

    await pumpActive(
      tester,
      gateway: gateway,
      timers: timers,
      requestIdGenerator: () {
        requestIdCalls += 1;
        return 'chat_request_${requestIdCalls}_1234567890';
      },
    );

    final input = find.byKey(const ValueKey('ride-chat-input-ride_1'));

    await tester.enterText(input, 'Birinci');
    await tester.tap(find.byKey(const ValueKey('ride-chat-send-ride_1')));

    await tester.pump();
    await tester.pump();

    await tester.enterText(input, 'İkinci');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('ride-chat-send-ride_1')));

    await tester.pump();
    await tester.pump();

    expect(requestIdCalls, 2);
    expect(gateway.sendRequestIds, [
      'chat_request_1_1234567890',
      'chat_request_2_1234567890',
    ]);
  });

  testWidgets('terminal chat is read-only and renders callable messages', (
    tester,
  ) async {
    final gateway = _Gateway()
      ..listPage = RideChatPage(
        rideId: 'ride_terminal',
        messages: [
          RideChatMessage(
            messageId: 'terminal_message',
            senderRole: RideChatSenderRole.driver,
            assignmentRound: 2,
            text: 'Görüşmek üzere',
            createdAt: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
            expiresAt: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
          ),
        ],
        nextCursor: null,
      );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RideChatPanel(
            rideId: 'ride_terminal',
            status: RideStatus.completed,
            viewerRole: RideChatSenderRole.passenger,
            gateway: gateway,
            requestIdGenerator: () => 'unused_request_1234567890',
            periodicTimerFactory: _PeriodicTimerFactory().create,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Görüşmek üzere'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ride-chat-read-only-ride_terminal')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ride-chat-input-ride_terminal')),
      findsNothing,
    );
  });
}

class _Gateway implements RideChatGateway {
  int sendFailuresRemaining = 0;

  final sendRequestIds = <String>[];
  final sendTexts = <String>[];

  RideChatPage? listPage;

  int _sendCount = 0;

  @override
  Future<RideChatPage> listMessages({
    required String rideId,
    int pageSize = 50,
    RideChatCursor? cursor,
  }) async =>
      listPage ??
      RideChatPage(
        rideId: rideId,
        messages: const <RideChatMessage>[],
        nextCursor: null,
      );

  @override
  Future<RideChatMessage> sendMessage({
    required String rideId,
    required String requestId,
    required String text,
  }) async {
    _sendCount += 1;
    sendRequestIds.add(requestId);
    sendTexts.add(text);

    if (sendFailuresRemaining > 0) {
      sendFailuresRemaining -= 1;
      throw const RideGatewayException('unavailable');
    }

    return RideChatMessage(
      messageId: 'sent_$_sendCount',
      senderRole: RideChatSenderRole.passenger,
      assignmentRound: 1,
      text: text,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        1000 + _sendCount,
        isUtc: true,
      ),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        2000 + _sendCount,
        isUtc: true,
      ),
    );
  }
}

class _PeriodicTimerFactory {
  _FakeTimer? timer;

  Timer create(Duration duration, void Function(Timer timer) callback) {
    timer = _FakeTimer(callback);
    return timer!;
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this._callback);

  final void Function(Timer timer) _callback;

  bool _active = true;
  int _tick = 0;

  @override
  void cancel() {
    _active = false;
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  void fire() {
    if (!_active) {
      return;
    }

    _tick += 1;
    _callback(this);
  }
}
