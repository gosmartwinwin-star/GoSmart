import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/domain/return_route/driver_return_route_status.dart';
import 'package:gosmart_mobile/domain/return_route/geo_coordinate.dart';
import 'package:gosmart_mobile/services/publish_return_route_service.dart';

void main() {
  final origin = GeoCoordinate(latitude: 41.0, longitude: 29.0);
  final destination = GeoCoordinate(latitude: 41.1, longitude: 29.1);
  const encoded = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
  const activatedAt = 1_800_000_000_000;
  const expiresAt = activatedAt + 3_600_000;

  Map<String, Object?> response({
    Object? routeId = 'route-1',
    Object? driverId = 'driver-1',
    Object? status = 'active',
    Object? activated = activatedAt,
    Object? expires = expiresAt,
    Object? distance = 12000,
    Object? duration = 1800,
    Object? polyline = encoded,
  }) => {
    'routeId': routeId,
    'driverId': driverId,
    'status': status,
    'activatedAtMillis': activated,
    'expiresAtMillis': expires,
    'distanceMeters': distance,
    'durationSeconds': duration,
    'encodedPolyline': polyline,
  };

  Future<({dynamic result, _FakeInvoker invoker, _FakeAuth auth})> publish({
    Object? rawResponse,
    GeoCoordinate? selectedOrigin,
    GeoCoordinate? selectedDestination,
    int validity = 3600,
    bool authenticated = true,
    Object? invocationError,
  }) async {
    final invoker = _FakeInvoker(rawResponse ?? response(), invocationError);
    final auth = _FakeAuth(authenticated);
    final result =
        await PublishReturnRouteService(
          authSession: auth,
          invoker: invoker,
        ).publish(
          origin: selectedOrigin ?? origin,
          destination: selectedDestination ?? destination,
          validForSeconds: validity,
        );
    return (result: result, invoker: invoker, auth: auth);
  }

  group('payload', () {
    test('yalnız güvenli üç üst seviye alanı gönderir', () async {
      final call = await publish();
      expect(call.invoker.payload?.keys, {
        'origin',
        'destination',
        'validForSeconds',
      });
    });

    test('koordinatları ve geçerlilik süresini doğru gönderir', () async {
      final call = await publish(validity: 900);
      expect(call.invoker.payload?['origin'], {
        'latitude': 41.0,
        'longitude': 29.0,
      });
      expect(call.invoker.payload?['destination'], {
        'latitude': 41.1,
        'longitude': 29.1,
      });
      expect(call.invoker.payload?['validForSeconds'], 900);
    });

    test('sunucu alanlarını payload içine eklemez', () async {
      final payload = (await publish()).invoker.payload!;
      for (final key in [
        'driverId',
        'authUserId',
        'status',
        'createdAt',
        'activatedAt',
        'expiresAt',
        'distanceMeters',
        'durationSeconds',
        'encodedPolyline',
        'subscriptionActive',
        'profileApproved',
      ]) {
        expect(payload.containsKey(key), isFalse, reason: key);
      }
    });
  });

  group('yerel doğrulama', () {
    test('aynı koordinat callable öncesinde reddedilir', () async {
      final invoker = _FakeInvoker(response(), null);
      await expectLater(
        PublishReturnRouteService(
          authSession: _FakeAuth(true),
          invoker: invoker,
        ).publish(origin: origin, destination: origin, validForSeconds: 900),
        throwsArgumentError,
      );
      expect(invoker.calls, 0);
    });

    for (final invalid in [899, 14401]) {
      test('$invalid saniye callable öncesinde reddedilir', () async {
        final invoker = _FakeInvoker(response(), null);
        await expectLater(
          PublishReturnRouteService(
            authSession: _FakeAuth(true),
            invoker: invoker,
          ).publish(
            origin: origin,
            destination: destination,
            validForSeconds: invalid,
          ),
          throwsArgumentError,
        );
        expect(invoker.calls, 0);
      });
    }

    for (final valid in [900, 14400]) {
      test('$valid saniye kabul edilir', () async {
        expect((await publish(validity: valid)).invoker.calls, 1);
      });
    }

    test('oturum yoksa callable çağrılmaz', () async {
      final invoker = _FakeInvoker(response(), null);
      await expectLater(
        PublishReturnRouteService(
          authSession: _FakeAuth(false),
          invoker: invoker,
        ).publish(
          origin: origin,
          destination: destination,
          validForSeconds: 900,
        ),
        throwsA(isA<PublishReturnRouteException>()),
      );
      expect(invoker.calls, 0);
    });
  });

  group('yanıt mapping', () {
    test(
      'geçerli yanıttan aktif ve hesaplanmış domain rotası üretir',
      () async {
        final published = (await publish()).result;
        expect(published.route.id, 'route-1');
        expect(published.route.driverId, 'driver-1');
        expect(published.route.status, DriverReturnRouteStatus.active);
        expect(published.route.hasCalculatedRoute, isTrue);
        expect(published.encodedPolyline, encoded);
        expect(published.route.routePoints.length, 3);
      },
    );

    test(
      'backend zamanlarını UTC kullanır ve createdAt aktivasyondur',
      () async {
        final route = (await publish()).result.route;
        expect(route.activatedAt?.millisecondsSinceEpoch, activatedAt);
        expect(route.expiresAt?.millisecondsSinceEpoch, expiresAt);
        expect(route.activatedAt?.isUtc, isTrue);
        expect(route.expiresAt?.isUtc, isTrue);
        expect(route.createdAt, route.activatedAt);
        expect(route.isActiveAt(route.activatedAt!), isTrue);
        expect(route.isActiveAt(route.expiresAt!), isFalse);
      },
    );

    test('mesafe, süre ve validity getterları korunur', () async {
      final published = (await publish()).result;
      expect(published.distanceMeters, 12000);
      expect(published.durationSeconds, 1800);
      expect(published.validityDuration, const Duration(hours: 1));
    });

    test('fazladan cevap alanları sonucu etkilemez', () async {
      final data = response()..['extra'] = 'ignored';
      expect((await publish(rawResponse: data)).result.routeId, 'route-1');
    });
  });

  group('bozuk yanıt', () {
    test('map olmayan yanıt reddedilir', () async {
      await expectLater(publish(rawResponse: 'invalid'), throwsFormatException);
    });

    final invalidFields = <String, List<Object?>>{
      'routeId': [null, '', '   '],
      'driverId': [null, '', '   '],
      'status': [null, 'paused'],
      'activatedAtMillis': [null, -1, 10.0, true],
      'expiresAtMillis': [null, activatedAt, activatedAt - 1, 10.0, true],
      'distanceMeters': [null, 0, -1, 10.0, true],
      'durationSeconds': [null, 0, -1, 10.0, true],
      'encodedPolyline': [null, '', '   ', '_p~iF', '_p~iF~ps|U'],
    };
    for (final entry in invalidFields.entries) {
      for (final invalid in entry.value) {
        test('${entry.key}=$invalid reddedilir', () async {
          final data = response()..[entry.key] = invalid;
          await expectLater(publish(rawResponse: data), throwsFormatException);
        });
      }
    }
  });

  group('hatalar ve immutability', () {
    for (final reason in [
      'active_return_route_exists',
      'subscription_required',
      'driver_approval_required',
    ]) {
      test('$reason kaybolmadan aktarılır', () async {
        final error = PublishReturnRouteException(
          code: 'failed-precondition',
          reason: reason,
        );
        await expectLater(
          publish(invocationError: error),
          throwsA(same(error)),
        );
      });
    }

    test('routePoints değiştirilemez', () async {
      final points = (await publish()).result.route.routePoints;
      expect(() => points.add(points.first), throwsUnsupportedError);
    });
  });
}

class _FakeInvoker implements PublishReturnRouteCallableInvoker {
  final Object? response;
  final Object? error;
  int calls = 0;
  Map<String, Object?>? payload;
  _FakeInvoker(this.response, this.error);

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    calls++;
    this.payload = payload;
    if (error != null) throw error!;
    return response;
  }
}

class _FakeAuth implements PublishReturnRouteAuthSession {
  final bool authenticated;
  int calls = 0;
  _FakeAuth(this.authenticated);

  @override
  Future<void> requireAuthenticatedUser() async {
    calls++;
    if (!authenticated) {
      throw const PublishReturnRouteException(code: 'unauthenticated');
    }
  }
}
