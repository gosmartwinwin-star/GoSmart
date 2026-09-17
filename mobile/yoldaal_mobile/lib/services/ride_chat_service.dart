import '../application/ride/ride_chat_gateway.dart';
import '../application/ride/ride_gateway.dart';
import 'ride_lifecycle_service.dart';

const rideChatSendCallableName = 'sendRideChatMessage';
const rideChatListCallableName = 'listRideChatMessages';
const rideChatTextMaxCharacters = 1000;
const rideChatPageSizeMax = 50;

class RideChatService implements RideChatGateway {
  RideChatService({RideCallableInvoker? invoker})
    : _invoker = invoker ?? FirebaseRideCallableInvoker();

  final RideCallableInvoker _invoker;

  @override
  Future<RideChatMessage> sendMessage({
    required String rideId,
    required String requestId,
    required String text,
  }) async {
    _validateRideId(rideId);
    _validateRequestId(requestId);

    final normalizedText = text.trim();
    _validateText(normalizedText);

    final data = await _call(rideChatSendCallableName, {
      'rideId': rideId,
      'requestId': requestId,
      'text': normalizedText,
    });

    if (data.length != 8 || data['rideId'] != rideId) {
      throw const RideGatewayException('invalid-response');
    }

    return _parseMessage(data, expectedKeyCount: 8, hasRideId: true);
  }

  @override
  Future<RideChatPage> listMessages({
    required String rideId,
    int pageSize = 50,
    RideChatCursor? cursor,
  }) async {
    _validateRideId(rideId);

    if (pageSize < 1 || pageSize > rideChatPageSizeMax) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'Ride chat page size must be between 1 and 50.',
      );
    }

    final payload = <String, dynamic>{
      'rideId': rideId,
      'pageSize': pageSize,
      if (cursor != null) 'cursor': cursor.toPayload(),
    };

    final data = await _call(rideChatListCallableName, payload);

    if (data.length != 3 || data['rideId'] != rideId) {
      throw const RideGatewayException('invalid-response');
    }

    final rawMessages = data['messages'];
    final rawCursor = data['nextCursor'];

    if (rawMessages is! List) {
      throw const RideGatewayException('invalid-response');
    }

    final messages = <RideChatMessage>[];

    for (final rawMessage in rawMessages) {
      if (rawMessage is! Map) {
        throw const RideGatewayException('invalid-response');
      }

      messages.add(
        _parseMessage(
          Map<String, dynamic>.from(rawMessage),
          expectedKeyCount: 7,
          hasRideId: false,
        ),
      );
    }

    RideChatCursor? nextCursor;

    if (rawCursor != null) {
      if (rawCursor is! Map) {
        throw const RideGatewayException('invalid-response');
      }

      nextCursor = _parseCursor(Map<String, dynamic>.from(rawCursor));
    }

    return RideChatPage(
      rideId: rideId,
      messages: List<RideChatMessage>.unmodifiable(messages),
      nextCursor: nextCursor,
    );
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> payload,
  ) async {
    try {
      return await _invoker.call(name, payload);
    } on RideGatewayException {
      rethrow;
    } catch (_) {
      throw const RideGatewayException('invalid-response');
    }
  }

  static RideChatMessage _parseMessage(
    Map<String, dynamic> data, {
    required int expectedKeyCount,
    required bool hasRideId,
  }) {
    if (data.length != expectedKeyCount) {
      throw const RideGatewayException('invalid-response');
    }

    if (hasRideId && data['rideId'] is! String) {
      throw const RideGatewayException('invalid-response');
    }

    final messageId = data['messageId'];
    final kind = data['kind'];
    final senderRoleRaw = data['senderRole'];
    final assignmentRound = data['assignmentRound'];
    final text = data['text'];
    final createdAtMillis = data['createdAtMillis'];
    final expiresAtMillis = data['expiresAtMillis'];

    if (messageId is! String ||
        messageId.isEmpty ||
        kind != 'text' ||
        senderRoleRaw is! String ||
        assignmentRound is! int ||
        assignmentRound < 1 ||
        text is! String ||
        text.trim().isEmpty ||
        text.runes.length > rideChatTextMaxCharacters ||
        createdAtMillis is! int ||
        createdAtMillis < 0 ||
        expiresAtMillis is! int ||
        expiresAtMillis <= createdAtMillis) {
      throw const RideGatewayException('invalid-response');
    }

    final senderRole = rideChatSenderRoleFromWire(senderRoleRaw);

    if (senderRole == null) {
      throw const RideGatewayException('invalid-response');
    }

    return RideChatMessage(
      messageId: messageId,
      senderRole: senderRole,
      assignmentRound: assignmentRound,
      text: text,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        createdAtMillis,
        isUtc: true,
      ),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        expiresAtMillis,
        isUtc: true,
      ),
    );
  }

  static RideChatCursor _parseCursor(Map<String, dynamic> data) {
    if (data.length != 3) {
      throw const RideGatewayException('invalid-response');
    }

    final expiresAtMillis = data['expiresAtMillis'];
    final createdAtMillis = data['createdAtMillis'];
    final messageId = data['messageId'];

    if (expiresAtMillis is! int ||
        expiresAtMillis < 0 ||
        createdAtMillis is! int ||
        createdAtMillis < 0 ||
        messageId is! String ||
        messageId.isEmpty) {
      throw const RideGatewayException('invalid-response');
    }

    return RideChatCursor(
      expiresAtMillis: expiresAtMillis,
      createdAtMillis: createdAtMillis,
      messageId: messageId,
    );
  }

  static void _validateRideId(String value) {
    if (value.isEmpty ||
        value.length > 128 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw ArgumentError.value(value, 'rideId', 'Invalid ride id.');
    }
  }

  static void _validateRequestId(String value) {
    if (value.length < 16 ||
        value.length > 128 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw ArgumentError.value(value, 'requestId', 'Invalid request id.');
    }
  }

  static void _validateText(String value) {
    if (value.isEmpty || value.runes.length > rideChatTextMaxCharacters) {
      throw ArgumentError.value(
        value,
        'text',
        'Ride chat text must contain 1-1000 Unicode code points.',
      );
    }
  }
}
