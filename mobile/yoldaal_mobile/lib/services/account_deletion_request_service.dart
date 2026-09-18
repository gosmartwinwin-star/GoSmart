import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

class AccountDeletionRequestService {
  AccountDeletionRequestService({
    FirebaseFunctions? functions,
  }) : _functions =
           functions ??
           FirebaseFunctions.instanceFor(
             app: Firebase.app(),
             region: 'europe-west1',
           );

  final FirebaseFunctions _functions;

  Future<void> requestDeletion() async {
    final callable =
        _functions.httpsCallable(
      'requestAccountDeletion',
    );

    final result = await callable.call(
      <String, dynamic>{},
    );

    final data = result.data;

    if (
      data is! Map ||
      data['status'] != 'requested'
    ) {
      throw StateError(
        'Account deletion request response is invalid.',
      );
    }
  }
}