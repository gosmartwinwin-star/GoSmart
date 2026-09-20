import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/core/branding/yoldaal_slogans.dart';

void main() {
  test('approved YoldaAl slogans are authoritative', () {
    expect(
      YoldaAlSlogans.brand,
      'Ayn\u0131 Y\u00f6n, Ortak Kazan\u00e7.',
    );
    expect(
      YoldaAlSlogans.driver,
      'Bo\u015f Gitme, D\u00f6n\u00fc\u015f Yolunu De\u011fere \u00c7evir',
    );
    expect(
      YoldaAlSlogans.customer,
      'Ayn\u0131 Rota, \u00c7ok Hesapl\u0131 Fiyat',
    );
  });

  test('master brand assets exist and are non-empty', () {
    final mark = File('assets/images/yoldaal_logo.png');
    final appIcon = File('assets/images/yoldaal_app_icon_master.png');

    expect(mark.existsSync(), isTrue);
    expect(appIcon.existsSync(), isTrue);
    expect(mark.lengthSync(), greaterThan(1000));
    expect(appIcon.lengthSync(), greaterThan(1000));
  });

  test('login uses approved brand surface without taxi placeholder', () {
    final source =
        File('lib/screens/auth/login_screen.dart').readAsStringSync();

    expect(source, contains('YoldaAlBrandMark'));
    expect(source, contains('YoldaAlSlogans.brand'));
    expect(
      source,
      contains('backgroundColor: YoldaAlColors.background'),
    );
    expect(source, contains('Google ile devam et'));
    expect(source, contains('Telefon ile devam et'));
    expect(source, contains('YoldaAlColors.surface'));
    expect(source, contains('YoldaAlColors.divider'));
    expect(source, isNot(contains('Icons.local_taxi')));
    expect(source, isNot(contains('Ortak Yol Ortak Kazan')));
  });

  test('Flutter loading splash uses approved brand surface', () {
    final source =
        File('lib/screens/splash/splash_screen.dart').readAsStringSync();

    expect(source, contains('YoldaAlBrandMark'));
    expect(source, contains('YoldaAlSlogans.brand'));
    expect(
      source,
      contains('backgroundColor: YoldaAlColors.primary'),
    );
    expect(source, isNot(contains('Icons.local_taxi')));
    expect(source, isNot(contains('Colors.amber')));
  });

  test('primary button uses authoritative design system', () {
    final source =
        File('lib/widgets/primary_button.dart').readAsStringSync();

    expect(source, contains('YoldaAlColors.primary'));
    expect(source, contains('YoldaAlRadius.md'));
    expect(source, contains('YoldaAlTypography.button'));
    expect(source, isNot(contains('0xFFFFC107')));
  });
}