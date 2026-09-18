import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/core/firebase/firebase_functions_registry.dart';
import 'package:yoldaal_mobile/services/passenger_push_target_registration_service.dart';

void main() {
  const canonicalFid = 'cR4Vv5T6u7W8x9Y0z1_A-b';

  test('registry exposes exact registerPassengerPushTarget callable name', () {
    expect(
      FirebaseFunctionsRegistry.registerPassengerPushTarget,
      'registerPassengerPushTarget',
    );
  });

  test('platform wire values are exact', () {
    expect(PassengerPushTargetPlatform.android.wireValue, 'android');
    expect(PassengerPushTargetPlatform.ios.wireValue, 'ios');
  });

  test(
    'unauthenticated current registration stops before FID and callable',
    () async {
      final source = _FakeInstallationIdSource(fid: canonicalFid);
      final invoker = _FakeInvoker(response: const {'updatedAtMillis': 123});

      await expectLater(
        PassengerPushTargetRegistrationService(
          authSession: _FakeAuth(authenticated: false),
          installationIdSource: source,
          invoker: invoker,
        ).registerCurrentInstallation(
          platform: PassengerPushTargetPlatform.android,
        ),
        throwsA(
          isA<PassengerPushTargetRegistrationException>().having(
            (error) => error.code,
            'code',
            'unauthenticated',
          ),
        ),
      );

      expect(source.getIdCalls, 0);
      expect(invoker.calls, 0);
    },
  );

  test('current installation sends exact FID and Android payload', () async {
    final source = _FakeInstallationIdSource(fid: canonicalFid);
    final invoker = _FakeInvoker(response: const {'updatedAtMillis': 123});

    final result =
        await PassengerPushTargetRegistrationService(
          authSession: _FakeAuth(authenticated: true),
          installationIdSource: source,
          invoker: invoker,
        ).registerCurrentInstallation(
          platform: PassengerPushTargetPlatform.android,
        );

    expect(source.getIdCalls, 1);
    expect(invoker.calls, 1);
    expect(invoker.payload, {'fid': canonicalFid, 'platform': 'android'});
    expect(invoker.payload?.length, 2);
    expect(result.updatedAtMillis, 123);
  });

  test(
    'changed FID can be registered without reacquiring current ID',
    () async {
      final source = _FakeInstallationIdSource(fid: canonicalFid);
      final invoker = _FakeInvoker(response: const {'updatedAtMillis': 456});
      const changedFid = 'opaque/fid+value=alpha';

      final result =
          await PassengerPushTargetRegistrationService(
            authSession: _FakeAuth(authenticated: true),
            installationIdSource: source,
            invoker: invoker,
          ).registerInstallationId(
            fid: changedFid,
            platform: PassengerPushTargetPlatform.ios,
          );

      expect(source.getIdCalls, 0);
      expect(invoker.calls, 1);
      expect(invoker.payload, {'fid': changedFid, 'platform': 'ios'});
      expect(result.updatedAtMillis, 456);
    },
  );

  test(
    'FID validation mirrors opaque 8 to 512 no-whitespace contract',
    () async {
      final invoker = _FakeInvoker(response: const {'updatedAtMillis': 1});
      final service = PassengerPushTargetRegistrationService(
        authSession: _FakeAuth(authenticated: true),
        installationIdSource: _FakeInstallationIdSource(fid: canonicalFid),
        invoker: invoker,
      );

      await service.registerInstallationId(
        fid: 'a' * 512,
        platform: PassengerPushTargetPlatform.android,
      );

      expect(invoker.calls, 1);

      for (final invalid in [
        'a' * 7,
        ' abcdefgh',
        'abcdefgh ',
        'abcd efgh',
        'a' * 513,
      ]) {
        await expectLater(
          service.registerInstallationId(
            fid: invalid,
            platform: PassengerPushTargetPlatform.android,
          ),
          throwsFormatException,
        );
      }

      expect(invoker.calls, 1);
    },
  );

  test('response must contain only integer updatedAtMillis', () async {
    Future<void> expectInvalid(Object? response) async {
      await expectLater(
        PassengerPushTargetRegistrationService(
          authSession: _FakeAuth(authenticated: true),
          installationIdSource: _FakeInstallationIdSource(fid: canonicalFid),
          invoker: _FakeInvoker(response: response),
        ).registerCurrentInstallation(
          platform: PassengerPushTargetPlatform.android,
        ),
        throwsFormatException,
      );
    }

    await expectInvalid(const <String, Object?>{});
    await expectInvalid(const {'updatedAtMillis': '123'});
    await expectInvalid(const {
      'updatedAtMillis': 123,
      'driverId': 'forbidden',
    });
  });

  test('callable domain exception preserves safe code and reason', () async {
    await expectLater(
      PassengerPushTargetRegistrationService(
        authSession: _FakeAuth(authenticated: true),
        installationIdSource: _FakeInstallationIdSource(fid: canonicalFid),
        invoker: _FakeInvoker(
          error: const PassengerPushTargetRegistrationException(
            code: 'failed-precondition',
            reason: 'subscription_required',
          ),
        ),
      ).registerCurrentInstallation(
        platform: PassengerPushTargetPlatform.android,
      ),
      throwsA(
        isA<PassengerPushTargetRegistrationException>()
            .having((error) => error.code, 'code', 'failed-precondition')
            .having((error) => error.reason, 'reason', 'subscription_required'),
      ),
    );
  });

  test(
    'installation ID change stream is exposed without side effects',
    () async {
      final source = _FakeInstallationIdSource(
        fid: canonicalFid,
        changes: Stream<String>.fromIterable(const [
          'fid-change-1',
          'fid-change-2',
        ]),
      );

      final service = PassengerPushTargetRegistrationService(
        authSession: _FakeAuth(authenticated: true),
        installationIdSource: source,
        invoker: _FakeInvoker(response: const {'updatedAtMillis': 1}),
      );

      await expectLater(
        service.installationIdChanges,
        emitsInOrder(const ['fid-change-1', 'fid-change-2']),
      );

      expect(source.getIdCalls, 0);
    },
  );
}

class _FakeAuth implements PassengerPushTargetAuthSession {
  _FakeAuth({required this.authenticated});

  final bool authenticated;
  int calls = 0;

  @override
  Future<void> requireAuthenticatedUser() async {
    calls++;

    if (!authenticated) {
      throw const PassengerPushTargetRegistrationException(
        code: 'unauthenticated',
      );
    }
  }
}

class _FakeInstallationIdSource implements PassengerPushInstallationIdSource {
  _FakeInstallationIdSource({required this.fid, Stream<String>? changes})
    : changes = changes ?? const Stream<String>.empty();

  final String fid;
  final Stream<String> changes;

  int getIdCalls = 0;

  @override
  Future<String> getId() async {
    getIdCalls++;
    return fid;
  }

  @override
  Stream<String> get onIdChange => changes;
}

class _FakeInvoker implements PassengerPushTargetCallableInvoker {
  _FakeInvoker({this.response, this.error});

  final Object? response;
  final Object? error;

  int calls = 0;
  Map<String, Object?>? payload;

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
