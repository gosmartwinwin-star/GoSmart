import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/core/place/place_session_token.dart';

void main() {
  test('session token UUIDv4 biciminde uretilir', () {
    final token = createPlaceSessionToken(
      bytesFactory: (length) {
        expect(length, 16);

        return List<int>.generate(16, (index) => index, growable: false);
      },
    );

    expect(token, '00010203-0405-4607-8809-0a0b0c0d0e0f');

    expect(token.length, 36);

    expect(
      RegExp(
        r'^[0-9a-f]{8}-'
        r'[0-9a-f]{4}-'
        r'4[0-9a-f]{3}-'
        r'[89ab][0-9a-f]{3}-'
        r'[0-9a-f]{12}$',
      ).hasMatch(token),
      isTrue,
    );
  });

  test('invalid byte factory fail closed olur', () {
    expect(
      () => createPlaceSessionToken(bytesFactory: (_) => [1, 2, 3]),
      throwsArgumentError,
    );
  });
}
