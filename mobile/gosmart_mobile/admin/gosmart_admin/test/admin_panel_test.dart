import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_admin/application/ports.dart';
import 'package:gosmart_admin/controllers/admin_auth_controller.dart';
import 'package:gosmart_admin/controllers/driver_applications_controller.dart';
import 'package:gosmart_admin/core/admin_exceptions.dart';
import 'package:gosmart_admin/core/formatting.dart';
import 'package:gosmart_admin/domain/admin_session.dart';
import 'package:gosmart_admin/domain/driver_application.dart';
import 'package:gosmart_admin/screens/admin_login_screen.dart';
import 'package:gosmart_admin/screens/driver_application_details_screen.dart';
import 'package:gosmart_admin/screens/driver_applications_screen.dart';
import 'package:gosmart_admin/services/driver_application_admin_read_service.dart';

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
  testWidgets('details shows sections but no protected context or actions', (
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
    expect(find.textContaining('Görüntüle'), findsNothing);
    expect(find.textContaining('Başvuruyu Onayla'), findsNothing);
    expect(find.textContaining('Başvuruyu Reddet'), findsNothing);
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
  @override
  Future<Object?> call({
    required String functionName,
    required Map<String, Object?> payload,
  }) async {
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

final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
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

Map<String, Object?> detailsResponse() => {
  'reviewContext': {'submissionVersion': 1, 'documentSetId': 'set-secret'},
  'application': {
    'applicationId': 'app-1',
    'status': 'pendingReview',
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
