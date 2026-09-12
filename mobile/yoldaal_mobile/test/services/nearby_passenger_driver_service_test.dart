import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/services/nearby_passenger_driver_service.dart';

void main() {
  test(
    'loads privacy-minimal nearby projections using exact empty callable payload',
    () async {
      String? calledName;
      Map<String, dynamic>? calledPayload;

      final service = NearbyPassengerDriverService(
        caller: (name, payload) async {
          calledName = name;
          calledPayload = payload;

          return <Object?>[
            <String, Object?>{
              'latitude': 41.0082,
              'longitude': 28.9784,
              'updatedAtMillis': 123456,
            },
            <String, Object?>{
              'latitude': 41,
              'longitude': 29,
              'updatedAtMillis': 123400,
            },
          ];
        },
      );

      final result = await service.load();

      expect(
        calledName,
        NearbyPassengerDriverService.callableName,
      );

      expect(
        calledName,
        'getNearbyPassengerDrivers',
      );

      expect(
        calledPayload,
        isEmpty,
      );

      expect(
        result,
        hasLength(2),
      );

      expect(
        result.first.latitude,
        41.0082,
      );

      expect(
        result.first.longitude,
        28.9784,
      );

      expect(
        result.first.updatedAtMillis,
        123456,
      );

      expect(
        result[1].latitude,
        41.0,
      );

      expect(
        result[1].longitude,
        29.0,
      );

      expect(
        () => result.add(
          const NearbyPassengerDriverProjection(
            latitude: 0,
            longitude: 0,
            updatedAtMillis: 0,
          ),
        ),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'accepts complete empty discovery result',
    () async {
      final service = NearbyPassengerDriverService(
        caller: (_, _) async => <Object?>[],
      );

      expect(
        await service.load(),
        isEmpty,
      );
    },
  );

  test(
    'fails closed for malformed public discovery responses',
    () async {
      final malformedResponses = <Object?>[
        null,
        <String, Object?>{},
        <Object?>[
          <Object?>[],
        ],
        <Object?>[
          <String, Object?>{
            'latitude': 41.0,
            'longitude': 29.0,
          },
        ],
        <Object?>[
          <String, Object?>{
            'latitude': 41.0,
            'longitude': 29.0,
            'updatedAtMillis': 1,
            'extra': true,
          },
        ],
        <Object?>[
          <String, Object?>{
            'latitude': 91.0,
            'longitude': 29.0,
            'updatedAtMillis': 1,
          },
        ],
        <Object?>[
          <String, Object?>{
            'latitude': 41.0,
            'longitude': 181.0,
            'updatedAtMillis': 1,
          },
        ],
        <Object?>[
          <String, Object?>{
            'latitude': double.nan,
            'longitude': 29.0,
            'updatedAtMillis': 1,
          },
        ],
        <Object?>[
          <String, Object?>{
            'latitude': 41.0,
            'longitude': double.infinity,
            'updatedAtMillis': 1,
          },
        ],
        <Object?>[
          <String, Object?>{
            'latitude': 41.0,
            'longitude': 29.0,
            'updatedAtMillis': -1,
          },
        ],
        <Object?>[
          <String, Object?>{
            'latitude': 41.0,
            'longitude': 29.0,
            'updatedAtMillis': 1.5,
          },
        ],
      ];

      for (final raw in malformedResponses) {
        final service = NearbyPassengerDriverService(
          caller: (_, _) async => raw,
        );

        await expectLater(
          service.load(),
          throwsA(
            isA<NearbyPassengerDriverDiscoveryException>().having(
              (error) => error.code,
              'code',
              'unavailable',
            ),
          ),
        );
      }
    },
  );

  test(
    'preserves controlled service exception from injected caller',
    () async {
      final service = NearbyPassengerDriverService(
        caller: (_, _) async {
          throw const NearbyPassengerDriverDiscoveryException(
            code: 'failed-precondition',
            reason: 'passenger_ride_not_matching',
          );
        },
      );

      await expectLater(
        service.load(),
        throwsA(
          isA<NearbyPassengerDriverDiscoveryException>()
              .having(
                (error) => error.code,
                'code',
                'failed-precondition',
              )
              .having(
                (error) => error.reason,
                'reason',
                'passenger_ride_not_matching',
              ),
        ),
      );
    },
  );

  test(
    'maps unknown caller failure to safe unavailable',
    () async {
      final service = NearbyPassengerDriverService(
        caller: (_, _) async {
          throw StateError('internal detail');
        },
      );

      await expectLater(
        service.load(),
        throwsA(
          isA<NearbyPassengerDriverDiscoveryException>()
              .having(
                (error) => error.code,
                'code',
                'unavailable',
              )
              .having(
                (error) => error.reason,
                'reason',
                isNull,
              ),
        ),
      );
    },
  );
}
