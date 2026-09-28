import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/services/account_deletion_web_auth_service.dart';

void main() {
  const googleUser = AccountDeletionWebAuthUser(
    uid: 'google-user',
    email: 'user@example.com',
    providerIds: <String>['google.com'],
  );
  const phoneUser = AccountDeletionWebAuthUser(
    uid: 'phone-user',
    phoneNumber: '+905551234567',
    providerIds: <String>['phone'],
  );

  test('google sign-in delegates and returns authenticated user', () async {
    var calls = 0;
    final service = AccountDeletionWebAuthService(
      googleSignIn: () async {
        calls++;
        return googleUser;
      },
      phoneStart: (_) async => _FakePhoneConfirmation(phoneUser),
      signOut: () async {},
    );

    final result = await service.signInWithGoogle();

    expect(calls, 1);
    expect(result.uid, 'google-user');
    expect(result.identityLabel, 'user@example.com');
  });

  test('phone flow uses normalized number then confirms exact code', () async {
    String? phone;
    final confirmation = _FakePhoneConfirmation(phoneUser);
    final service = AccountDeletionWebAuthService(
      googleSignIn: () async => googleUser,
      phoneStart: (value) async {
        phone = value;
        return confirmation;
      },
      signOut: () async {},
    );

    await service.startPhoneSignIn('  +905551234567  ');
    expect(service.hasPendingPhoneConfirmation, isTrue);

    final result = await service.confirmPhoneCode(' 123456 ');

    expect(phone, '+905551234567');
    expect(confirmation.code, '123456');
    expect(result.uid, 'phone-user');
    expect(service.hasPendingPhoneConfirmation, isFalse);
  });

  test('invalid phone fails closed before invoking provider', () async {
    var phoneStartCalls = 0;
    final service = AccountDeletionWebAuthService(
      googleSignIn: () async => googleUser,
      phoneStart: (_) async {
        phoneStartCalls++;
        return _FakePhoneConfirmation(phoneUser);
      },
      signOut: () async {},
    );

    await expectLater(
      service.startPhoneSignIn('0555 123 45 67'),
      throwsA(isA<FormatException>()),
    );
    expect(phoneStartCalls, 0);
  });

  test('confirmation without pending phone flow fails closed', () async {
    final service = AccountDeletionWebAuthService(
      googleSignIn: () async => googleUser,
      phoneStart: (_) async => _FakePhoneConfirmation(phoneUser),
      signOut: () async {},
    );

    await expectLater(
      service.confirmPhoneCode('123456'),
      throwsA(isA<StateError>()),
    );
  });

  test('sign-out clears pending phone confirmation', () async {
    var signOutCalls = 0;
    final service = AccountDeletionWebAuthService(
      googleSignIn: () async => googleUser,
      phoneStart: (_) async => _FakePhoneConfirmation(phoneUser),
      signOut: () async {
        signOutCalls++;
      },
    );

    await service.startPhoneSignIn('+905551234567');
    expect(service.hasPendingPhoneConfirmation, isTrue);

    await service.signOut();

    expect(signOutCalls, 1);
    expect(service.hasPendingPhoneConfirmation, isFalse);
  });
}

class _FakePhoneConfirmation implements AccountDeletionPhoneConfirmation {
  _FakePhoneConfirmation(this.user);

  final AccountDeletionWebAuthUser user;
  String? code;

  @override
  Future<AccountDeletionWebAuthUser> confirm(String verificationCode) async {
    code = verificationCode;
    return user;
  }
}
