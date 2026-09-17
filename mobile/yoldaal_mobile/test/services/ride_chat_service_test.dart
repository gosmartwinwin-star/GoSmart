import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/ride/ride_chat_gateway.dart';
import 'package:yoldaal_mobile/application/ride/ride_gateway.dart';
import 'package:yoldaal_mobile/services/ride_chat_service.dart';
import 'package:yoldaal_mobile/services/ride_lifecycle_service.dart';

void main() {
  test('send uses exact callable and frozen payload', () async {
    final invoker = _Invoker()
      ..response = {
        'rideId': 'ride_1',
        'messageId': 'message_1',
        'kind': 'text',
        'senderRole': 'passenger',
        'assignmentRound': 2,
        'text': 'Merhaba',
        'createdAtMillis': 1000,
        'expiresAtMillis': 2000,
      };

    final service = RideChatService(invoker: invoker);

    final message = await service.sendMessage(
      rideId: 'ride_1',
      requestId: 'chat_request_1234567890',
      text: '  Merhaba  ',
    );

    expect(invoker.names, [rideChatSendCallableName]);
    expect(invoker.payloads, [
      {
        'rideId': 'ride_1',
        'requestId': 'chat_request_1234567890',
        'text': 'Merhaba',
      },
    ]);

    expect(message.messageId, 'message_1');
    expect(message.senderRole, RideChatSenderRole.passenger);
    expect(message.assignmentRound, 2);
    expect(message.text, 'Merhaba');
    expect(
      message.createdAt,
      DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
    );
    expect(
      message.expiresAt,
      DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
    );
  });

  test('list uses bounded page and exact frozen cursor payload', () async {
    final invoker = _Invoker()
      ..response = {
        'rideId': 'ride_1',
        'messages': [
          {
            'messageId': 'message_2',
            'kind': 'text',
            'senderRole': 'driver',
            'assignmentRound': 3,
            'text': 'Geliyorum',
            'createdAtMillis': 3000,
            'expiresAtMillis': 4000,
          },
        ],
        'nextCursor': {
          'expiresAtMillis': 4000,
          'createdAtMillis': 3000,
          'messageId': 'message_2',
        },
      };

    final service = RideChatService(invoker: invoker);

    final page = await service.listMessages(
      rideId: 'ride_1',
      pageSize: 50,
      cursor: const RideChatCursor(
        expiresAtMillis: 2000,
        createdAtMillis: 1000,
        messageId: 'message_1',
      ),
    );

    expect(invoker.names, [rideChatListCallableName]);
    expect(invoker.payloads, [
      {
        'rideId': 'ride_1',
        'pageSize': 50,
        'cursor': {
          'expiresAtMillis': 2000,
          'createdAtMillis': 1000,
          'messageId': 'message_1',
        },
      },
    ]);

    expect(page.rideId, 'ride_1');
    expect(page.messages.single.messageId, 'message_2');
    expect(page.messages.single.senderRole, RideChatSenderRole.driver);
    expect(
      page.nextCursor,
      const RideChatCursor(
        expiresAtMillis: 4000,
        createdAtMillis: 3000,
        messageId: 'message_2',
      ),
    );
  });

  test('list omits cursor when polling from beginning', () async {
    final invoker = _Invoker()
      ..response = {
        'rideId': 'ride_1',
        'messages': <Object?>[],
        'nextCursor': null,
      };

    final service = RideChatService(invoker: invoker);

    await service.listMessages(rideId: 'ride_1');

    expect(invoker.payloads.single, {'rideId': 'ride_1', 'pageSize': 50});
  });

  test('text validation is Unicode-code-point based and trims input', () async {
    final invoker = _Invoker()
      ..response = {
        'rideId': 'ride_1',
        'messageId': 'message_emoji',
        'kind': 'text',
        'senderRole': 'passenger',
        'assignmentRound': 1,
        'text': List<String>.filled(1000, '🙂').join(),
        'createdAtMillis': 1000,
        'expiresAtMillis': 2000,
      };

    final service = RideChatService(invoker: invoker);
    final accepted = List<String>.filled(1000, '🙂').join();

    await service.sendMessage(
      rideId: 'ride_1',
      requestId: 'chat_request_1234567890',
      text: accepted,
    );

    expect(invoker.payloads.single['text'], accepted);

    final rejected = List<String>.filled(1001, '🙂').join();

    expect(
      () => service.sendMessage(
        rideId: 'ride_1',
        requestId: 'chat_request_1234567890',
        text: rejected,
      ),
      throwsArgumentError,
    );

    expect(
      () => service.sendMessage(
        rideId: 'ride_1',
        requestId: 'chat_request_1234567890',
        text: '   ',
      ),
      throwsArgumentError,
    );
  });

  test('malformed or expanded responses fail closed', () async {
    final invalidResponses = <Map<String, dynamic>>[
      {
        'rideId': 'ride_1',
        'messages': <Object?>[],
        'nextCursor': null,
        'participantUid': 'must-not-leak',
      },
      {
        'rideId': 'ride_1',
        'messages': [
          {
            'messageId': 'message_1',
            'kind': 'text',
            'senderRole': 'driver',
            'assignmentRound': 1,
            'text': 'x',
            'createdAtMillis': 1000,
            'expiresAtMillis': 2000,
            'driverId': 'must-not-leak',
          },
        ],
        'nextCursor': null,
      },
    ];

    for (final response in invalidResponses) {
      final invoker = _Invoker()..response = response;
      final service = RideChatService(invoker: invoker);

      await expectLater(
        service.listMessages(rideId: 'ride_1'),
        throwsA(
          isA<RideGatewayException>().having(
            (error) => error.code,
            'code',
            'invalid-response',
          ),
        ),
      );
    }
  });

  test('gateway errors propagate without widening error details', () async {
    final invoker = _Invoker()
      ..error = const RideGatewayException(
        'permission-denied',
        reason: 'ride_chat_participant_required',
      );

    final service = RideChatService(invoker: invoker);

    await expectLater(
      service.listMessages(rideId: 'ride_1'),
      throwsA(
        isA<RideGatewayException>()
            .having((error) => error.code, 'code', 'permission-denied')
            .having(
              (error) => error.reason,
              'reason',
              'ride_chat_participant_required',
            ),
      ),
    );
  });
}

class _Invoker implements RideCallableInvoker {
  final names = <String>[];
  final payloads = <Map<String, dynamic>>[];

  Map<String, dynamic> response = const {};
  RideGatewayException? error;

  @override
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> payload,
  ) async {
    names.add(name);
    payloads.add(Map<String, dynamic>.from(payload));

    if (error case final value?) {
      throw value;
    }

    return Map<String, dynamic>.from(response);
  }
}
