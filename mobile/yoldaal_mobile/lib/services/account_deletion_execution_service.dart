import 'package:cloud_functions/cloud_functions.dart';

import '../core/firebase/firebase_functions_registry.dart';

enum AccountDeletionExecutionStatus { processing, completed }

class AccountDeletionExecutionResult {
  const AccountDeletionExecutionResult({
    required this.status,
    required this.idempotent,
  });

  final AccountDeletionExecutionStatus status;
  final bool idempotent;
}

class AccountDeletionExecutionException implements Exception {
  const AccountDeletionExecutionException({required this.code, this.reason});

  final String code;
  final String? reason;
}

typedef AccountDeletionCallableInvoker =
    Future<Object?> Function(String callableName, Map<String, dynamic> payload);

class AccountDeletionExecutionService {
  AccountDeletionExecutionService({
    FirebaseFunctions? functions,
    AccountDeletionCallableInvoker? invoker,
  }) : _invoker =
           invoker ??
           _firebaseInvoker(functions ?? FirebaseFunctionsRegistry.client);

  final AccountDeletionCallableInvoker _invoker;

  static AccountDeletionCallableInvoker _firebaseInvoker(
    FirebaseFunctions functions,
  ) {
    return (callableName, payload) async {
      final callable = functions.httpsCallable(callableName);
      final result = await callable.call<Map<String, Object?>>(payload);
      return result.data;
    };
  }

  Future<AccountDeletionExecutionResult> execute() async {
    Object? raw;
    try {
      raw = await _invoker(
        FirebaseFunctionsRegistry.executeAccountDeletion,
        <String, dynamic>{},
      );
    } on FirebaseFunctionsException catch (error) {
      throw AccountDeletionExecutionException(
        code: error.code,
        reason: _safeReason(error.details),
      );
    } on AccountDeletionExecutionException {
      rethrow;
    } catch (_) {
      throw const AccountDeletionExecutionException(code: 'unavailable');
    }

    if (raw is! Map) {
      throw StateError('Account deletion execution response is invalid.');
    }

    final status = switch (raw['status']) {
      'processing' => AccountDeletionExecutionStatus.processing,
      'completed' => AccountDeletionExecutionStatus.completed,
      _ => null,
    };
    final idempotent = raw['idempotent'];

    if (status == null || idempotent is! bool) {
      throw StateError('Account deletion execution response is invalid.');
    }

    return AccountDeletionExecutionResult(
      status: status,
      idempotent: idempotent,
    );
  }

  static String? _safeReason(Object? details) {
    if (details is! Map) return null;
    final reason = details['reason'];
    if (reason is! String) return null;

    return switch (reason) {
      'active_ride_blocks_account_deletion' => reason,
      'account_deletion_request_required' => reason,
      'account_deletion_request_state_invalid' => reason,
      'account_deletion_execution_lease_lost' => reason,
      'non_terminal_ride_blocks_account_deletion' => reason,
      _ => null,
    };
  }
}
