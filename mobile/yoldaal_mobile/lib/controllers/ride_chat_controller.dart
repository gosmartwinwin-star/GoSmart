import 'dart:async';

import 'package:flutter/foundation.dart';

import '../application/ride/ride_chat_gateway.dart';
import '../application/ride/ride_gateway.dart';
import '../domain/ride/canonical_ride.dart';

const rideChatPollInterval = Duration(seconds: 5);
const rideChatPageSize = 50;

typedef RideChatPeriodicTimerFactory =
    Timer Function(Duration duration, void Function(Timer timer) callback);

class RideChatController extends ChangeNotifier {
  RideChatController({
    required RideChatGateway gateway,
    RideChatPeriodicTimerFactory? periodicTimerFactory,
  }) : _gateway = gateway,
       _periodicTimerFactory = periodicTimerFactory ?? Timer.periodic;

  static const Set<RideStatus> _writableStatuses = <RideStatus>{
    RideStatus.driverEnRoute,
    RideStatus.driverArrived,
    RideStatus.inProgress,
  };

  static const Set<RideStatus> _terminalStatuses = <RideStatus>{
    RideStatus.completed,
    RideStatus.cancelled,
    RideStatus.expired,
  };

  final RideChatGateway _gateway;
  final RideChatPeriodicTimerFactory _periodicTimerFactory;

  Timer? _pollTimer;
  String? _rideId;
  RideStatus? _status;
  RideChatCursor? _cursor;

  final Map<String, RideChatMessage> _messagesById =
      <String, RideChatMessage>{};

  bool _loading = false;
  bool _sending = false;
  bool _inFlight = false;
  bool _pendingImmediateRead = false;
  bool _disposed = false;
  bool _accessClosed = false;

  int _generation = 0;

  String? _readErrorCode;
  String? _sendErrorCode;

  static bool isWritableStatus(RideStatus status) =>
      _writableStatuses.contains(status);

  static bool isReadableStatus(RideStatus status) =>
      _writableStatuses.contains(status) || _terminalStatuses.contains(status);

  static bool isTerminalStatus(RideStatus status) =>
      _terminalStatuses.contains(status);

  String? get rideId => _rideId;
  RideStatus? get status => _status;

  bool get isReadable =>
      !_disposed &&
      !_accessClosed &&
      _rideId != null &&
      _status != null &&
      isReadableStatus(_status!);

  bool get canSend =>
      isReadable && _status != null && isWritableStatus(_status!);

  bool get loading => _loading;
  bool get sending => _sending;
  bool get accessClosed => _accessClosed;
  String? get readErrorCode => _readErrorCode;
  String? get sendErrorCode => _sendErrorCode;

  bool get polling => _pollTimer?.isActive ?? false;

  List<RideChatMessage> get messages {
    final values = _messagesById.values.toList(growable: false);

    values.sort((left, right) {
      final expiresCompare = left.expiresAt.millisecondsSinceEpoch.compareTo(
        right.expiresAt.millisecondsSinceEpoch,
      );

      if (expiresCompare != 0) {
        return expiresCompare;
      }

      final createdCompare = left.createdAt.millisecondsSinceEpoch.compareTo(
        right.createdAt.millisecondsSinceEpoch,
      );

      if (createdCompare != 0) {
        return createdCompare;
      }

      return left.messageId.compareTo(right.messageId);
    });

    return List<RideChatMessage>.unmodifiable(values);
  }

  void updateContext({required String rideId, required RideStatus status}) {
    if (_disposed) {
      return;
    }

    final rideChanged = _rideId != rideId;
    final statusChanged = _status != status;

    if (!rideChanged && !statusChanged) {
      return;
    }

    _generation += 1;
    _pendingImmediateRead = false;
    _readErrorCode = null;
    _sendErrorCode = null;
    _accessClosed = false;

    if (rideChanged) {
      _messagesById.clear();
      _cursor = null;
    }

    _rideId = rideId;
    _status = status;

    if (!isReadableStatus(status)) {
      _cancelPolling();
      _messagesById.clear();
      _cursor = null;
      _loading = false;
      _notify();
      return;
    }

    _ensurePolling();
    _loading = true;
    _notify();
    _queueImmediateRead();
  }

  Future<void> refresh() async {
    if (!isReadable) {
      return;
    }

    _readErrorCode = null;
    _loading = true;
    _notify();

    if (_inFlight) {
      _pendingImmediateRead = true;
      return;
    }

    await _readCurrent();
  }

  Future<RideChatMessage> send({
    required String requestId,
    required String text,
  }) async {
    final currentRideId = _rideId;

    if (!canSend || currentRideId == null || _sending) {
      throw const RideGatewayException(
        'failed-precondition',
        reason: 'ride_chat_send_not_allowed',
      );
    }

    final generation = _generation;

    _sending = true;
    _sendErrorCode = null;
    _notify();

    try {
      final message = await _gateway.sendMessage(
        rideId: currentRideId,
        requestId: requestId,
        text: text,
      );

      if (_disposed || generation != _generation || currentRideId != _rideId) {
        return message;
      }

      _messagesById[message.messageId] = message;
      _sendErrorCode = null;
      _notify();

      return message;
    } on RideGatewayException catch (error) {
      if (!_disposed && generation == _generation && currentRideId == _rideId) {
        _sendErrorCode = error.code;
        _notify();
      }

      rethrow;
    } finally {
      if (!_disposed && generation == _generation && currentRideId == _rideId) {
        _sending = false;
        _notify();
      }
    }
  }

  void _queueImmediateRead() {
    if (_disposed || !isReadable) {
      return;
    }

    if (_inFlight) {
      _pendingImmediateRead = true;
      return;
    }

    unawaited(_readCurrent());
  }

  void _ensurePolling() {
    if (_disposed || !isReadable) {
      return;
    }

    if (_pollTimer?.isActive == true) {
      return;
    }

    _pollTimer = _periodicTimerFactory(rideChatPollInterval, (_) {
      if (!_inFlight && isReadable) {
        unawaited(_readCurrent());
      }
    });
  }

  Future<void> _readCurrent() async {
    if (_disposed || !isReadable || _inFlight) {
      return;
    }

    final currentRideId = _rideId;
    final currentStatus = _status;

    if (currentRideId == null || currentStatus == null) {
      return;
    }

    final generation = _generation;
    final cursor = _cursor;

    _inFlight = true;
    _loading = true;
    _notify();

    try {
      final page = await _gateway.listMessages(
        rideId: currentRideId,
        pageSize: rideChatPageSize,
        cursor: cursor,
      );

      if (_disposed ||
          generation != _generation ||
          currentRideId != _rideId ||
          currentStatus != _status) {
        return;
      }

      if (page.rideId != currentRideId) {
        throw const RideGatewayException('invalid-response');
      }

      for (final message in page.messages) {
        _messagesById[message.messageId] = message;
      }

      _readErrorCode = null;
      _loading = false;

      if (page.nextCursor case final nextCursor?) {
        _cursor = nextCursor;
      } else {
        if (page.messages.isNotEmpty) {
          _cursor = page.messages.last.cursor;
        }

        if (isTerminalStatus(currentStatus)) {
          _cancelPolling();
        }
      }

      _notify();
    } on RideGatewayException catch (error) {
      if (_disposed || generation != _generation || currentRideId != _rideId) {
        return;
      }

      _loading = false;
      _readErrorCode = error.code;

      if (_mustClearPrivateCache(error.code)) {
        _messagesById.clear();
        _cursor = null;
        _accessClosed = true;
        _cancelPolling();
      }

      _notify();
    } catch (_) {
      if (_disposed || generation != _generation || currentRideId != _rideId) {
        return;
      }

      _loading = false;
      _readErrorCode = 'unavailable';
      _notify();
    } finally {
      _inFlight = false;

      if (!_disposed && generation == _generation && _pendingImmediateRead) {
        _pendingImmediateRead = false;
        _queueImmediateRead();
      }
    }
  }

  static bool _mustClearPrivateCache(String code) =>
      code == 'unauthenticated' ||
      code == 'permission-denied' ||
      code == 'failed-precondition';

  void _cancelPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }

    _generation += 1;
    _cancelPolling();
    _messagesById.clear();
    _cursor = null;
    _pendingImmediateRead = false;
    _disposed = true;

    super.dispose();
  }
}
