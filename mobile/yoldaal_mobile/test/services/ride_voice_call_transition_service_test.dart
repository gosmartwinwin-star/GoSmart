import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/services/ride_voice_call_transition_service.dart';

void main() {
  test(
    'uses exact transition callable and authoritative payload shape',
    () async {
      const rideId = 'ride-1';
      const callId = 'rvc_0123456789abcdef0123456789abcdef';

      for (final target in <String>[
        'accepted',
        'connecting',
        'active',
        'declined',
        'cancelled',
        'ended',
      ]) {
        final invoker = _FakeInvoker();
        final service = RideVoiceCallTransitionService(invoker: invoker);

        await service.transition(
          rideId: rideId,
          callId: callId,
          targetState: target,
        );

        expect(invoker.calls, 1);
        expect(invoker.callable, 'transitionRideVoiceCall');
        expect(invoker.data, <String, dynamic>{
          'rideId': rideId,
          'callId': callId,
          'toState': target,
        });
      }
    },
  );

  test('unsupported target and malformed identifiers fail locally', () async {
    final invalidTarget = _FakeInvoker();
    final targetService = RideVoiceCallTransitionService(
      invoker: invalidTarget,
    );

    await expectLater(
      targetService.transition(
        rideId: 'ride-1',
        callId: 'rvc_0123456789abcdef0123456789abcdef',
        targetState: 'unsupported',
      ),
      throwsA(
        isA<RideVoiceCallTransitionException>().having(
          (error) => error.code,
          'code',
          'invalid-argument',
        ),
      ),
    );
    expect(invalidTarget.calls, 0);

    final invalidCall = _FakeInvoker();
    final callService = RideVoiceCallTransitionService(invoker: invalidCall);

    await expectLater(
      callService.transition(
        rideId: 'ride-1',
        callId: 'not-a-call-id',
        targetState: 'ended',
      ),
      throwsA(isA<RideVoiceCallTransitionException>()),
    );
    expect(invalidCall.calls, 0);
  });

  test(
    'bounded callable errors are preserved and raw failures are sanitized',
    () async {
      final bounded = _FakeInvoker(
        error: const RideVoiceCallTransitionException('permission-denied'),
      );
      final boundedService = RideVoiceCallTransitionService(invoker: bounded);

      await expectLater(
        boundedService.transition(
          rideId: 'ride-1',
          callId: 'rvc_0123456789abcdef0123456789abcdef',
          targetState: 'cancelled',
        ),
        throwsA(
          isA<RideVoiceCallTransitionException>().having(
            (error) => error.code,
            'code',
            'permission-denied',
          ),
        ),
      );

      final unknownCode = _FakeInvoker(
        error: const RideVoiceCallTransitionException('sensitive-raw-code'),
      );
      final unknownService = RideVoiceCallTransitionService(
        invoker: unknownCode,
      );

      await expectLater(
        unknownService.transition(
          rideId: 'ride-1',
          callId: 'rvc_0123456789abcdef0123456789abcdef',
          targetState: 'cancelled',
        ),
        throwsA(
          isA<RideVoiceCallTransitionException>().having(
            (error) => error.code,
            'code',
            'internal',
          ),
        ),
      );

      final raw = _FakeInvoker(error: StateError('sensitive transport detail'));
      final rawService = RideVoiceCallTransitionService(invoker: raw);

      await expectLater(
        rawService.transition(
          rideId: 'ride-1',
          callId: 'rvc_0123456789abcdef0123456789abcdef',
          targetState: 'cancelled',
        ),
        throwsA(
          isA<RideVoiceCallTransitionException>().having(
            (error) => error.code,
            'code',
            'unavailable',
          ),
        ),
      );
    },
  );
}

class _FakeInvoker implements RideVoiceCallTransitionCallableInvoker {
  _FakeInvoker({this.error});

  final Object? error;

  int calls = 0;
  String? callable;
  Map<String, dynamic>? data;

  @override
  Future<Object?> call(String callable, Map<String, dynamic> data) async {
    calls += 1;
    this.callable = callable;
    this.data = Map<String, dynamic>.from(data);

    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }

    return const <String, dynamic>{'ok': true};
  }
}
