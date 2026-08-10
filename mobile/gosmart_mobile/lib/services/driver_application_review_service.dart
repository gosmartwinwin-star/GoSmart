import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../application/driver_application/driver_application_repository.dart';
import '../application/driver_application/resubmit_driver_application_gateway.dart';
import '../domain/driver_application/driver_application_document_type.dart';
import '../domain/driver_application/driver_application_review.dart';

class DriverApplicationReviewException implements Exception {
  const DriverApplicationReviewException({required this.code, this.reason});
  final String code;
  final String? reason;
}

abstract interface class DriverApplicationReviewAuthSession {
  Future<void> requireAuthenticatedUser();
}

abstract interface class DriverApplicationReviewCallableInvoker {
  Future<Object?> call(String functionName, Map<String, Object?> payload);
}

class FirebaseDriverApplicationReviewAuthSession
    implements DriverApplicationReviewAuthSession {
  FirebaseDriverApplicationReviewAuthSession({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;
  final FirebaseAuth _auth;

  @override
  Future<void> requireAuthenticatedUser() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const DriverApplicationReviewException(code: 'unauthenticated');
    }
    try {
      await user.getIdToken();
    } on FirebaseAuthException {
      throw const DriverApplicationReviewException(code: 'unauthenticated');
    }
  }
}

class FirebaseDriverApplicationReviewCallableInvoker
    implements DriverApplicationReviewCallableInvoker {
  FirebaseDriverApplicationReviewCallableInvoker({FirebaseFunctions? functions})
    : _functions =
          functions ??
          FirebaseFunctions.instanceFor(
            app: Firebase.app(),
            region: 'europe-west1',
          );
  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(
    String functionName,
    Map<String, Object?> payload,
  ) async {
    try {
      return (await _functions.httpsCallable(functionName).call(payload)).data;
    } on FirebaseFunctionsException catch (error) {
      final details = error.details;
      throw DriverApplicationReviewException(
        code: error.code,
        reason: details is Map && details['reason'] is String
            ? details['reason'] as String
            : null,
      );
    }
  }
}

class DriverApplicationReviewService
    implements DriverApplicationRepository, ResubmitDriverApplicationGateway {
  DriverApplicationReviewService({
    DriverApplicationReviewAuthSession? auth,
    DriverApplicationReviewCallableInvoker? invoker,
  }) : _auth = auth ?? FirebaseDriverApplicationReviewAuthSession(),
       _invoker = invoker ?? FirebaseDriverApplicationReviewCallableInvoker();

  final DriverApplicationReviewAuthSession _auth;
  final DriverApplicationReviewCallableInvoker _invoker;

  @override
  Future<DriverApplicationReview?> findForAuthenticatedUser() async {
    await _auth.requireAuthenticatedUser();
    try {
      return _parseReview(
        await _invoker.call('getMyDriverApplicationStatus', const {}),
      );
    } on DriverApplicationReviewException catch (error) {
      if (error.reason == 'driver_application_not_found') return null;
      rethrow;
    }
  }

  @override
  Future<int> resubmit({
    required int expectedSubmissionVersion,
    required String requestId,
  }) async {
    if (expectedSubmissionVersion < 1 ||
        requestId.length < 16 ||
        requestId.length > 128 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(requestId)) {
      throw const FormatException('Belge gönderim isteği geçersiz.');
    }
    await _auth.requireAuthenticatedUser();
    final response = await _invoker.call('resubmitDriverApplicationDocuments', {
      'expectedSubmissionVersion': expectedSubmissionVersion,
      'requestId': requestId,
    });
    if (response is! Map || response['status'] != 'pendingReview') {
      throw const FormatException('Belge gönderim yanıtı geçersiz.');
    }
    final version = response['submissionVersion'];
    if (version is! int || version <= expectedSubmissionVersion) {
      throw const FormatException('Belge gönderim yanıtı geçersiz.');
    }
    return version;
  }

  DriverApplicationReview _parseReview(Object? raw) {
    if (raw is! Map) throw const FormatException('Başvuru durumu geçersiz.');
    final state = _enumByName(
      DriverApplicationReviewState.values,
      raw['reviewState'],
    );
    final version = raw['submissionVersion'];
    final rawDocuments = raw['documents'];
    if (version is! int || version < 1 || rawDocuments is! List) {
      throw const FormatException('Başvuru durumu geçersiz.');
    }
    final documents = rawDocuments
        .map((value) {
          if (value is! Map) {
            throw const FormatException('Belge durumu geçersiz.');
          }
          final type = _enumByName(
            DriverApplicationDocumentType.values,
            value['documentType'],
          );
          final status = _enumByName(
            DriverApplicationPublicDocumentStatus.values,
            value['reviewStatus'],
          );
          final rawReason = value['reuploadReasonCode'];
          DriverApplicationReuploadReason? reason;
          if (status ==
              DriverApplicationPublicDocumentStatus.reuploadRequired) {
            reason = DriverApplicationReuploadReason.values.firstWhere(
              (item) => item.wireValue == rawReason,
              orElse: () => throw const FormatException(
                'Belge yenileme nedeni geçersiz.',
              ),
            );
          } else if (rawReason != null) {
            throw const FormatException('Belge yenileme nedeni geçersiz.');
          }
          return DriverApplicationReviewDocument(
            type: type,
            status: status,
            reuploadReason: reason,
          );
        })
        .toList(growable: false);
    if (documents.map((item) => item.type).toList().join('|') !=
        DriverApplicationDocumentType.values.join('|')) {
      throw const FormatException('Belge sıralaması geçersiz.');
    }
    DriverApplicationFinalRejectionReason? finalReason;
    final rawApplicationReason = raw['applicationReasonCode'];
    if (state == DriverApplicationReviewState.rejected) {
      finalReason = DriverApplicationFinalRejectionReason.values.firstWhere(
        (item) => item.wireValue == rawApplicationReason,
        orElse: () => throw const FormatException('Ret nedeni geçersiz.'),
      );
    } else if (rawApplicationReason != null) {
      throw const FormatException('Ret nedeni geçersiz.');
    }
    return DriverApplicationReview(
      state: state,
      submissionVersion: version,
      finalRejectionReason: finalReason,
      documents: documents,
    );
  }

  T _enumByName<T extends Enum>(List<T> values, Object? raw) {
    if (raw is! String) throw const FormatException('Durum geçersiz.');
    return values.firstWhere(
      (item) => item.name == raw,
      orElse: () => throw const FormatException('Durum geçersiz.'),
    );
  }
}
