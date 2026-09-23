import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/controllers/ride_voice_call_recovery_controller.dart';
import 'package:yoldaal_mobile/services/ride_voice_call_push_hint_service.dart';
import 'package:yoldaal_mobile/services/ride_voice_call_recovery_service.dart';
import 'package:yoldaal_mobile/services/ride_voice_call_transition_service.dart';

void main() {
  test(
    'start performs one authoritative recovery for authenticated user',
    () async {
      final hints = _FakeHintSource();
      final invoker = _FakeInvoker(
        result: <String, dynamic>{
          'activeCall': <String, dynamic>{
            'rideId': 'ride-1',
            'callId': 'rvc_0123456789abcdef0123456789abcdef',
            'state': 'ringing',
            'role': 'passenger',
            'side': 'callee',
          },
        },
      );
      final controller = RideVoiceCallRecoveryController(
        recoveryService: RideVoiceCallRecoveryService(invoker: invoker),
        hintSource: hints,
        isAuthenticated: () => true,
      );

      addTearDown(controller.dispose);
      addTearDown(hints.dispose);

      controller.start();
      await _drain();

      expect(invoker.calls, 1);
      expect(controller.activeCall?.rideId, 'ride-1');
      expect(
        controller.activeCall?.callId,
        'rvc_0123456789abcdef0123456789abcdef',
      );
      expect(controller.activeCall?.state, RideVoiceCallRecoveryState.ringing);
      expect(controller.activeCall?.role, RideVoiceCallRecoveryRole.passenger);
      expect(controller.activeCall?.side, RideVoiceCallRecoverySide.callee);
      expect(controller.errorCode, isNull);
    },
  );

  test(
    'new hint revision and resume each request authoritative recovery',
    () async {
      final hints = _FakeHintSource();
      final invoker = _FakeInvoker(
        result: const <String, dynamic>{'activeCall': null},
      );
      final controller = RideVoiceCallRecoveryController(
        recoveryService: RideVoiceCallRecoveryService(invoker: invoker),
        hintSource: hints,
        isAuthenticated: () => true,
      );

      addTearDown(controller.dispose);
      addTearDown(hints.dispose);

      controller.start();
      await _drain();
      expect(invoker.calls, 1);

      hints.emit(1);
      await _drain();
      expect(invoker.calls, 2);
      expect(controller.handledHintRevision, 1);

      hints.emit(1);
      await _drain();
      expect(invoker.calls, 2);

      controller.appResumed();
      await _drain();
      expect(invoker.calls, 3);
    },
  );

  test(
    'signed-out state never invokes callable and auth change clears state',
    () async {
      var authenticated = false;
      final hints = _FakeHintSource();
      final invoker = _FakeInvoker(
        result: <String, dynamic>{
          'activeCall': <String, dynamic>{
            'rideId': 'ride-1',
            'callId': 'rvc_0123456789abcdef0123456789abcdef',
            'state': 'active',
            'role': 'driver',
            'side': 'caller',
          },
        },
      );
      final controller = RideVoiceCallRecoveryController(
        recoveryService: RideVoiceCallRecoveryService(invoker: invoker),
        hintSource: hints,
        isAuthenticated: () => authenticated,
      );

      addTearDown(controller.dispose);
      addTearDown(hints.dispose);

      controller.start();
      await _drain();
      expect(invoker.calls, 0);
      expect(controller.activeCall, isNull);

      authenticated = true;
      controller.authChanged();
      await _drain();
      expect(invoker.calls, 1);
      expect(controller.activeCall, isNotNull);

      authenticated = false;
      controller.authChanged();
      await _drain();
      expect(invoker.calls, 1);
      expect(controller.activeCall, isNull);
      expect(controller.errorCode, isNull);
    },
  );

  test(
    'concurrent hint and resume triggers are serialized and coalesced',
    () async {
      final hints = _FakeHintSource();
      final pending = Completer<Object?>();
      final invoker = _FakeInvoker(pending: pending);
      final controller = RideVoiceCallRecoveryController(
        recoveryService: RideVoiceCallRecoveryService(invoker: invoker),
        hintSource: hints,
        isAuthenticated: () => true,
      );

      addTearDown(controller.dispose);
      addTearDown(hints.dispose);

      controller.start();
      await Future<void>.delayed(Duration.zero);

      expect(invoker.calls, 1);
      expect(invoker.maxConcurrent, 1);

      hints.emit(1);
      controller.appResumed();
      hints.emit(2);

      await Future<void>.delayed(Duration.zero);
      expect(invoker.calls, 1);

      pending.complete(const <String, dynamic>{'activeCall': null});
      await _drain(4);

      expect(invoker.calls, 2);
      expect(invoker.maxConcurrent, 1);
      expect(controller.handledHintRevision, 2);
    },
  );

  test(
    'bounded recovery error is exposed without raw transport detail',
    () async {
      final hints = _FakeHintSource();
      final invoker = _FakeInvoker(
        error: StateError('sensitive raw transport'),
      );
      final controller = RideVoiceCallRecoveryController(
        recoveryService: RideVoiceCallRecoveryService(invoker: invoker),
        hintSource: hints,
        isAuthenticated: () => true,
      );

      addTearDown(controller.dispose);
      addTearDown(hints.dispose);

      controller.start();
      await _drain();

      expect(invoker.calls, 1);
      expect(controller.errorCode, 'unavailable');
      expect(controller.errorCode, isNot(contains('sensitive')));
    },
  );
  test(
    'callee ringing accepts and refreshes from authoritative recovery',
    () async {
      final hints = _FakeHintSource();
      final recovery = _FakeInvoker(
        result: <String, dynamic>{
          'activeCall': <String, dynamic>{
            'rideId': 'ride-1',
            'callId': 'rvc_0123456789abcdef0123456789abcdef',
            'state': 'ringing',
            'role': 'passenger',
            'side': 'callee',
          },
        },
      );
      final transitionInvoker = _FakeTransitionInvoker();
      final controller = RideVoiceCallRecoveryController(
        recoveryService: RideVoiceCallRecoveryService(invoker: recovery),
        transitionService: RideVoiceCallTransitionService(
          invoker: transitionInvoker,
        ),
        hintSource: hints,
        isAuthenticated: () => true,
      );

      addTearDown(controller.dispose);
      addTearDown(hints.dispose);

      controller.start();
      await _drain();

      expect(controller.canAccept, isTrue);
      expect(controller.canDecline, isTrue);
      expect(controller.canCancel, isFalse);
      expect(controller.canEnd, isFalse);

      await controller.acceptCall();

      expect(transitionInvoker.calls, 1);
      expect(transitionInvoker.data?['toState'], 'accepted');
      expect(recovery.calls, 2);
      expect(controller.actionErrorCode, isNull);
      expect(controller.actionInFlight, isFalse);
    },
  );

  test('caller ringing can cancel but cannot accept', () async {
    final hints = _FakeHintSource();
    final recovery = _FakeInvoker(
      result: <String, dynamic>{
        'activeCall': <String, dynamic>{
          'rideId': 'ride-1',
          'callId': 'rvc_0123456789abcdef0123456789abcdef',
          'state': 'ringing',
          'role': 'driver',
          'side': 'caller',
        },
      },
    );
    final transitionInvoker = _FakeTransitionInvoker();
    final controller = RideVoiceCallRecoveryController(
      recoveryService: RideVoiceCallRecoveryService(invoker: recovery),
      transitionService: RideVoiceCallTransitionService(
        invoker: transitionInvoker,
      ),
      hintSource: hints,
      isAuthenticated: () => true,
    );

    addTearDown(controller.dispose);
    addTearDown(hints.dispose);

    controller.start();
    await _drain();

    expect(controller.canCancel, isTrue);
    expect(controller.canAccept, isFalse);

    await controller.acceptCall();
    expect(transitionInvoker.calls, 0);
    expect(controller.actionErrorCode, 'failed-precondition');

    await controller.cancelCall();
    expect(transitionInvoker.calls, 1);
    expect(transitionInvoker.data?['toState'], 'cancelled');
  });

  test('accepted connecting and active calls expose end action', () async {
    for (final state in <String>['accepted', 'connecting', 'active']) {
      final hints = _FakeHintSource();
      final recovery = _FakeInvoker(
        result: <String, dynamic>{
          'activeCall': <String, dynamic>{
            'rideId': 'ride-1',
            'callId': 'rvc_0123456789abcdef0123456789abcdef',
            'state': state,
            'role': 'passenger',
            'side': 'callee',
          },
        },
      );
      final transitionInvoker = _FakeTransitionInvoker();
      final controller = RideVoiceCallRecoveryController(
        recoveryService: RideVoiceCallRecoveryService(invoker: recovery),
        transitionService: RideVoiceCallTransitionService(
          invoker: transitionInvoker,
        ),
        hintSource: hints,
        isAuthenticated: () => true,
      );

      controller.start();
      await _drain();

      expect(controller.canEnd, isTrue);
      await controller.endCall();
      expect(transitionInvoker.calls, 1);
      expect(transitionInvoker.data?['toState'], 'ended');

      controller.dispose();
      await hints.dispose();
    }
  });

  test(
    'transition failure keeps snapshot and exposes bounded action error',
    () async {
      final hints = _FakeHintSource();
      final recovery = _FakeInvoker(
        result: <String, dynamic>{
          'activeCall': <String, dynamic>{
            'rideId': 'ride-1',
            'callId': 'rvc_0123456789abcdef0123456789abcdef',
            'state': 'ringing',
            'role': 'passenger',
            'side': 'callee',
          },
        },
      );
      final transitionInvoker = _FakeTransitionInvoker(
        error: const RideVoiceCallTransitionException('permission-denied'),
      );
      final controller = RideVoiceCallRecoveryController(
        recoveryService: RideVoiceCallRecoveryService(invoker: recovery),
        transitionService: RideVoiceCallTransitionService(
          invoker: transitionInvoker,
        ),
        hintSource: hints,
        isAuthenticated: () => true,
      );

      addTearDown(controller.dispose);
      addTearDown(hints.dispose);

      controller.start();
      await _drain();
      final before = controller.activeCall;

      await controller.declineCall();

      expect(transitionInvoker.calls, 1);
      expect(recovery.calls, 1);
      expect(controller.activeCall, same(before));
      expect(controller.actionErrorCode, 'permission-denied');
    },
  );

  test('parallel transition attempts are coalesced to one callable', () async {
    final hints = _FakeHintSource();
    final recovery = _FakeInvoker(
      result: <String, dynamic>{
        'activeCall': <String, dynamic>{
          'rideId': 'ride-1',
          'callId': 'rvc_0123456789abcdef0123456789abcdef',
          'state': 'ringing',
          'role': 'passenger',
          'side': 'callee',
        },
      },
    );
    final pending = Completer<Object?>();
    final transitionInvoker = _FakeTransitionInvoker(pending: pending);
    final controller = RideVoiceCallRecoveryController(
      recoveryService: RideVoiceCallRecoveryService(invoker: recovery),
      transitionService: RideVoiceCallTransitionService(
        invoker: transitionInvoker,
      ),
      hintSource: hints,
      isAuthenticated: () => true,
    );

    addTearDown(controller.dispose);
    addTearDown(hints.dispose);

    controller.start();
    await _drain();

    final first = controller.acceptCall();
    await Future<void>.delayed(Duration.zero);
    final second = controller.declineCall();
    await Future<void>.delayed(Duration.zero);

    expect(controller.actionInFlight, isTrue);
    expect(transitionInvoker.calls, 1);

    pending.complete(const <String, dynamic>{'ok': true});
    await Future.wait<void>(<Future<void>>[first, second]);

    expect(transitionInvoker.calls, 1);
    expect(recovery.calls, 2);
    expect(controller.actionInFlight, isFalse);
  });
}

Future<void> _drain([int turns = 2]) async {
  for (var i = 0; i < turns; i += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _FakeHintSource implements RideVoiceCallPushHintSource {
  final StreamController<int> _controller = StreamController<int>.broadcast(
    sync: true,
  );

  int _revision = 0;

  @override
  int get revision => _revision;

  @override
  Stream<int> get revisions => _controller.stream;

  void emit(int revision) {
    _revision = revision;
    _controller.add(revision);
  }

  Future<void> dispose() => _controller.close();
}

class _FakeInvoker implements RideVoiceCallRecoveryCallableInvoker {
  _FakeInvoker({this.result, this.error, this.pending});

  final Object? result;
  final Object? error;
  final Completer<Object?>? pending;

  int calls = 0;
  int concurrent = 0;
  int maxConcurrent = 0;

  @override
  Future<Object?> call(String callable, Map<String, dynamic> data) async {
    expect(callable, 'getMyActiveRideVoiceCall');
    expect(data, isEmpty);

    calls += 1;
    concurrent += 1;
    if (concurrent > maxConcurrent) {
      maxConcurrent = concurrent;
    }

    try {
      if (pending != null) {
        return await pending!.future;
      }
      if (error != null) {
        throw error!;
      }
      return result;
    } finally {
      concurrent -= 1;
    }
  }
}

class _FakeTransitionInvoker implements RideVoiceCallTransitionCallableInvoker {
  _FakeTransitionInvoker({this.error, this.pending});

  final Object? error;
  final Completer<Object?>? pending;

  int calls = 0;
  Map<String, dynamic>? data;

  @override
  Future<Object?> call(String callable, Map<String, dynamic> data) async {
    calls += 1;
    this.data = Map<String, dynamic>.from(data);

    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }

    final currentPending = pending;
    if (currentPending != null) {
      return currentPending.future;
    }

    return const <String, dynamic>{'ok': true};
  }
}
