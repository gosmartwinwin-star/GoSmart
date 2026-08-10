import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/domain/driver_application/driver_application_document_type.dart';
import 'package:gosmart_mobile/domain/driver_application/driver_application_review.dart';
import 'package:gosmart_mobile/services/driver_application_review_service.dart';

void main() {
  Map<String, Object?> response({
    String state = 'awaitingDocumentResubmission',
    String? applicationReason,
    String firstStatus = 'reuploadRequired',
    String? firstReason = 'unreadable_document',
  }) => {
    'reviewState': state,
    'submissionVersion': 2,
    'applicationReasonCode': ?applicationReason,
    'documents': [
      for (final type in DriverApplicationDocumentType.values)
        {
          'documentType': type.name,
          'reviewStatus': type.index == 0 ? firstStatus : 'pendingReview',
          if (type.index == 0) 'reuploadReasonCode': ?firstReason,
        },
    ],
    'ignoredInternalField': 'ignored',
  };

  test('status callable uses exact name and empty payload', () async {
    final invoker = _Invoker(response());
    await DriverApplicationReviewService(
      auth: _Auth(),
      invoker: invoker,
    ).findForAuthenticatedUser();
    expect(invoker.name, 'getMyDriverApplicationStatus');
    expect(invoker.payload, isEmpty);
    for (final key in ['uid', 'applicationId', 'documentSetId']) {
      expect(invoker.payload, isNot(contains(key)));
    }
  });

  for (final state in DriverApplicationReviewState.values) {
    test('${state.name} exact parse edilir', () async {
      final finalReason = state == DriverApplicationReviewState.rejected
          ? 'duplicate_application'
          : null;
      final value = await DriverApplicationReviewService(
        auth: _Auth(),
        invoker: _Invoker(
          response(
            state: state.name,
            applicationReason: finalReason,
            firstStatus: 'pendingReview',
            firstReason: null,
          ),
        ),
      ).findForAuthenticatedUser();
      expect(value!.state, state);
    });
  }

  test('unknown application/document state and type fail safely', () async {
    for (final mutate in <void Function(Map<String, Object?>)>[
      (value) => value['reviewState'] = 'raw-state',
      (value) =>
          ((value['documents'] as List).first as Map)['documentType'] = 'raw',
      (value) =>
          ((value['documents'] as List).first as Map)['reviewStatus'] = 'raw',
    ]) {
      final value = response();
      mutate(value);
      expect(
        DriverApplicationReviewService(
          auth: _Auth(),
          invoker: _Invoker(value),
        ).findForAuthenticatedUser(),
        throwsFormatException,
      );
    }
  });

  test('seven documents remain canonical and safe', () async {
    final value = (await DriverApplicationReviewService(
      auth: _Auth(),
      invoker: _Invoker(response()),
    ).findForAuthenticatedUser())!;
    expect(value.documents, hasLength(7));
    expect(
      value.documents.map((item) => item.type),
      DriverApplicationDocumentType.values,
    );
    expect(value.documents.first.reuploadReason?.label, 'Belge okunamıyor.');
    expect(value.toString(), isNot(contains('unreadable_document')));
  });

  final reasonLabels = {
    'unreadable_document': 'Belge okunamıyor.',
    'incomplete_document': 'Belge eksik.',
    'expired_document': 'Belgenin geçerlilik süresi dolmuş.',
    'information_mismatch':
        'Belgedeki bilgiler başvuru bilgileriyle eşleşmiyor.',
    'wrong_document': 'Yanlış belge yüklenmiş.',
    'unsupported_document': 'Belge formatı veya türü kabul edilmiyor.',
  };
  for (final entry in reasonLabels.entries) {
    test('${entry.key} güvenli Türkçe label üretir', () async {
      final value = await DriverApplicationReviewService(
        auth: _Auth(),
        invoker: _Invoker(response(firstReason: entry.key)),
      ).findForAuthenticatedUser();
      expect(value!.documents.first.reuploadReason?.label, entry.value);
    });
  }

  test('unknown document reason raw olarak geçmez', () {
    expect(
      DriverApplicationReviewService(
        auth: _Auth(),
        invoker: _Invoker(response(firstReason: 'raw-reason')),
      ).findForAuthenticatedUser(),
      throwsFormatException,
    );
  });

  test('not found maps to no application', () async {
    final value = await DriverApplicationReviewService(
      auth: _Auth(),
      invoker: _ErrorInvoker(
        const DriverApplicationReviewException(
          code: 'not-found',
          reason: 'driver_application_not_found',
        ),
      ),
    ).findForAuthenticatedUser();
    expect(value, isNull);
  });

  test('resubmit exact callable and payload uses current version', () async {
    final invoker = _Invoker({
      'status': 'pendingReview',
      'submissionVersion': 3,
    });
    final version = await DriverApplicationReviewService(
      auth: _Auth(),
      invoker: invoker,
    ).resubmit(expectedSubmissionVersion: 2, requestId: 'request_123456789');
    expect(version, 3);
    expect(invoker.name, 'resubmitDriverApplicationDocuments');
    expect(invoker.payload, {
      'expectedSubmissionVersion': 2,
      'requestId': 'request_123456789',
    });
  });

  test('invalid request id and response fail before unsafe use', () {
    expect(
      DriverApplicationReviewService(
        auth: _Auth(),
        invoker: _Invoker({}),
      ).resubmit(expectedSubmissionVersion: 2, requestId: 'short'),
      throwsFormatException,
    );
  });
}

class _Auth implements DriverApplicationReviewAuthSession {
  @override
  Future<void> requireAuthenticatedUser() async {}
}

class _Invoker implements DriverApplicationReviewCallableInvoker {
  _Invoker(this.response);
  final Object? response;
  String? name;
  Map<String, Object?> payload = {};
  @override
  Future<Object?> call(String functionName, Map<String, Object?> value) async {
    name = functionName;
    payload = value;
    return response;
  }
}

class _ErrorInvoker implements DriverApplicationReviewCallableInvoker {
  _ErrorInvoker(this.error);
  final Object error;
  @override
  Future<Object?> call(String name, Map<String, Object?> payload) async =>
      throw error;
}
