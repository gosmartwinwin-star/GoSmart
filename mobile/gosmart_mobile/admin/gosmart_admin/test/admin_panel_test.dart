import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_admin/application/ports.dart';
import 'package:gosmart_admin/controllers/admin_auth_controller.dart';
import 'package:gosmart_admin/controllers/driver_application_review_actions_controller.dart';
import 'package:gosmart_admin/controllers/driver_applications_controller.dart';
import 'package:gosmart_admin/core/admin_exceptions.dart';
import 'package:gosmart_admin/core/formatting.dart';
import 'package:gosmart_admin/domain/admin_session.dart';
import 'package:gosmart_admin/domain/driver_application.dart';
import 'package:gosmart_admin/screens/admin_login_screen.dart';
import 'package:gosmart_admin/screens/driver_application_details_screen.dart';
import 'package:gosmart_admin/screens/driver_applications_screen.dart';
import 'package:gosmart_admin/services/driver_application_admin_read_service.dart';
import 'package:gosmart_admin/services/driver_application_admin_review_service.dart';
import 'package:gosmart_admin/services/driver_application_review_events_service.dart';

void main() {
  group('auth domain and controller', () {
    test('empty UID is rejected', () {
      expect(
        () =>
            AdminSession(userId: ' ', email: null, hasGoSmartAdminClaim: true),
        throwsArgumentError,
      );
    });
    test('sign in forwards credentials and stores no password', () async {
      final gateway = FakeAuthGateway();
      final controller = AdminAuthController(gateway);
      expect(
        await controller.signIn('admin@example.test', 'temporary'),
        isTrue,
      );
      expect(gateway.signInCalls, 1);
      expect(controller.session?.hasGoSmartAdminClaim, isTrue);
      expect(controller.toString(), isNot(contains('temporary')));
    });
    test('false claim signs out and returns safe message', () async {
      final gateway = FakeAuthGateway(claim: false);
      final controller = AdminAuthController(gateway);
      expect(await controller.signIn('a@b.test', 'temporary'), isFalse);
      expect(gateway.signOutCalls, 1);
      expect(controller.errorMessage, contains('yetkisi'));
    });
    test('second concurrent sign in is blocked', () async {
      final gateway = FakeAuthGateway(wait: true);
      final controller = AdminAuthController(gateway);
      final first = controller.signIn('a@b.test', 'temporary');
      expect(await controller.signIn('a@b.test', 'temporary'), isFalse);
      gateway.complete();
      expect(await first, isTrue);
      expect(gateway.signInCalls, 1);
    });
    test('safe auth messages never expose raw errors', () {
      expect(
        adminAuthMessage(
          const AdminAuthenticationException('invalid_credentials'),
        ),
        'E-posta veya parola doğrulanamadı.',
      );
      expect(adminAuthMessage(Exception('raw secret')), isNot(contains('raw')));
    });
  });

  group('list and details service', () {
    test('default list payload has no sensitive keys', () async {
      final invoker = FakeInvoker(listResponse());
      final page = await DriverApplicationAdminReadService(
        invoker,
      ).list(status: DriverApplicationReviewStatus.pendingReview);
      expect(page.items, hasLength(1));
      expect(invoker.payload, {'status': 'pendingReview', 'pageSize': 20});
      for (final key in ['admin', 'uid', 'offset', 'documentSetId']) {
        expect(invoker.payload, isNot(contains(key)));
      }
      expect(page.items.single.submittedAt.isUtc, isTrue);
    });
    test('cursor is serialized with exact fields', () async {
      final invoker = FakeInvoker(listResponse());
      await DriverApplicationAdminReadService(invoker).list(
        status: DriverApplicationReviewStatus.approved,
        cursor: DriverApplicationReviewCursor(
          submittedAt: DateTime.fromMillisecondsSinceEpoch(12, isUtc: true),
          applicationId: 'app-1',
        ),
      );
      expect(invoker.payload['cursor'], {
        'submittedAtMillis': 12,
        'applicationId': 'app-1',
      });
    });
    test('bool, double and negative millis are rejected', () async {
      for (final bad in [true, 1.2, -1]) {
        final response = listResponse();
        (response['items']! as List).first['submittedAtMillis'] = bad;
        expect(
          DriverApplicationAdminReadService(
            FakeInvoker(response),
          ).list(status: DriverApplicationReviewStatus.pendingReview),
          throwsFormatException,
        );
      }
    });
    test('unknown enums and empty IDs are rejected', () async {
      final response = listResponse();
      (response['items']! as List).first['status'] = 'unknown';
      expect(
        DriverApplicationAdminReadService(
          FakeInvoker(response),
        ).list(status: DriverApplicationReviewStatus.pendingReview),
        throwsFormatException,
      );
    });
    for (final mutation in <void Function(Map<String, Object?>)>[
      (item) => item['workType'] = 'unknown',
      (item) => item['registrationOwnerType'] = 'unknown',
      (item) => item['applicationId'] = '',
      (item) => item['submissionVersion'] = 0,
      (item) => item['vehicleModelYear'] = 2024.0,
      (item) => item['updatedAtMillis'] = -1,
    ]) {
      test('invalid list field is rejected', () async {
        final response = listResponse();
        mutation((response['items']! as List).first);
        expect(
          DriverApplicationAdminReadService(
            FakeInvoker(response),
          ).list(status: DriverApplicationReviewStatus.pendingReview),
          throwsFormatException,
        );
      });
    }
    test('sensitive extra list fields are discarded', () async {
      final response = listResponse();
      final item = (response['items']! as List).first as Map<String, Object?>;
      item['fullName'] = 'Gizli';
      item['vehiclePlate'] = 'Gizli';
      item['documentSetId'] = 'Gizli';
      final summary = (await DriverApplicationAdminReadService(
        FakeInvoker(response),
      ).list(status: DriverApplicationReviewStatus.pendingReview)).items.single;
      expect(summary.toString(), isNot(contains('Gizli')));
    });
    test('malformed cursor is rejected', () async {
      final response = listResponse()
        ..['nextCursor'] = {
          'submittedAtMillis': true,
          'applicationId': 'app-1',
        };
      expect(
        DriverApplicationAdminReadService(
          FakeInvoker(response),
        ).list(status: DriverApplicationReviewStatus.pendingReview),
        throwsFormatException,
      );
    });
    test('details payload contains only applicationId', () async {
      final invoker = FakeInvoker(detailsResponse());
      final details = await DriverApplicationAdminReadService(
        invoker,
      ).getDetails(applicationId: 'app-1');
      expect(invoker.payload, {'applicationId': 'app-1'});
      expect(details.documents, hasLength(7));
      expect(details.reviewContext.toString(), isNot(contains('set-secret')));
      expect(details.application.submittedAt.isUtc, isTrue);
    });
    test('missing and duplicate documents are rejected', () async {
      final missing = detailsResponse();
      (missing['documents']! as List).removeLast();
      expect(
        DriverApplicationAdminReadService(
          FakeInvoker(missing),
        ).getDetails(applicationId: 'app-1'),
        throwsFormatException,
      );
      final duplicate = detailsResponse();
      (duplicate['documents']! as List)[1]['documentType'] =
          (duplicate['documents']! as List)[0]['documentType'];
      expect(
        DriverApplicationAdminReadService(
          FakeInvoker(duplicate),
        ).getDetails(applicationId: 'app-1'),
        throwsFormatException,
      );
    });
    for (final badSize in <Object>[true, 1.2, 0, -1]) {
      test('invalid document size is rejected', () async {
        final response = detailsResponse();
        (response['documents']! as List).first['sizeBytes'] = badSize;
        expect(
          DriverApplicationAdminReadService(
            FakeInvoker(response),
          ).getDetails(applicationId: 'app-1'),
          throwsFormatException,
        );
      });
    }
    test('unknown document type and status are rejected', () async {
      for (final field in ['documentType', 'reviewStatus']) {
        final response = detailsResponse();
        (response['documents']! as List).first[field] = 'unknown';
        expect(
          DriverApplicationAdminReadService(
            FakeInvoker(response),
          ).getDetails(applicationId: 'app-1'),
          throwsFormatException,
        );
      }
    });
    test('invalid context and raw timestamp are rejected', () async {
      final invalidContext = detailsResponse();
      (invalidContext['reviewContext']! as Map)['submissionVersion'] = 0;
      expect(
        DriverApplicationAdminReadService(
          FakeInvoker(invalidContext),
        ).getDetails(applicationId: 'app-1'),
        throwsFormatException,
      );
      final invalidTime = detailsResponse();
      (invalidTime['application']! as Map)['submittedAtMillis'] = Object();
      expect(
        DriverApplicationAdminReadService(
          FakeInvoker(invalidTime),
        ).getDetails(applicationId: 'app-1'),
        throwsFormatException,
      );
    });
    test('storage and reviewer response fields never enter models', () async {
      final response = detailsResponse();
      (response['documents']! as List).first.addAll({
        'storagePath': 'secret-path',
        'reviewedByAdminUid': 'secret-uid',
        'storageGeneration': 'secret-generation',
      });
      final details = await DriverApplicationAdminReadService(
        FakeInvoker(response),
      ).getDetails(applicationId: 'app-1');
      expect(details.documents.first.toString(), isNot(contains('secret')));
    });
  });

  group('controllers', () {
    test('list controller loads, deduplicates and clears', () async {
      final gateway = FakeReadGateway();
      final controller = DriverApplicationsController(gateway);
      await controller.loadInitial();
      expect(controller.items, hasLength(1));
      await controller.loadMore();
      expect(controller.items, hasLength(1));
      controller.clearSensitiveState();
      expect(controller.items, isEmpty);
    });
    test('details controller clears sensitive state on error', () async {
      final gateway = FakeReadGateway(failDetails: true);
      final controller = DriverApplicationDetailsController(gateway);
      await controller.load('app-1');
      expect(controller.details, isNull);
      expect(controller.errorMessage, isNotNull);
    });
    test('status change clears old page and reloads', () async {
      final gateway = FakeReadGateway();
      final controller = DriverApplicationsController(gateway);
      await controller.loadInitial();
      await controller.changeStatus(DriverApplicationReviewStatus.approved);
      expect(controller.selectedStatus, DriverApplicationReviewStatus.approved);
      expect(gateway.listCalls, 2);
    });
    test('load more does nothing without cursor', () async {
      final gateway = FakeReadGateway(noCursor: true);
      final controller = DriverApplicationsController(gateway);
      await controller.loadInitial();
      await controller.loadMore();
      expect(gateway.listCalls, 1);
    });
    test('details keeps route identity and fresh mutation context', () async {
      final gateway = SequencedReadGateway([detailsResponse()]);
      final controller = DriverApplicationDetailsController(gateway);

      await controller.load('test-application');

      expect(controller.currentApplicationId, 'test-application');
      expect(controller.details, isNotNull);
      expect(controller.hasFreshMutationContext, isTrue);
    });
    test(
      'context invalidation keeps route identity and visible details',
      () async {
        final controller = DriverApplicationDetailsController(
          SequencedReadGateway([detailsResponse()]),
        );
        await controller.load('test-application');

        controller.invalidateReviewContext();

        expect(controller.currentApplicationId, 'test-application');
        expect(controller.details, isNotNull);
        expect(controller.hasFreshMutationContext, isFalse);
      },
    );
    test('refresh uses current id and replaces details', () async {
      final gateway = SequencedReadGateway([
        detailsResponse(),
        detailsResponse(status: 'approved'),
      ]);
      final controller = DriverApplicationDetailsController(gateway);
      await controller.load('test-application');

      await controller.refresh();

      expect(gateway.detailIds, ['test-application', 'test-application']);
      expect(
        controller.details!.application.status,
        DriverApplicationReviewStatus.approved,
      );
      expect(controller.hasFreshMutationContext, isTrue);
    });
    test(
      'refresh retains content, marks refreshing and locks context',
      () async {
        final gateway = SequencedReadGateway([detailsResponse()]);
        final controller = DriverApplicationDetailsController(gateway);
        await controller.load('test-application');
        gateway.waitForNextDetails = true;

        final refresh = controller.refresh();

        expect(controller.isRefreshing, isTrue);
        expect(controller.details, isNotNull);
        expect(controller.hasFreshMutationContext, isFalse);
        gateway.completeNextDetails(detailsResponse(status: 'approved'));
        await refresh;
        expect(controller.isRefreshing, isFalse);
        expect(controller.hasFreshMutationContext, isTrue);
      },
    );
    test(
      'refresh failure retains route and disables future mutation',
      () async {
        final gateway = SequencedReadGateway([detailsResponse()]);
        final controller = DriverApplicationDetailsController(gateway);
        await controller.load('test-application');
        gateway.nextDetailsError = const AdminPanelException('unavailable');

        await controller.refresh();

        expect(controller.currentApplicationId, 'test-application');
        expect(controller.details, isNotNull);
        expect(controller.hasFreshMutationContext, isFalse);
        expect(controller.errorMessage, contains('İşlem kaydedildi'));
      },
    );
    test('retry reads same route id and restores fresh context', () async {
      final gateway = SequencedReadGateway([detailsResponse()]);
      final controller = DriverApplicationDetailsController(gateway);
      await controller.load('test-application');
      gateway.nextDetailsError = const AdminPanelException('unavailable');
      await controller.refresh();

      await controller.refresh();

      expect(gateway.detailIds, everyElement('test-application'));
      expect(controller.errorMessage, isNull);
      expect(controller.hasFreshMutationContext, isTrue);
    });
    test('full clear removes route identity and sensitive details', () async {
      final controller = DriverApplicationDetailsController(
        SequencedReadGateway([detailsResponse()]),
      );
      await controller.load('test-application');

      controller.clearSensitiveState();

      expect(controller.currentApplicationId, isNull);
      expect(controller.details, isNull);
      expect(controller.hasFreshMutationContext, isFalse);
    });
    test(
      'session expiry fully clears details and invokes auth callback',
      () async {
        final gateway = SequencedReadGateway([detailsResponse()]);
        var authFailures = 0;
        final controller = DriverApplicationDetailsController(
          gateway,
          handleAuthFailure: () async => authFailures++,
        );
        await controller.load('test-application');
        gateway.nextDetailsError = const AdminPanelException(
          'unauthenticated',
          reason: 'session_expired',
        );

        await controller.refresh();

        expect(authFailures, 1);
        expect(controller.currentApplicationId, isNull);
        expect(controller.details, isNull);
        expect(controller.hasFreshMutationContext, isFalse);
      },
    );
    test(
      'loading a new id clears the previous application immediately',
      () async {
        final gateway = SequencedReadGateway([detailsResponse()]);
        final controller = DriverApplicationDetailsController(gateway);
        await controller.load('first-application');
        gateway.waitForNextDetails = true;

        final load = controller.load('second-application');

        expect(controller.currentApplicationId, 'second-application');
        expect(controller.details, isNull);
        gateway.completeNextDetails(detailsResponse());
        await load;
      },
    );
  });

  group('review service security', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1000000, isUtc: true);
    DriverApplicationReviewContext context() => DriverApplicationReviewContext(
      submissionVersion: 2,
      documentSetId: 'set-fixture',
    );
    Map<String, Object?> previewResponse({
      Object? url,
      Object? expiresAt,
      Object? contentType,
      Object? size,
    }) => {
      'url': url ?? 'https://example.invalid/temporary-document',
      'expiresAtMillis':
          expiresAt ??
          now.add(const Duration(minutes: 3)).millisecondsSinceEpoch,
      'contentType': contentType ?? 'image/jpeg',
      'sizeBytes': size ?? 100,
      'storagePath': 'ignored',
      'reviewerUid': 'ignored',
    };

    test('preview uses exact callable and minimal payload', () async {
      final invoker = FakeInvoker(previewResponse());
      final preview =
          await DriverApplicationAdminReviewService(
            invoker,
            now: () => now,
          ).createDocumentPreview(
            applicationId: 'app-1',
            reviewContext: context(),
            documentType: DriverDocumentType.driverLicenseFront,
          );
      expect(invoker.functionName, 'createDriverApplicationDocumentReviewUrl');
      expect(invoker.payload, {
        'applicationId': 'app-1',
        'submissionVersion': 2,
        'documentSetId': 'set-fixture',
        'documentType': 'driverLicenseFront',
      });
      for (final key in ['admin', 'uid', 'storagePath', 'url']) {
        expect(invoker.payload, isNot(contains(key)));
      }
      expect(preview.expiresAt.isUtc, isTrue);
      expect(preview.toString(), contains('[REDACTED]'));
      expect(preview.toString(), isNot(contains('example.invalid')));
    });
    for (final badUrl in [
      '',
      'http://example.invalid/a',
      'javascript:alert(1)',
      'data:text/plain,a',
      'file:///a',
      'https:///missing-host',
      'https://example.invalid/a#fragment',
    ]) {
      test('unsafe preview URL is rejected', () async {
        expect(
          DriverApplicationAdminReviewService(
            FakeInvoker(previewResponse(url: badUrl)),
            now: () => now,
          ).createDocumentPreview(
            applicationId: 'app-1',
            reviewContext: context(),
            documentType: DriverDocumentType.driverLicenseFront,
          ),
          throwsFormatException,
        );
      });
    }
    for (final badExpiry in <Object>[
      true,
      1.2,
      -1,
      now.add(const Duration(seconds: 10)).millisecondsSinceEpoch,
    ]) {
      test('invalid or near-expiry preview is rejected', () async {
        expect(
          DriverApplicationAdminReviewService(
            FakeInvoker(previewResponse(expiresAt: badExpiry)),
            now: () => now,
          ).createDocumentPreview(
            applicationId: 'app-1',
            reviewContext: context(),
            documentType: DriverDocumentType.driverLicenseFront,
          ),
          throwsFormatException,
        );
      });
    }
    for (final badType in [
      'text/html',
      'image/gif',
      'application/octet-stream',
    ]) {
      test('unknown preview content type is rejected', () async {
        expect(
          DriverApplicationAdminReviewService(
            FakeInvoker(previewResponse(contentType: badType)),
            now: () => now,
          ).createDocumentPreview(
            applicationId: 'app-1',
            reviewContext: context(),
            documentType: DriverDocumentType.driverLicenseFront,
          ),
          throwsFormatException,
        );
      });
    }
    for (final badSize in <Object>[true, 1.2, 0, -1]) {
      test('invalid preview size is rejected', () async {
        expect(
          DriverApplicationAdminReviewService(
            FakeInvoker(previewResponse(size: badSize)),
            now: () => now,
          ).createDocumentPreview(
            applicationId: 'app-1',
            reviewContext: context(),
            documentType: DriverDocumentType.driverLicenseFront,
          ),
          throwsFormatException,
        );
      });
    }
    test('document approve and reupload payloads are exact', () async {
      final approve = FakeInvoker({
        'applicationStatus': 'pendingReview',
        'documentStatus': 'approved',
        'reviewedAtMillis': 1,
      });
      await DriverApplicationAdminReviewService(approve).approveDocument(
        applicationId: 'app-1',
        reviewContext: context(),
        documentType: DriverDocumentType.identityCardFront,
      );
      expect(approve.functionName, 'reviewDriverApplicationDocument');
      expect(approve.payload['decision'], 'approve');
      expect(approve.payload, isNot(contains('reasonCode')));
      final reupload = FakeInvoker({
        'applicationStatus': 'rejected',
        'documentStatus': 'reuploadRequired',
        'reviewedAtMillis': 1,
      });
      await DriverApplicationAdminReviewService(
        reupload,
      ).requestDocumentReupload(
        applicationId: 'app-1',
        reviewContext: context(),
        documentType: DriverDocumentType.identityCardFront,
        reason: DriverDocumentReuploadReason.unreadableDocument,
      );
      expect(reupload.payload['decision'], 'requireReupload');
      expect(reupload.payload['reasonCode'], 'unreadable_document');
      expect(reupload.payload.length, 6);
    });
    test('application approve and reject payloads are exact', () async {
      final approve = FakeInvoker({
        'status': 'approved',
        'reviewedAtMillis': 1,
        'driverProfileCreated': true,
      });
      await DriverApplicationAdminReviewService(
        approve,
      ).approveApplication(applicationId: 'app-1', reviewContext: context());
      expect(approve.functionName, 'reviewDriverApplication');
      expect(approve.payload['decision'], 'approve');
      expect(approve.payload, isNot(contains('rejectionReasonCode')));
      final reject = FakeInvoker({
        'status': 'rejected',
        'reviewedAtMillis': 1,
        'driverProfileCreated': false,
      });
      await DriverApplicationAdminReviewService(reject).rejectApplication(
        applicationId: 'app-1',
        reviewContext: context(),
        reason: DriverApplicationRejectionReason.vehicleInformationInvalid,
      );
      expect(reject.payload['decision'], 'reject');
      expect(
        reject.payload['rejectionReasonCode'],
        'vehicle_information_invalid',
      );
      for (final key in ['fullName', 'vehicle', 'driverProfile', 'admin']) {
        expect(reject.payload, isNot(contains(key)));
      }
    });
    test('malformed mutation responses are rejected', () async {
      expect(
        DriverApplicationAdminReviewService(FakeInvoker({})).approveDocument(
          applicationId: 'app-1',
          reviewContext: context(),
          documentType: DriverDocumentType.driverLicenseBack,
        ),
        throwsFormatException,
      );
      expect(
        DriverApplicationAdminReviewService(
          FakeInvoker({}),
        ).approveApplication(applicationId: 'app-1', reviewContext: context()),
        throwsFormatException,
      );
    });
  });

  group('review actions controller', () {
    test('preview is stored briefly and cleared on close', () async {
      final gateway = FakeReviewGateway();
      final controller = actionController(gateway);
      await controller.openDocumentPreview(
        applicationId: 'app-1',
        reviewContext: reviewContext(),
        documentType: DriverDocumentType.criminalRecord,
      );
      expect(controller.activePreview, isNotNull);
      controller.closeDocumentPreview();
      expect(controller.activePreview, isNull);
      expect(controller.toString(), isNot(contains('example.invalid')));
    });
    test('document success clears preview and refreshes both views', () async {
      final gateway = FakeReviewGateway();
      var detailsRefresh = 0;
      var listRefresh = 0;
      var timelineRefresh = 0;
      var invalidations = 0;
      var fullClears = 0;
      final controller = actionController(
        gateway,
        refreshDetails: () async => detailsRefresh++,
        refreshList: () async => listRefresh++,
        refreshTimeline: () async => timelineRefresh++,
        invalidateReviewContext: () => invalidations++,
        clearDetails: () => fullClears++,
      );
      await controller.openDocumentPreview(
        applicationId: 'app-1',
        reviewContext: reviewContext(),
        documentType: DriverDocumentType.criminalRecord,
      );
      expect(
        await controller.approveDocument(
          applicationId: 'app-1',
          reviewContext: reviewContext(),
          documentType: DriverDocumentType.criminalRecord,
        ),
        isTrue,
      );
      expect(controller.activePreview, isNull);
      expect(detailsRefresh, 1);
      expect(listRefresh, 1);
      expect(timelineRefresh, 1);
      expect(invalidations, 1);
      expect(fullClears, 0);
      expect(gateway.approveCalls, 1);
    });
    test('reupload and reject reasons reach gateway', () async {
      final gateway = FakeReviewGateway();
      final controller = actionController(gateway);
      await controller.requestDocumentReupload(
        applicationId: 'app-1',
        reviewContext: reviewContext(),
        documentType: DriverDocumentType.vehicleRegistration,
        reason: DriverDocumentReuploadReason.expiredDocument,
      );
      await controller.rejectApplication(
        applicationId: 'app-1',
        reviewContext: reviewContext(),
        reason: DriverApplicationRejectionReason.personalInformationInvalid,
      );
      expect(
        gateway.documentReason,
        DriverDocumentReuploadReason.expiredDocument,
      );
      expect(
        gateway.applicationReason,
        DriverApplicationRejectionReason.personalInformationInvalid,
      );
    });
    test('stale mutation is not retried and reloads current state', () async {
      final gateway = FakeReviewGateway(
        error: const AdminPanelException(
          'failed-precondition',
          reason: 'stale_driver_application_review',
        ),
      );
      var refreshes = 0;
      var invalidations = 0;
      final controller = actionController(
        gateway,
        refreshDetails: () async => refreshes++,
        refreshList: () async => refreshes++,
        refreshTimeline: () async => refreshes++,
        invalidateReviewContext: () => invalidations++,
      );
      expect(
        await controller.approveApplication(
          applicationId: 'app-1',
          reviewContext: reviewContext(),
        ),
        isFalse,
      );
      expect(gateway.applicationApproveCalls, 1);
      expect(refreshes, 3);
      expect(invalidations, 1);
      expect(controller.actionErrorMessage, contains('yeniden yükleniyor'));
    });
    test('auth failure clears state and invokes sign out callback', () async {
      final gateway = FakeReviewGateway(
        error: const AdminPanelException(
          'permission-denied',
          reason: 'admin_access_required',
        ),
      );
      var authFailures = 0;
      var fullClears = 0;
      final controller = actionController(
        gateway,
        authFailure: () async => authFailures++,
        clearDetails: () => fullClears++,
      );
      await controller.approveApplication(
        applicationId: 'app-1',
        reviewContext: reviewContext(),
      );
      expect(authFailures, 1);
      expect(fullClears, 1);
      expect(controller.activePreview, isNull);
    });
    for (final actionName in [
      'approve document',
      'request document reupload',
      'approve application',
      'reject application',
    ]) {
      test(
        '$actionName invalidates context and refreshes all read models',
        () async {
          final gateway = FakeReviewGateway();
          var invalidations = 0;
          var detailsRefreshes = 0;
          var listRefreshes = 0;
          var timelineRefreshes = 0;
          var fullClears = 0;
          final controller = actionController(
            gateway,
            invalidateReviewContext: () => invalidations++,
            clearDetails: () => fullClears++,
            refreshDetails: () async => detailsRefreshes++,
            refreshList: () async => listRefreshes++,
            refreshTimeline: () async => timelineRefreshes++,
          );

          switch (actionName) {
            case 'approve document':
              await controller.approveDocument(
                applicationId: 'test-application',
                reviewContext: reviewContext(),
                documentType: DriverDocumentType.criminalRecord,
              );
              break;
            case 'request document reupload':
              await controller.requestDocumentReupload(
                applicationId: 'test-application',
                reviewContext: reviewContext(),
                documentType: DriverDocumentType.criminalRecord,
                reason: DriverDocumentReuploadReason.unreadableDocument,
              );
              break;
            case 'approve application':
              await controller.approveApplication(
                applicationId: 'test-application',
                reviewContext: reviewContext(),
              );
              break;
            case 'reject application':
              await controller.rejectApplication(
                applicationId: 'test-application',
                reviewContext: reviewContext(),
                reason: DriverApplicationRejectionReason
                    .documentInformationMismatch,
              );
              break;
          }

          expect(invalidations, 1);
          expect(fullClears, 0);
          expect(detailsRefreshes, 1);
          expect(listRefreshes, 1);
          expect(timelineRefreshes, 1);
        },
      );
    }
  });

  group('safe presentation helpers', () {
    test('file sizes use binary units', () {
      expect(formatFileSize(10), '10 B');
      expect(formatFileSize(1024), '1.0 KiB');
      expect(formatFileSize(1024 * 1024), '1.0 MiB');
    });
    test('unknown rejection reason never exposes raw code', () {
      expect(
        rejectionReasonLabel('raw_internal_code'),
        'İnceleme açıklaması mevcut.',
      );
    });
    test('safe panel error never exposes raw exception', () {
      expect(
        adminPanelMessage(Exception('raw secret')),
        isNot(contains('raw')),
      );
    });
  });

  testWidgets('login has required safe UI and clears password', (tester) async {
    final controller = AdminAuthController(FakeAuthGateway(fail: true));
    await tester.pumpWidget(
      MaterialApp(home: AdminLoginScreen(controller: controller)),
    );
    expect(find.text('GoSmart Yönetim'), findsOneWidget);
    expect(find.text('Sürücü Başvuru İnceleme Paneli'), findsOneWidget);
    expect(find.text('Beni hatırla'), findsNothing);
    expect(find.text('Kayıt ol'), findsNothing);
    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.test');
    await tester.enterText(find.byType(TextFormField).at(1), 'temporary');
    await tester.tap(find.text('Giriş Yap'));
    await tester.pumpAndSettle();
    expect(
      find.text('Giriş şu anda tamamlanamadı. Lütfen tekrar deneyin.'),
      findsOneWidget,
    );
    final password = tester.widget<TextFormField>(
      find.byType(TextFormField).at(1),
    );
    expect(password.controller?.text, isEmpty);
  });
  testWidgets('login fits a 360x640 viewport', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AdminLoginScreen(
          controller: AdminAuthController(FakeAuthGateway()),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('list shows safe columns and excludes personal data', (
    tester,
  ) async {
    final gateway = DriverApplicationAdminReadService(
      FakeInvoker(listResponse()),
    );
    final controller = DriverApplicationsController(gateway);
    await controller.loadInitial();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverApplicationsScreen(
            controller: controller,
            gateway: gateway,
            reviews: FakeReviewGateway(),
            reviewEvents: DriverApplicationReviewEventsService(
              FakeInvoker(timelineResponse()),
            ),
            auth: AdminAuthController(FakeAuthGateway()),
          ),
        ),
      ),
    );
    expect(find.text('Sürücü Başvuruları'), findsOneWidget);
    for (final status in DriverApplicationReviewStatus.values) {
      expect(find.text(status.label), findsWidgets);
    }
    expect(find.text('İncele'), findsOneWidget);
    expect(find.text('Ad Soyad'), findsNothing);
    expect(find.text('00 XX 000'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('details shows safe sections and manual review actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = DriverApplicationAdminReadService(
      FakeInvoker(detailsResponse()),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DriverApplicationDetailsScreen(
          applicationId: 'app-1',
          gateway: gateway,
          reviews: FakeReviewGateway(),
          reviewEvents: DriverApplicationReviewEventsService(
            FakeInvoker(timelineResponse()),
          ),
          refreshList: () async {},
          auth: AdminAuthController(FakeAuthGateway()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final heading in [
      'Başvuru Özeti',
      'Kişisel Bilgiler',
      'Çalışma Bilgileri',
      'Araç Bilgileri',
      'Beyanlar',
      'Belgeler',
    ]) {
      expect(find.text(heading), findsOneWidget);
    }
    expect(find.textContaining('set-secret'), findsNothing);
    expect(find.textContaining('storagePath'), findsNothing);
    expect(find.text('Görüntüle'), findsNWidgets(7));
    expect(find.text('Başvuruyu Onayla'), findsOneWidget);
    expect(find.text('Başvuruyu Reddet'), findsOneWidget);
    final approve = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Başvuruyu Onayla'),
    );
    expect(approve.onPressed, isNull);
  });
  testWidgets('mutation refresh keeps details visible and locks actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = SequencedReadGateway([detailsResponse()]);
    await tester.pumpWidget(
      MaterialApp(
        home: DriverApplicationDetailsScreen(
          applicationId: 'test-application',
          gateway: gateway,
          reviews: FakeReviewGateway(),
          reviewEvents: DriverApplicationReviewEventsService(
            FakeInvoker(timelineResponse()),
          ),
          refreshList: () async {},
          auth: AdminAuthController(FakeAuthGateway()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    gateway.waitForNextDetails = true;

    await tester.tap(find.widgetWithText(FilledButton, 'Onayla').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Belgeyi Onayla'));
    await tester.pump();

    expect(find.text('Güncel bilgiler yükleniyor...'), findsOneWidget);
    expect(find.text('Başvuru Özeti'), findsOneWidget);
    final documentApprove = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Onayla').first,
    );
    expect(documentApprove.onPressed, isNull);
    gateway.completeNextDetails(detailsResponse(status: 'approved'));
    await tester.pumpAndSettle();
    expect(find.text('Güncel bilgiler yükleniyor...'), findsNothing);
    expect(find.text('Başvuru Özeti'), findsOneWidget);
  });
  testWidgets('refresh failure keeps detail shell and offers read retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = SequencedReadGateway([detailsResponse()]);
    await tester.pumpWidget(
      MaterialApp(
        home: DriverApplicationDetailsScreen(
          applicationId: 'test-application',
          gateway: gateway,
          reviews: FakeReviewGateway(),
          reviewEvents: DriverApplicationReviewEventsService(
            FakeInvoker(timelineResponse()),
          ),
          refreshList: () async {},
          auth: AdminAuthController(FakeAuthGateway()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    gateway.nextDetailsError = const AdminPanelException('unavailable');

    await tester.tap(find.widgetWithText(FilledButton, 'Onayla').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Belgeyi Onayla'));
    await tester.pumpAndSettle();

    expect(find.text('Başvuru Özeti'), findsOneWidget);
    expect(
      find.text('İşlem kaydedildi ancak güncel başvuru bilgileri yüklenemedi.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Tekrar Yükle'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Onayla').first,
          )
          .onPressed,
      isNull,
    );
  });
  testWidgets('approve application requires exact ONAYLA confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ApproveDriverApplicationDialog())),
    );
    FilledButton submit() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Başvuruyu Onayla'),
    );
    expect(submit().onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'onayla');
    await tester.pump();
    expect(submit().onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'ONAYLA');
    await tester.pump();
    expect(submit().onPressed, isNotNull);
  });
  testWidgets('reupload dialog has no default or free-text reason', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RequestDocumentReuploadDialog(
            documentType: DriverDocumentType.driverLicenseFront,
          ),
        ),
      ),
    );
    final submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Yeniden Yükleme İste'),
    );
    expect(submit.onPressed, isNull);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('unreadable_document'), findsNothing);
  });
  testWidgets('reject dialog requires reason and exact REDDET', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: RejectDriverApplicationDialog())),
    );
    FilledButton submit() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Başvuruyu Reddet'),
    );
    expect(submit().onPressed, isNull);
    await tester.tap(
      find.byType(DropdownButtonFormField<DriverApplicationRejectionReason>),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .text(
            DriverApplicationRejectionReason.personalInformationInvalid.label,
          )
          .last,
    );
    await tester.pumpAndSettle();
    expect(submit().onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'REDDET');
    await tester.pump();
    expect(submit().onPressed, isNotNull);
    expect(find.text('personal_information_invalid'), findsNothing);
  });
  testWidgets('preview dialog never renders URL or review context as text', (
    tester,
  ) async {
    final controller = actionController(FakeReviewGateway());
    await controller.openDocumentPreview(
      applicationId: 'app-1',
      reviewContext: reviewContext(),
      documentType: DriverDocumentType.driverLicenseFront,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DriverApplicationDocumentPreviewDialog(
          controller: controller,
          documentType: DriverDocumentType.driverLicenseFront,
        ),
      ),
    );
    expect(find.textContaining('example.invalid'), findsNothing);
    expect(find.textContaining('set-fixture'), findsNothing);
    expect(
      find.text('Belge önizleme test ortamında gösterilmiyor.'),
      findsOneWidget,
    );
    controller.dispose();
  });
}

final class FakeAuthGateway implements AdminAuthGateway {
  FakeAuthGateway({this.claim = true, this.fail = false, this.wait = false});
  final bool claim;
  final bool fail;
  final bool wait;
  int signInCalls = 0;
  int signOutCalls = 0;
  final _waiter = Completer<void>();
  void complete() {
    if (!_waiter.isCompleted) _waiter.complete();
  }

  @override
  Stream<AdminSession?> authStateChanges() => const Stream.empty();
  @override
  Future<AdminSession?> refreshAndGetSession() async => null;
  @override
  Future<AdminSession> signIn({
    required String email,
    required String password,
  }) async {
    signInCalls++;
    if (wait) await _waiter.future;
    if (fail) throw Exception('raw');
    return AdminSession(
      userId: 'admin-1',
      email: email,
      hasGoSmartAdminClaim: claim,
    );
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }
}

final class FakeInvoker implements AdminCallableInvoker {
  FakeInvoker(this.response);
  final Object? response;
  Map<String, Object?> payload = {};
  String? functionName;
  @override
  Future<Object?> call({
    required String functionName,
    required Map<String, Object?> payload,
  }) async {
    this.functionName = functionName;
    this.payload = payload;
    return response;
  }
}

final class FakeReadGateway implements DriverApplicationAdminReadGateway {
  FakeReadGateway({this.failDetails = false, this.noCursor = false});
  final bool failDetails;
  final bool noCursor;
  int listCalls = 0;
  @override
  Future<DriverApplicationReviewPage> list({
    required DriverApplicationReviewStatus status,
    int pageSize = 20,
    DriverApplicationReviewCursor? cursor,
  }) async {
    listCalls++;
    return DriverApplicationReviewPage(
      items: [summary()],
      nextCursor: !noCursor && cursor == null
          ? DriverApplicationReviewCursor(
              submittedAt: _epoch,
              applicationId: 'app-1',
            )
          : null,
    );
  }

  @override
  Future<DriverApplicationReviewDetails> getDetails({
    required String applicationId,
  }) async {
    if (failDetails) throw const AdminPanelException('x');
    throw UnimplementedError();
  }
}

final class SequencedReadGateway implements DriverApplicationAdminReadGateway {
  SequencedReadGateway(this.responses);
  final List<Map<String, Object?>> responses;
  final List<String> detailIds = [];
  bool waitForNextDetails = false;
  Object? nextDetailsError;
  Completer<Map<String, Object?>>? _detailsCompleter;

  void completeNextDetails(Map<String, Object?> response) {
    _detailsCompleter?.complete(response);
  }

  @override
  Future<DriverApplicationReviewDetails> getDetails({
    required String applicationId,
  }) async {
    detailIds.add(applicationId);
    final error = nextDetailsError;
    nextDetailsError = null;
    if (error != null) throw error;
    Map<String, Object?> response;
    if (waitForNextDetails) {
      waitForNextDetails = false;
      _detailsCompleter = Completer<Map<String, Object?>>();
      response = await _detailsCompleter!.future;
    } else {
      response = responses.length > 1 ? responses.removeAt(0) : responses.first;
    }
    return DriverApplicationAdminReadService(
      FakeInvoker(response),
    ).getDetails(applicationId: applicationId);
  }

  @override
  Future<DriverApplicationReviewPage> list({
    required DriverApplicationReviewStatus status,
    int pageSize = 20,
    DriverApplicationReviewCursor? cursor,
  }) => throw UnimplementedError();
}

final class FakeReviewGateway implements DriverApplicationAdminReviewGateway {
  FakeReviewGateway({this.error});
  final Object? error;
  int previewCalls = 0;
  int approveCalls = 0;
  int applicationApproveCalls = 0;
  DriverDocumentReuploadReason? documentReason;
  DriverApplicationRejectionReason? applicationReason;
  void _throwIfNeeded() {
    final value = error;
    if (value != null) throw value;
  }

  @override
  Future<DriverApplicationDocumentPreview> createDocumentPreview({
    required String applicationId,
    required DriverApplicationReviewContext reviewContext,
    required DriverDocumentType documentType,
  }) async {
    previewCalls++;
    _throwIfNeeded();
    return DriverApplicationDocumentPreview(
      rendererUri: Uri.parse('https://example.invalid/temporary-document'),
      contentType: 'image/jpeg',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 2)),
      documentType: documentType,
      sizeBytes: 100,
    );
  }

  @override
  Future<void> approveDocument({
    required String applicationId,
    required DriverApplicationReviewContext reviewContext,
    required DriverDocumentType documentType,
  }) async {
    approveCalls++;
    _throwIfNeeded();
  }

  @override
  Future<void> requestDocumentReupload({
    required String applicationId,
    required DriverApplicationReviewContext reviewContext,
    required DriverDocumentType documentType,
    required DriverDocumentReuploadReason reason,
  }) async {
    documentReason = reason;
    _throwIfNeeded();
  }

  @override
  Future<void> approveApplication({
    required String applicationId,
    required DriverApplicationReviewContext reviewContext,
  }) async {
    applicationApproveCalls++;
    _throwIfNeeded();
  }

  @override
  Future<void> rejectApplication({
    required String applicationId,
    required DriverApplicationReviewContext reviewContext,
    required DriverApplicationRejectionReason reason,
  }) async {
    applicationReason = reason;
    _throwIfNeeded();
  }
}

DriverApplicationReviewContext reviewContext() =>
    DriverApplicationReviewContext(
      submissionVersion: 1,
      documentSetId: 'set-fixture',
    );

DriverApplicationReviewActionsController actionController(
  FakeReviewGateway gateway, {
  Future<void> Function()? refreshDetails,
  Future<void> Function()? refreshList,
  Future<void> Function()? refreshTimeline,
  void Function()? invalidateReviewContext,
  void Function()? clearDetails,
  Future<void> Function()? authFailure,
}) => DriverApplicationReviewActionsController(
  gateway: gateway,
  refreshDetails: refreshDetails ?? () async {},
  refreshList: refreshList ?? () async {},
  refreshTimeline: refreshTimeline ?? () async {},
  invalidateReviewContext: invalidateReviewContext ?? () {},
  clearDetails: clearDetails ?? () {},
  handleAuthFailure: authFailure ?? () async {},
);

final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
Map<String, Object?> timelineResponse() => {
  'items': <Object?>[],
  'nextCursor': null,
};
DriverApplicationReviewSummary summary() => DriverApplicationReviewSummary(
  applicationId: 'app-1',
  status: DriverApplicationReviewStatus.pendingReview,
  submittedAt: _epoch,
  updatedAt: _epoch,
  submissionVersion: 1,
  workType: DriverWorkType.vehicleOwner,
  vehicleBrand: 'Marka',
  vehicleModel: 'Model',
  vehicleModelYear: 2024,
  registrationOwnerType: RegistrationOwnerType.applicant,
);

Map<String, Object?> listResponse() => {
  'items': [
    {
      'applicationId': 'app-1',
      'status': 'pendingReview',
      'submittedAtMillis': 0,
      'updatedAtMillis': 1,
      'submissionVersion': 1,
      'workType': 'vehicleOwner',
      'vehicleBrand': 'Marka',
      'vehicleModel': 'Model',
      'vehicleModelYear': 2024,
      'registrationOwnerType': 'applicant',
    },
  ],
  'nextCursor': null,
};

Map<String, Object?> detailsResponse({String status = 'pendingReview'}) => {
  'reviewContext': {'submissionVersion': 1, 'documentSetId': 'set-secret'},
  'application': {
    'applicationId': 'app-1',
    'status': status,
    'submittedAtMillis': 0,
    'updatedAtMillis': 1,
    'reviewedAtMillis': null,
    'submissionVersion': 1,
    'fullName': 'Ad Soyad',
    'verifiedPhoneNumber': '+900000000',
    'email': null,
    'driverTaxiStandName': null,
    'driverTaxiStandAddress': null,
    'workType': 'vehicleOwner',
    'vehiclePlate': '00 XX 000',
    'vehicleBrand': 'Marka',
    'vehicleModel': 'Model',
    'vehicleModelYear': 2024,
    'registrationOwnerType': 'applicant',
    'hasVehicleUseAuthorization': true,
    'vehicleTaxiStandName': null,
    'informationAccuracyAccepted': true,
    'documentValidityNotificationAccepted': true,
    'documentProcessingNoticeAccepted': true,
    'kvkkNoticeAccepted': true,
    'termsAccepted': true,
    'marketingConsent': false,
    'rejectionReasonCode': null,
  },
  'documents':
      [
            'driverLicenseFront',
            'driverLicenseBack',
            'identityCardFront',
            'identityCardBack',
            'vehicleRegistration',
            'driverProfilePhoto',
            'criminalRecord',
          ]
          .map(
            (type) => {
              'documentType': type,
              'reviewStatus': 'pendingReview',
              'reviewedAtMillis': null,
              'rejectionReasonCode': null,
              'contentType': 'image/jpeg',
              'sizeBytes': 100,
            },
          )
          .toList(),
};
