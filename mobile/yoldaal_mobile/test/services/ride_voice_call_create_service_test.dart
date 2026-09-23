import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/services/ride_voice_call_create_service.dart';

void main() {
  test('uses exact create callable and exact rideId-only payload', () async {
    final invoker = _FakeInvoker();
    final service = RideVoiceCallCreateService(invoker: invoker);

    await service.create(rideId: ' ride-1 ');

    expect(invoker.calls, 1);
    expect(invoker.callable, 'createRideVoiceCall');
    expect(invoker.data, <String, dynamic>{'rideId': 'ride-1'});
    expect(invoker.data!.keys, <String>{'rideId'});
  });

  test(
    'blank rideId is rejected locally without callable invocation',
    () async {
      final invoker = _FakeInvoker();
      final service = RideVoiceCallCreateService(invoker: invoker);

      await expectLater(
        service.create(rideId: '   '),
        throwsA(
          isA<RideVoiceCallCreateException>().having(
            (error) => error.code,
            'code',
            'invalid-argument',
          ),
        ),
      );

      expect(invoker.calls, 0);
    },
  );

  test(
    'bounded callable errors survive and unknown failures are sanitized',
    () async {
      final bounded = _FakeInvoker(
        error: const RideVoiceCallCreateException('permission-denied'),
      );
      final boundedService = RideVoiceCallCreateService(invoker: bounded);

      await expectLater(
        boundedService.create(rideId: 'ride-1'),
        throwsA(
          isA<RideVoiceCallCreateException>().having(
            (error) => error.code,
            'code',
            'permission-denied',
          ),
        ),
      );

      final unknown = _FakeInvoker(
        error: const RideVoiceCallCreateException('sensitive-raw-code'),
      );
      final unknownService = RideVoiceCallCreateService(invoker: unknown);

      await expectLater(
        unknownService.create(rideId: 'ride-1'),
        throwsA(
          isA<RideVoiceCallCreateException>().having(
            (error) => error.code,
            'code',
            'internal',
          ),
        ),
      );

      final raw = _FakeInvoker(error: StateError('sensitive transport detail'));
      final rawService = RideVoiceCallCreateService(invoker: raw);

      await expectLater(
        rawService.create(rideId: 'ride-1'),
        throwsA(
          isA<RideVoiceCallCreateException>().having(
            (error) => error.code,
            'code',
            'unavailable',
          ),
        ),
      );
    },
  );
}

class _FakeInvoker implements RideVoiceCallCreateCallableInvoker {
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

    return const <String, dynamic>{
      'callId': 'forbidden-response-identity',
      'state': 'ringing',
    };
  }
}
