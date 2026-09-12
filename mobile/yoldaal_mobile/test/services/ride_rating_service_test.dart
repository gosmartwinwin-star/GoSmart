import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/ride/ride_gateway.dart';
import 'package:yoldaal_mobile/core/firebase/firebase_functions_registry.dart';
import 'package:yoldaal_mobile/services/ride_lifecycle_service.dart';
import 'package:yoldaal_mobile/services/ride_rating_service.dart';

void main() {
  test('status callable uses exact rideId-only payload and absent schema', () async {
    final invoker = _Invoker()
      ..response = {
        'rideId': 'ride_1',
        'hasSubmitted': false,
      };

    final service = RideRatingService(invoker: invoker);

    final result = await service.getMyRatingStatus(rideId: 'ride_1');

    expect(invoker.names, [FirebaseFunctionsRegistry.getMyRideRatingStatus]);
    expect(invoker.payloads, [
      {'rideId': 'ride_1'},
    ]);
    expect(result.rideId, 'ride_1');
    expect(result.hasSubmitted, isFalse);
    expect(result.rating, isNull);
    expect(result.submittedAt, isNull);
  });

  test('status callable parses only own submitted score and timestamp', () async {
    final invoker = _Invoker()
      ..response = {
        'rideId': 'ride_1',
        'hasSubmitted': true,
        'rating': 4,
        'submittedAtMillis': 123456,
      };

    final service = RideRatingService(invoker: invoker);

    final result = await service.getMyRatingStatus(rideId: 'ride_1');

    expect(result.hasSubmitted, isTrue);
    expect(result.rating, 4);
    expect(
      result.submittedAt,
      DateTime.fromMillisecondsSinceEpoch(123456, isUtc: true),
    );
  });

  test('status response rejects counterpart or private extra fields', () async {
    for (final extra in [
      {'counterpartyRating': 5},
      {'counterpartyHasSubmitted': true},
      {'raterId': 'secret'},
      {'rateeId': 'secret'},
    ]) {
      final invoker = _Invoker()
        ..response = {
          'rideId': 'ride_1',
          'hasSubmitted': false,
          ...extra,
        };

      final service = RideRatingService(invoker: invoker);

      await expectLater(
        service.getMyRatingStatus(rideId: 'ride_1'),
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

  test('submit callable sends exact authoritative payload', () async {
    final invoker = _Invoker()
      ..response = {
        'rideId': 'ride_1',
        'rating': 5,
        'raterRole': 'passenger',
        'submittedAtMillis': 456789,
      };

    final service = RideRatingService(invoker: invoker);

    final result = await service.submitRating(
      rideId: 'ride_1',
      rating: 5,
      requestId: 'rating_request_1234567890',
    );

    expect(invoker.names, [FirebaseFunctionsRegistry.submitRideRating]);
    expect(invoker.payloads, [
      {
        'rideId': 'ride_1',
        'rating': 5,
        'requestId': 'rating_request_1234567890',
      },
    ]);

    expect(result.rideId, 'ride_1');
    expect(result.hasSubmitted, isTrue);
    expect(result.rating, 5);
    expect(
      result.submittedAt,
      DateTime.fromMillisecondsSinceEpoch(456789, isUtc: true),
    );
  });

  test('submit requestId is caller-owned and unchanged across retries', () async {
    final invoker = _Invoker()
      ..failuresRemaining = 1
      ..response = {
        'rideId': 'ride_1',
        'rating': 3,
        'raterRole': 'driver',
        'submittedAtMillis': 999,
      };

    final service = RideRatingService(invoker: invoker);
    const stableRequestId = 'rating_retry_1234567890';

    await expectLater(
      service.submitRating(
        rideId: 'ride_1',
        rating: 3,
        requestId: stableRequestId,
      ),
      throwsA(
        isA<RideGatewayException>().having(
          (error) => error.code,
          'code',
          'unavailable',
        ),
      ),
    );

    final result = await service.submitRating(
      rideId: 'ride_1',
      rating: 3,
      requestId: stableRequestId,
    );

    expect(result.hasSubmitted, isTrue);
    expect(invoker.payloads, [
      {
        'rideId': 'ride_1',
        'rating': 3,
        'requestId': stableRequestId,
      },
      {
        'rideId': 'ride_1',
        'rating': 3,
        'requestId': stableRequestId,
      },
    ]);
  });

  test('local validation rejects invalid ride rating and request ids', () async {
    final service = RideRatingService(invoker: _Invoker());

    expect(
      () => service.getMyRatingStatus(rideId: 'ride/invalid'),
      throwsArgumentError,
    );

    expect(
      () => service.submitRating(
        rideId: 'ride_1',
        rating: 0,
        requestId: 'rating_request_1234567890',
      ),
      throwsArgumentError,
    );

    expect(
      () => service.submitRating(
        rideId: 'ride_1',
        rating: 5,
        requestId: 'short',
      ),
      throwsArgumentError,
    );
  });

  test('gateway errors propagate without exposing them as response data', () async {
    final invoker = _Invoker()
      ..error = const RideGatewayException(
        'failed-precondition',
        reason: 'rating_already_submitted',
      );

    final service = RideRatingService(invoker: invoker);

    await expectLater(
      service.submitRating(
        rideId: 'ride_1',
        rating: 5,
        requestId: 'rating_request_1234567890',
      ),
      throwsA(
        isA<RideGatewayException>()
            .having(
              (error) => error.code,
              'code',
              'failed-precondition',
            )
            .having(
              (error) => error.reason,
              'reason',
              'rating_already_submitted',
            ),
      ),
    );
  });

  test('malformed submit response fails closed', () async {
    final invoker = _Invoker()
      ..response = {
        'rideId': 'ride_1',
        'rating': 5,
        'raterRole': 'passenger',
        'submittedAtMillis': 456789,
        'rateeId': 'must-not-leak',
      };

    final service = RideRatingService(invoker: invoker);

    await expectLater(
      service.submitRating(
        rideId: 'ride_1',
        rating: 5,
        requestId: 'rating_request_1234567890',
      ),
      throwsA(
        isA<RideGatewayException>().having(
          (error) => error.code,
          'code',
          'invalid-response',
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
  int failuresRemaining = 0;

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

    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw const RideGatewayException('unavailable');
    }

    return Map<String, dynamic>.from(response);
  }
}
