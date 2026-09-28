import 'package:cloud_functions/cloud_functions.dart';

import '../core/firebase/firebase_functions_registry.dart';

class AccountDeletionRequestService {
  AccountDeletionRequestService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctionsRegistry.client;

  final FirebaseFunctions _functions;

  Future<void> requestDeletion() async {
    final callable = _functions.httpsCallable(
      FirebaseFunctionsRegistry.requestAccountDeletion,
    );

    final result = await callable.call(<String, dynamic>{});

    final data = result.data;

    if (data is! Map || data['status'] != 'requested') {
      throw StateError('Account deletion request response is invalid.');
    }
  }
}
