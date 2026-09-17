import 'package:flutter/foundation.dart';

enum RideChatSenderRole { passenger, driver }

String rideChatSenderRoleWireValue(RideChatSenderRole role) => switch (role) {
  RideChatSenderRole.passenger => 'passenger',
  RideChatSenderRole.driver => 'driver',
};

RideChatSenderRole? rideChatSenderRoleFromWire(String value) => switch (value) {
  'passenger' => RideChatSenderRole.passenger,
  'driver' => RideChatSenderRole.driver,
  _ => null,
};

@immutable
class RideChatCursor {
  const RideChatCursor({
    required this.expiresAtMillis,
    required this.createdAtMillis,
    required this.messageId,
  });

  final int expiresAtMillis;
  final int createdAtMillis;
  final String messageId;

  Map<String, dynamic> toPayload() => {
    'expiresAtMillis': expiresAtMillis,
    'createdAtMillis': createdAtMillis,
    'messageId': messageId,
  };

  @override
  bool operator ==(Object other) =>
      other is RideChatCursor &&
      other.expiresAtMillis == expiresAtMillis &&
      other.createdAtMillis == createdAtMillis &&
      other.messageId == messageId;

  @override
  int get hashCode => Object.hash(expiresAtMillis, createdAtMillis, messageId);
}

@immutable
class RideChatMessage {
  const RideChatMessage({
    required this.messageId,
    required this.senderRole,
    required this.assignmentRound,
    required this.text,
    required this.createdAt,
    required this.expiresAt,
  });

  final String messageId;
  final RideChatSenderRole senderRole;
  final int assignmentRound;
  final String text;
  final DateTime createdAt;
  final DateTime expiresAt;

  RideChatCursor get cursor => RideChatCursor(
    expiresAtMillis: expiresAt.millisecondsSinceEpoch,
    createdAtMillis: createdAt.millisecondsSinceEpoch,
    messageId: messageId,
  );
}

@immutable
class RideChatPage {
  const RideChatPage({
    required this.rideId,
    required this.messages,
    required this.nextCursor,
  });

  final String rideId;
  final List<RideChatMessage> messages;
  final RideChatCursor? nextCursor;
}

abstract interface class RideChatGateway {
  Future<RideChatMessage> sendMessage({
    required String rideId,
    required String requestId,
    required String text,
  });

  Future<RideChatPage> listMessages({
    required String rideId,
    int pageSize = 50,
    RideChatCursor? cursor,
  });
}
