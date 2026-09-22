import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/core/firebase/firebase_functions_registry.dart';
import 'package:yoldaal_mobile/services/ride_voice_call_recovery_service.dart';

void main() {
  test(
    'recovery uses exact empty callable payload and parses projection',
    () async {
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
      final service = RideVoiceCallRecoveryService(invoker: invoker);

      final recovered = await service.recover();

      expect(
        invoker.callable,
        FirebaseFunctionsRegistry.getMyActiveRideVoiceCall,
      );
      expect(invoker.data, isEmpty);
      expect(recovered, isNotNull);
      expect(recovered!.rideId, 'ride-1');
      expect(recovered.callId, 'rvc_0123456789abcdef0123456789abcdef');
      expect(recovered.state, RideVoiceCallRecoveryState.ringing);
      expect(recovered.role, RideVoiceCallRecoveryRole.passenger);
      expect(recovered.side, RideVoiceCallRecoverySide.callee);
    },
  );

  test('null authoritative activeCall recovers as null', () async {
    final service = RideVoiceCallRecoveryService(
      invoker: _FakeInvoker(
        result: const <String, dynamic>{'activeCall': null},
      ),
    );

    expect(await service.recover(), isNull);
  });

  test('expanded root or active-call response fails closed', () async {
    final invalidResponses = <Object?>[
      <String, dynamic>{'activeCall': null, 'counterpartyUid': 'forbidden'},
      <String, dynamic>{
        'activeCall': <String, dynamic>{
          'rideId': 'ride-1',
          'callId': 'rvc_0123456789abcdef0123456789abcdef',
          'state': 'active',
          'role': 'driver',
          'side': 'caller',
          'driverId': 'forbidden',
        },
      },
    ];

    for (final response in invalidResponses) {
      final service = RideVoiceCallRecoveryService(
        invoker: _FakeInvoker(result: response),
      );

      await expectLater(
        service.recover(),
        throwsA(
          isA<RideVoiceCallRecoveryException>().having(
            (error) => error.code,
            'code',
            'invalid-response',
          ),
        ),
      );
    }
  });

  test('malformed projection values fail closed', () async {
    final invalidCalls = <Map<String, dynamic>>[
      <String, dynamic>{
        'rideId': '',
        'callId': 'rvc_0123456789abcdef0123456789abcdef',
        'state': 'active',
        'role': 'driver',
        'side': 'caller',
      },
      <String, dynamic>{
        'rideId': 'ride-1',
        'callId': 'ride-1',
        'state': 'active',
        'role': 'driver',
        'side': 'caller',
      },
      <String, dynamic>{
        'rideId': 'ride-1',
        'callId': 'rvc_0123456789abcdef0123456789abcdef',
        'state': 'ended',
        'role': 'driver',
        'side': 'caller',
      },
      <String, dynamic>{
        'rideId': 'ride-1',
        'callId': 'rvc_0123456789abcdef0123456789abcdef',
        'state': 'active',
        'role': 'admin',
        'side': 'caller',
      },
      <String, dynamic>{
        'rideId': 'ride-1',
        'callId': 'rvc_0123456789abcdef0123456789abcdef',
        'state': 'active',
        'role': 'driver',
        'side': 'observer',
      },
    ];

    for (final call in invalidCalls) {
      final service = RideVoiceCallRecoveryService(
        invoker: _FakeInvoker(result: <String, dynamic>{'activeCall': call}),
      );

      await expectLater(
        service.recover(),
        throwsA(
          isA<RideVoiceCallRecoveryException>().having(
            (error) => error.code,
            'code',
            'invalid-response',
          ),
        ),
      );
    }
  });

  test('callable failures expose only bounded error codes', () async {
    final denied = RideVoiceCallRecoveryService(
      invoker: _FakeInvoker(
        error: const RideVoiceCallRecoveryException('permission-denied'),
      ),
    );
    final unknown = RideVoiceCallRecoveryService(
      invoker: _FakeInvoker(
        error: const RideVoiceCallRecoveryException('raw-upstream-detail'),
      ),
    );
    final transport = RideVoiceCallRecoveryService(
      invoker: _FakeInvoker(error: StateError('sensitive transport detail')),
    );

    await expectLater(
      denied.recover(),
      throwsA(
        isA<RideVoiceCallRecoveryException>().having(
          (error) => error.code,
          'code',
          'permission-denied',
        ),
      ),
    );
    await expectLater(
      unknown.recover(),
      throwsA(
        isA<RideVoiceCallRecoveryException>().having(
          (error) => error.code,
          'code',
          'unknown',
        ),
      ),
    );
    await expectLater(
      transport.recover(),
      throwsA(
        isA<RideVoiceCallRecoveryException>().having(
          (error) => error.code,
          'code',
          'unavailable',
        ),
      ),
    );
  });
}

class _FakeInvoker implements RideVoiceCallRecoveryCallableInvoker {
  _FakeInvoker({this.result, this.error});

  final Object? result;
  final Object? error;

  String? callable;
  Map<String, dynamic>? data;

  @override
  Future<Object?> call(String callable, Map<String, dynamic> data) async {
    this.callable = callable;
    this.data = Map<String, dynamic>.from(data);

    final failure = error;

    if (failure != null) {
      throw failure;
    }

    return result;
  }
}
