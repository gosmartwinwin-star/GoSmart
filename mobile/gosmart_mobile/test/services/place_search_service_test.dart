import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/ride/ride_gateway.dart';
import 'package:gosmart_mobile/services/place_search_service.dart';
import 'package:gosmart_mobile/services/ride_lifecycle_service.dart';

void main() {
  test('service olusturmak Functions registry gerektirmez', () {
    expect(() => PlaceSearchService(), returnsNormally);
  });

  const token = '123e4567-e89b-42d3-a456-426614174000';

  test('autocomplete exact payload ve suggestions map eder', () async {
    final invoker = _Invoker()
      ..response = {
        'suggestions': [
          {
            'placeId': 'place-1',
            'title': 'Taksim Meydani',
            'description': 'Beyoglu/Istanbul',
          },
          {
            'placeId': 'place-2',
            'title': 'Taksim Gezi Parki',
            'description': '',
          },
        ],
      };

    final result = await PlaceSearchService(
      invoker: invoker,
    ).search(input: '  Taksim  ', sessionToken: token);

    expect(invoker.name, 'searchPlaces');
    expect(invoker.payload, {'input': 'Taksim', 'sessionToken': token});

    expect(result, hasLength(2));
    expect(result[0].placeId, 'place-1');
    expect(result[0].title, 'Taksim Meydani');
    expect(result[0].description, 'Beyoglu/Istanbul');
    expect(result[1].placeId, 'place-2');
    expect(result[1].description, '');
  });

  test('bos autocomplete sonucu bos liste olur', () async {
    final invoker = _Invoker()..response = {'suggestions': <Object?>[]};

    final result = await PlaceSearchService(
      invoker: invoker,
    ).search(input: 'Galata', sessionToken: token);

    expect(result, isEmpty);
  });

  test('malformed autocomplete response fail closed olur', () async {
    final invoker = _Invoker()
      ..response = {
        'suggestions': [
          {'placeId': '', 'title': 'Broken', 'description': ''},
        ],
      };

    await expectLater(
      PlaceSearchService(
        invoker: invoker,
      ).search(input: 'Galata', sessionToken: token),
      throwsA(
        isA<RideGatewayException>().having(
          (error) => error.code,
          'code',
          'invalid-response',
        ),
      ),
    );
  });

  test('place details exact payload ile AddressModel uretir', () async {
    final invoker = _Invoker()
      ..response = {
        'place': {
          'id': 'place-1',
          'title': 'Galata Kulesi',
          'description': 'Bereketzade, Beyoglu/Istanbul',
          'latitude': 41.0256,
          'longitude': 28.9741,
        },
      };

    final result = await PlaceSearchService(
      invoker: invoker,
    ).resolve(placeId: '  place-1  ', sessionToken: token);

    expect(invoker.name, 'resolvePlace');
    expect(invoker.payload, {'placeId': 'place-1', 'sessionToken': token});

    expect(result.id, 'place-1');
    expect(result.title, 'Galata Kulesi');
    expect(result.description, 'Bereketzade, Beyoglu/Istanbul');
    expect(result.latitude, 41.0256);
    expect(result.longitude, 28.9741);
    expect(result.favorite, isFalse);
  });

  test('gecersiz coordinate response fail closed olur', () async {
    final invoker = _Invoker()
      ..response = {
        'place': {
          'id': 'place-1',
          'title': 'Broken',
          'description': 'Broken',
          'latitude': 91,
          'longitude': 28.9,
        },
      };

    await expectLater(
      PlaceSearchService(
        invoker: invoker,
      ).resolve(placeId: 'place-1', sessionToken: token),
      throwsA(
        isA<RideGatewayException>().having(
          (error) => error.code,
          'code',
          'invalid-response',
        ),
      ),
    );
  });

  test('gateway code ve reason korunur', () async {
    final invoker = _Invoker()
      ..error = const RideGatewayException(
        'unavailable',
        reason: 'places_upstream_error',
      );

    await expectLater(
      PlaceSearchService(
        invoker: invoker,
      ).search(input: 'Taksim', sessionToken: token),
      throwsA(
        isA<RideGatewayException>()
            .having((error) => error.code, 'code', 'unavailable')
            .having((error) => error.reason, 'reason', 'places_upstream_error'),
      ),
    );
  });

  test('short input callable calismadan reddedilir', () async {
    final invoker = _Invoker();

    await expectLater(
      PlaceSearchService(
        invoker: invoker,
      ).search(input: 'Ta', sessionToken: token),
      throwsArgumentError,
    );

    expect(invoker.calls, 0);
  });

  test('invalid session token callable calismadan reddedilir', () async {
    final invoker = _Invoker();

    await expectLater(
      PlaceSearchService(
        invoker: invoker,
      ).search(input: 'Taksim', sessionToken: 'bad token'),
      throwsArgumentError,
    );

    expect(invoker.calls, 0);
  });
}

class _Invoker implements RideCallableInvoker {
  String? name;
  Map<String, dynamic>? payload;
  Map<String, dynamic> response = {'suggestions': <Object?>[]};
  RideGatewayException? error;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> call(
    String value,
    Map<String, dynamic> data,
  ) async {
    calls += 1;
    name = value;
    payload = Map<String, dynamic>.from(data);

    if (error case final failure?) {
      throw failure;
    }

    return response;
  }
}
