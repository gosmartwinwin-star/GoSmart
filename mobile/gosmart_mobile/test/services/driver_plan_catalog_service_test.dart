import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/driver_access/driver_plan_catalog_gateway.dart';
import 'package:gosmart_mobile/domain/subscription/driver_pass_plan.dart';
import 'package:gosmart_mobile/services/driver_plan_catalog_service.dart';

void main() {
  test(
    'canonical catalog uses exact callable and exact empty payload',
    () async {
      String? calledName;
      Map<String, dynamic>? calledPayload;

      final service = DriverPlanCatalogService(
        caller: (name, payload) async {
          calledName = name;
          calledPayload = payload;
          return response();
        },
      );

      final result = await service.load();

      expect(calledName, 'getDriverPlanCatalog');
      expect(calledPayload, <String, dynamic>{});
      expect(result.catalogVersion, 'catalog_v1');
      expect(
        result.plans.map((entry) => entry.plan).toList(),
        DriverPassPlan.values,
      );
      expect(result.plans.first.amountMinor, 0);
    },
  );

  test(
    'disabled plan and authoritative commercial fields are preserved',
    () async {
      final service = DriverPlanCatalogService(
        caller: (_, _) async => response(
          weeklyEnabled: false,
          weeklyAmountMinor: 3456,
          currency: 'EUR',
        ),
      );

      final result = await service.load();
      final weekly = result.entryFor(DriverPassPlan.weekly);

      expect(weekly, isNotNull);
      expect(weekly!.enabled, isFalse);
      expect(weekly.amountMinor, 3456);
      expect(weekly.currency, 'EUR');
    },
  );

  test('malformed callable responses fail closed', () async {
    final malformed = <Object?>[
      null,
      <String, Object?>{},
      {...response(), 'extra': true},
      {...response(), 'catalogVersion': ''},
      {...response(), 'plans': <Object?>[]},
      response(
        overridePlan: 0,
        overrideEntry: {
          'planId': 'weekly',
          'enabled': true,
          'amountMinor': 0,
          'currency': 'TRY',
        },
      ),
      response(
        overridePlan: 1,
        overrideEntry: {
          'planId': 'unknown',
          'enabled': true,
          'amountMinor': 100,
          'currency': 'TRY',
        },
      ),
      response(
        overridePlan: 1,
        overrideEntry: {
          'planId': 'weekly',
          'enabled': 'yes',
          'amountMinor': 100,
          'currency': 'TRY',
        },
      ),
      response(
        overridePlan: 1,
        overrideEntry: {
          'planId': 'weekly',
          'enabled': true,
          'amountMinor': -1,
          'currency': 'TRY',
        },
      ),
      response(
        overridePlan: 1,
        overrideEntry: {
          'planId': 'weekly',
          'enabled': true,
          'amountMinor': 9007199254740992,
          'currency': 'TRY',
        },
      ),
      response(
        overridePlan: 1,
        overrideEntry: {
          'planId': 'weekly',
          'enabled': true,
          'amountMinor': 100,
          'currency': 'try',
        },
      ),
      response(
        overridePlan: 1,
        overrideEntry: {
          'planId': 'weekly',
          'enabled': true,
          'amountMinor': 100,
          'currency': 'TRY',
          'extra': true,
        },
      ),
    ];

    for (final value in malformed) {
      final service = DriverPlanCatalogService(caller: (_, _) async => value);

      await expectLater(
        service.load(),
        throwsA(
          isA<DriverPlanCatalogException>().having(
            (error) => error.code,
            'code',
            'invalid-response',
          ),
        ),
      );
    }
  });

  test('controlled Functions code and safe reason are preserved', () async {
    final service = DriverPlanCatalogService(
      caller: (_, _) => throw _TestFunctionsException(
        code: 'failed-precondition',
        details: {'reason': 'driver_plan_catalog_unavailable'},
      ),
    );

    await expectLater(
      service.load(),
      throwsA(
        isA<DriverPlanCatalogException>()
            .having((error) => error.code, 'code', 'failed-precondition')
            .having(
              (error) => error.reason,
              'reason',
              'driver_plan_catalog_unavailable',
            ),
      ),
    );
  });

  test('unsafe details and unexpected client failures are sanitized', () async {
    final unsafeDetails = DriverPlanCatalogService(
      caller: (_, _) => throw _TestFunctionsException(
        code: 'permission-denied',
        details: {'reason': 'RAW SECRET DETAIL'},
      ),
    );

    await expectLater(
      unsafeDetails.load(),
      throwsA(
        isA<DriverPlanCatalogException>()
            .having((error) => error.code, 'code', 'permission-denied')
            .having((error) => error.reason, 'reason', isNull),
      ),
    );

    final unexpected = DriverPlanCatalogService(
      caller: (_, _) => throw StateError('socket secret'),
    );

    await expectLater(
      unexpected.load(),
      throwsA(
        isA<DriverPlanCatalogException>().having(
          (error) => error.code,
          'code',
          'unavailable',
        ),
      ),
    );
  });
}

Map<String, Object?> response({
  bool weeklyEnabled = true,
  int weeklyAmountMinor = 200,
  String currency = 'TRY',
  int? overridePlan,
  Map<String, Object?>? overrideEntry,
}) {
  final plans = <Map<String, Object?>>[
    {
      'planId': 'daily',
      'enabled': true,
      'amountMinor': 0,
      'currency': currency,
    },
    {
      'planId': 'weekly',
      'enabled': weeklyEnabled,
      'amountMinor': weeklyAmountMinor,
      'currency': currency,
    },
    {
      'planId': 'monthly',
      'enabled': true,
      'amountMinor': 300,
      'currency': currency,
    },
    {
      'planId': 'quarterly',
      'enabled': true,
      'amountMinor': 400,
      'currency': currency,
    },
  ];

  if (overridePlan != null && overrideEntry != null) {
    plans[overridePlan] = overrideEntry;
  }

  return {'catalogVersion': 'catalog_v1', 'plans': plans};
}

class _TestFunctionsException extends FirebaseFunctionsException {
  _TestFunctionsException({required super.code, super.details})
    : super(message: 'safe test failure');
}
