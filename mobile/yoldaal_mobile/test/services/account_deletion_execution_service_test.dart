import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/core/firebase/firebase_functions_registry.dart';
import 'package:yoldaal_mobile/services/account_deletion_execution_service.dart';

void main() {
  test('registry exposes exact account deletion callable names', () {
    expect(
      FirebaseFunctionsRegistry.requestAccountDeletion,
      'requestAccountDeletion',
    );
    expect(
      FirebaseFunctionsRegistry.executeAccountDeletion,
      'executeAccountDeletion',
    );
  });

  test('execution uses exact callable and exact empty payload', () async {
    String? callable;
    Map<String, dynamic>? payload;

    final service = AccountDeletionExecutionService(
      invoker: (name, data) async {
        callable = name;
        payload = data;
        return <String, Object?>{'status': 'completed', 'idempotent': false};
      },
    );

    final result = await service.execute();

    expect(callable, 'executeAccountDeletion');
    expect(payload, isEmpty);
    expect(result.status, AccountDeletionExecutionStatus.completed);
    expect(result.idempotent, isFalse);
  });

  test('processing response is parsed without claiming completion', () async {
    final service = AccountDeletionExecutionService(
      invoker: (_, _) async => <String, Object?>{
        'status': 'processing',
        'idempotent': true,
      },
    );

    final result = await service.execute();

    expect(result.status, AccountDeletionExecutionStatus.processing);
    expect(result.idempotent, isTrue);
  });

  test('malformed responses fail closed', () async {
    for (final response in <Object?>[
      null,
      'completed',
      <String, Object?>{'status': 'completed'},
      <String, Object?>{'status': 'unknown', 'idempotent': false},
      <String, Object?>{'status': 'completed', 'idempotent': 'false'},
    ]) {
      final service = AccountDeletionExecutionService(
        invoker: (_, _) async => response,
      );

      await expectLater(service.execute(), throwsA(isA<StateError>()));
    }
  });

  test(
    'unknown local invocation failures become bounded unavailable',
    () async {
      final service = AccountDeletionExecutionService(
        invoker: (_, _) async => throw Exception('secret raw failure'),
      );

      await expectLater(
        service.execute(),
        throwsA(
          isA<AccountDeletionExecutionException>().having(
            (error) => error.code,
            'code',
            'unavailable',
          ),
        ),
      );
    },
  );
}
