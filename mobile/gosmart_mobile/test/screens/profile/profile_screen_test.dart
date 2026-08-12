import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/screens/profile/profile_screen.dart';

void main() {
  test('telefon numarası maskelenir ve boş değer güvenli fallback üretir', () {
    expect(ProfileScreen.maskedPhoneNumber('+905551234567'), '•••••••••4567');
    expect(
      ProfileScreen.maskedPhoneNumber(null),
      'Telefon numarası bulunamadı',
    );
    expect(
      ProfileScreen.maskedPhoneNumber('  '),
      'Telefon numarası bulunamadı',
    );
  });

  testWidgets('çıkış onayı iptal edilirse signOut çağrılmaz', (tester) async {
    var calls = 0;
    await _show(tester, signOut: () async {
      calls++;
    });

    await tester.tap(find.text('Çıkış Yap'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('İptal'));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  testWidgets('başarılı çıkış Profil rotasını kapatır', (tester) async {
    var calls = 0;
    await _showOnSentinel(tester, signOut: () async {
      calls++;
    });

    await _confirm(tester);

    expect(calls, 1);
    expect(find.byType(ProfileScreen), findsNothing);
    expect(find.text('Oturum kapandı'), findsOneWidget);
  });

  testWidgets('pending çıkış duplicate invocation üretmez', (tester) async {
    final completer = Completer<void>();
    var calls = 0;
    await _show(tester, signOut: () {
      calls++;
      return completer.future;
    });

    await tester.tap(find.text('Çıkış Yap'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Çıkış Yap'));
    await tester.pump();

    expect(calls, 1);
    final pendingButton = tester.widget<OutlinedButton>(
      find.byType(OutlinedButton),
    );
    expect(pendingButton.onPressed, isNull);
    expect(find.text('Çıkış yapılıyor...'), findsOneWidget);
    expect(calls, 1);

    completer.complete();
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('çıkış hatası gösterilir ve kontrol tekrar kullanılabilir', (
    tester,
  ) async {
    var calls = 0;
    await _show(tester, signOut: () async {
      calls++;
      throw Exception('secret');
    });

    await _confirm(tester);

    expect(
      find.text(
        'Çıkış yapılamadı. Bağlantınızı kontrol edip tekrar deneyin.',
      ),
      findsOneWidget,
    );
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNotNull,
    );

    await _confirm(tester);
    expect(calls, 2);
  });
}

Future<void> _showOnSentinel(
  WidgetTester tester, {
  required SignOutCallback signOut,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(
            children: [
              const Text('Oturum kapandı'),
              ElevatedButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(
                      phoneNumber: '+905551234567',
                      signOut: signOut,
                    ),
                  ),
                ),
                child: const Text('Profili aç'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Profili aç'));
  await tester.pumpAndSettle();
  expect(find.byType(ProfileScreen), findsOneWidget);
}

Future<void> _show(
  WidgetTester tester, {
  required SignOutCallback signOut,
  String? phoneNumber = '+905551234567',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ProfileScreen(phoneNumber: phoneNumber, signOut: signOut),
    ),
  );
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(find.text('Çıkış Yap'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Çıkış Yap'));
  await tester.pumpAndSettle();
}
