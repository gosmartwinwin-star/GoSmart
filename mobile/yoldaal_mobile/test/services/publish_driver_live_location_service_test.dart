import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/driver/driver_live_presence_gateway.dart';
import 'package:yoldaal_mobile/domain/return_route/geo_coordinate.dart';
import 'package:yoldaal_mobile/services/publish_driver_live_location_service.dart';

void main() {
  final location = GeoCoordinate(latitude: 41, longitude: 29);

  test('unauthenticated stops before invoker', () async {
    final auth = _FakeAuth(authenticated: false);
    final invoker = _FakeInvoker(
      response: const {'updatedAtMillis': 123},
    );

    await expectLater(
      PublishDriverLiveLocationService(
        authSession: auth,
        invoker: invoker,
      ).publish(location: location),
      throwsA(
        isA<DriverLivePresencePublishException>().having(
          (error) => error.code,
          'code',
          'unauthenticated',
        ),
      ),
    );

    expect(auth.calls, 1);
    expect(invoker.calls, 0);
  });

  test('sends exact latitude longitude payload', () async {
    final invoker = _FakeInvoker(
      response: const {'updatedAtMillis': 123},
    );

    await PublishDriverLiveLocationService(
      authSession: _FakeAuth(authenticated: true),
      invoker: invoker,
    ).publish(location: location);

    expect(invoker.calls, 1);
    expect(invoker.payload, {
      'latitude': location.latitude,
      'longitude': location.longitude,
    });
    expect(invoker.payload?.length, 2);
  });

  test('does not send server-owned fields', () async {
    final invoker = _FakeInvoker(
      response: const {'updatedAtMillis': 123},
    );

    await PublishDriverLiveLocationService(
      authSession: _FakeAuth(authenticated: true),
      invoker: invoker,
    ).publish(location: location);

    for (final key in [
      'driverId',
      'authUserId',
      'updatedAt',
      'timestamp',
      'online',
    ]) {
      expect(invoker.payload?.containsKey(key), isFalse, reason: key);
    }
  });

  test('valid response returns only updatedAtMillis result', () async {
    final result = await PublishDriverLiveLocationService(
      authSession: _FakeAuth(authenticated: true),
      invoker: _FakeInvoker(
        response: const {'updatedAtMillis': 987654321},
      ),
    ).publish(location: location);

    expect(result.updatedAtMillis, 987654321);
  });

  test('missing updatedAtMillis fails closed', () async {
    final invoker = _FakeInvoker(response: const <String, Object?>{});

    await expectLater(
      PublishDriverLiveLocationService(
        authSession: _FakeAuth(authenticated: true),
        invoker: invoker,
      ).publish(location: location),
      throwsFormatException,
    );
  });

  test('wrong updatedAtMillis type fails closed', () async {
    final invoker = _FakeInvoker(
      response: const {'updatedAtMillis': '123'},
    );

    await expectLater(
      PublishDriverLiveLocationService(
        authSession: _FakeAuth(authenticated: true),
        invoker: invoker,
      ).publish(location: location),
      throwsFormatException,
    );
  });

  test('extra response key fails closed', () async {
    final invoker = _FakeInvoker(
      response: const {
        'updatedAtMillis': 123,
        'driverId': 'forbidden',
      },
    );

    await expectLater(
      PublishDriverLiveLocationService(
        authSession: _FakeAuth(authenticated: true),
        invoker: invoker,
      ).publish(location: location),
      throwsFormatException,
    );
  });

  test('domain exception preserves code and safe reason', () async {
    final invoker = _FakeInvoker(
      error: const DriverLivePresencePublishException(
        code: 'failed-precondition',
        reason: 'subscription_required',
      ),
    );

    await expectLater(
      PublishDriverLiveLocationService(
        authSession: _FakeAuth(authenticated: true),
        invoker: invoker,
      ).publish(location: location),
      throwsA(
        isA<DriverLivePresencePublishException>()
            .having(
              (error) => error.code,
              'code',
              'failed-precondition',
            )
            .having(
              (error) => error.reason,
              'reason',
              'subscription_required',
            ),
      ),
    );

    expect(invoker.calls, 1);
  });
}

class _FakeAuth implements DriverLivePresenceAuthSession {
  final bool authenticated;
  int calls = 0;

  _FakeAuth({required this.authenticated});

  @override
  Future<void> requireAuthenticatedUser() async {
    calls++;

    if (!authenticated) {
      throw const DriverLivePresencePublishException(
        code: 'unauthenticated',
      );
    }
  }
}

class _FakeInvoker implements DriverLivePresenceCallableInvoker {
  final Object? response;
  final Object? error;

  int calls = 0;
  Map<String, Object?>? payload;

  _FakeInvoker({
    this.response,
    this.error,
  });

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    calls++;
    this.payload = Map<String, Object?>.from(payload);

    final failure = error;
    if (failure != null) {
      throw failure;
    }

    return response;
  }
}
