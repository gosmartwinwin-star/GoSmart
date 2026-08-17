import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/place/place_search_gateway.dart';
import 'package:gosmart_mobile/application/ride/ride_gateway.dart';
import 'package:gosmart_mobile/models/address_model.dart';
import 'package:gosmart_mobile/screens/search/search_address_screen.dart';

void main() {
  const token = '123e4567-e89b-42d3-a456-426614174000';

  testWidgets('uc karakterden once autocomplete cagrisi yapilmaz', (
    tester,
  ) async {
    final gateway = _FakeGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: SearchAddressScreen(
          gateway: gateway,
          sessionTokenFactory: () => token,
          debounceDuration: const Duration(milliseconds: 10),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Ta');

    await tester.pump(const Duration(milliseconds: 20));

    expect(gateway.searchCalls, isEmpty);

    expect(find.text('Aramak için en az 3 karakter girin.'), findsOneWidget);
  });

  testWidgets(
    'debounce sonrasi suggestion ve Google Maps attribution gorunur',
    (tester) async {
      final gateway = _FakeGateway()
        ..suggestions = const [
          PlaceSearchSuggestion(
            placeId: 'taksim-1',
            title: 'Taksim Meydanı',
            description: 'Beyoğlu/İstanbul',
          ),
        ];

      await tester.pumpWidget(
        MaterialApp(
          home: SearchAddressScreen(
            gateway: gateway,
            sessionTokenFactory: () => token,
            debounceDuration: const Duration(milliseconds: 10),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '  Taksim  ');

      await tester.pump(const Duration(milliseconds: 11));

      await tester.pump();

      expect(gateway.searchCalls, [(input: 'Taksim', token: token)]);

      expect(find.text('Taksim Meydanı'), findsOneWidget);

      expect(
        find.byKey(const ValueKey('google_maps_attribution')),
        findsOneWidget,
      );

      expect(find.text('Google Maps'), findsOneWidget);
    },
  );

  testWidgets('eski autocomplete cevabi yeni sorgunun sonucunu ezmez', (
    tester,
  ) async {
    final galata = Completer<List<PlaceSearchSuggestion>>();

    final taksim = Completer<List<PlaceSearchSuggestion>>();

    final gateway = _FakeGateway()
      ..pending['Galata'] = galata
      ..pending['Taksim'] = taksim;

    await tester.pumpWidget(
      MaterialApp(
        home: SearchAddressScreen(
          gateway: gateway,
          sessionTokenFactory: () => token,
          debounceDuration: const Duration(milliseconds: 10),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Galata');

    await tester.pump(const Duration(milliseconds: 11));

    await tester.enterText(find.byType(TextField), 'Taksim');

    await tester.pump(const Duration(milliseconds: 11));

    taksim.complete(const [
      PlaceSearchSuggestion(
        placeId: 'new',
        title: 'Taksim Sonucu',
        description: '',
      ),
    ]);

    await tester.pump();

    expect(find.text('Taksim Sonucu'), findsOneWidget);

    galata.complete(const [
      PlaceSearchSuggestion(
        placeId: 'old',
        title: 'Eski Galata Sonucu',
        description: '',
      ),
    ]);

    await tester.pump();

    expect(find.text('Taksim Sonucu'), findsOneWidget);

    expect(find.text('Eski Galata Sonucu'), findsNothing);
  });

  testWidgets(
    'suggestion secimi ayni token ile resolve edilip AddressModel dondurur',
    (tester) async {
      final gateway = _FakeGateway()
        ..suggestions = const [
          PlaceSearchSuggestion(
            placeId: 'galata-1',
            title: 'Galata Kulesi',
            description: 'Beyoğlu/İstanbul',
          ),
        ]
        ..resolved = const AddressModel(
          id: 'galata-1',
          title: 'Galata Kulesi',
          description: 'Bereketzade, Beyoğlu/İstanbul',
          latitude: 41.0256,
          longitude: 28.9741,
        );

      AddressModel? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      selected = await Navigator.of(context).push<AddressModel>(
                        MaterialPageRoute(
                          builder: (_) => SearchAddressScreen(
                            gateway: gateway,
                            sessionTokenFactory: () => token,
                            debounceDuration: const Duration(milliseconds: 10),
                          ),
                        ),
                      );
                    },
                    child: const Text('Adres Seç'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Adres Seç'));

      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Galata');

      await tester.pump(const Duration(milliseconds: 11));

      await tester.pump();

      await tester.tap(find.text('Galata Kulesi'));

      await tester.pumpAndSettle();

      expect(gateway.resolveCalls, [(placeId: 'galata-1', token: token)]);

      expect(selected?.id, 'galata-1');

      expect(selected?.latitude, 41.0256);
    },
  );

  testWidgets('raw gateway hatasi kullaniciya sizdirilmaz', (tester) async {
    final gateway = _FakeGateway()
      ..searchError = const RideGatewayException(
        'unavailable',
        reason: 'RAW_SECRET_REASON',
      );

    await tester.pumpWidget(
      MaterialApp(
        home: SearchAddressScreen(
          gateway: gateway,
          sessionTokenFactory: () => token,
          debounceDuration: const Duration(milliseconds: 10),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Taksim');

    await tester.pump(const Duration(milliseconds: 11));

    await tester.pump();

    expect(find.textContaining('RAW_SECRET_REASON'), findsNothing);

    expect(
      find.text(
        'Adres araması şu anda kullanılamıyor. '
        'Tekrar deneyin.',
      ),
      findsOneWidget,
    );

    expect(find.byKey(const ValueKey('place_search_retry')), findsOneWidget);
  });
}

class _FakeGateway implements PlaceSearchGateway {
  List<PlaceSearchSuggestion> suggestions = const [];

  AddressModel resolved = const AddressModel(
    id: 'default',
    title: 'Default',
    description: '',
    latitude: 41,
    longitude: 29,
  );

  Object? searchError;
  Object? resolveError;

  final pending = <String, Completer<List<PlaceSearchSuggestion>>>{};

  final searchCalls = <({String input, String token})>[];

  final resolveCalls = <({String placeId, String token})>[];

  @override
  Future<List<PlaceSearchSuggestion>> search({
    required String input,
    required String sessionToken,
  }) async {
    searchCalls.add((input: input, token: sessionToken));

    if (searchError case final error?) {
      throw error;
    }

    final completer = pending[input];

    if (completer != null) {
      return completer.future;
    }

    return suggestions;
  }

  @override
  Future<AddressModel> resolve({
    required String placeId,
    required String sessionToken,
  }) async {
    resolveCalls.add((placeId: placeId, token: sessionToken));

    if (resolveError case final error?) {
      throw error;
    }

    return resolved;
  }
}
