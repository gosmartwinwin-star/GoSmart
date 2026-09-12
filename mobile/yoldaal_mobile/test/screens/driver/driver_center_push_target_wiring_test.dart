import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/screens/driver/driver_center_screen.dart',
  ).readAsStringSync();

  String section(
    String start,
    String end,
  ) {
    final startIndex = source.indexOf(start);
    final endIndex = source.indexOf(
      end,
      startIndex + start.length,
    );

    expect(startIndex, isNonNegative);
    expect(endIndex, greaterThan(startIndex));

    return source.substring(
      startIndex,
      endIndex,
    );
  }

  test('production lifecycle has injectable test seam', () {
    expect(
      source,
      contains(
        'final DriverPushTargetLifecycle? pushTargetLifecycle;',
      ),
    );

    final initialization = section(
      '  void _initializePushTargetLifecycle() {',
      '  void _syncPushTargetLifecycleEligibility() {',
    );

    expect(
      initialization,
      contains('final injected = widget.pushTargetLifecycle;'),
    );
    expect(
      initialization,
      contains('if (widget.controller != null) {'),
    );
    expect(
      initialization,
      contains('DriverPushTargetRegistrationService()'),
    );
    expect(
      initialization,
      contains('DriverPushTargetLifecycleController('),
    );
  });

  test('push eligibility is exactly ready and resumed', () {
    final eligibility = section(
      '  void _syncPushTargetLifecycleEligibility() {',
      '  DriverPlanPurchaseController? _resolvePlanPurchaseController() {',
    );

    expect(
      eligibility,
      contains('_appResumed &&'),
    );
    expect(
      eligibility,
      contains(
        'controller.status == DriverCenterStatus.ready',
      ),
    );
    expect(
      eligibility,
      isNot(contains('subscription_required')),
    );
  });

  test('auth and app lifecycle both drive eligibility', () {
    final appLifecycle = section(
      '  void didChangeAppLifecycleState(',
      '  void _initializePushTargetLifecycle() {',
    );

    expect(
      appLifecycle,
      contains('_syncPushTargetLifecycleEligibility();'),
    );

    final refresh = section(
      '  void _refresh() {',
      '  @override\n  void dispose() {',
    );

    expect(
      refresh,
      contains('_syncPushTargetLifecycleEligibility();'),
    );

    expect(
      source,
      contains(
        '_pushTargetLifecycle?.setEligible(false);',
      ),
    );
  });

  test('platform and ownership remain bounded', () {
    final platform = section(
      'DriverPushTargetPlatform? _resolveDriverPushTargetPlatform() {',
      'class _FirebaseDriverCenterAuth implements DriverCenterAuthGateway {',
    );

    expect(platform, contains('if (kIsWeb)'));
    expect(
      platform,
      contains(
        'TargetPlatform.android => DriverPushTargetPlatform.android',
      ),
    );
    expect(
      platform,
      contains(
        'TargetPlatform.iOS => DriverPushTargetPlatform.ios',
      ),
    );
    expect(platform, contains('_ => null'));

    final dispose = section(
      '  void dispose() {',
      '  Future<void> _selectDestination() async {',
    );

    expect(
      dispose,
      contains('_pushTargetLifecycle?.setEligible(false);'),
    );
    expect(
      dispose,
      contains('if (_ownsPushTargetLifecycle) {'),
    );
    expect(
      dispose,
      contains('_pushTargetLifecycle?.dispose();'),
    );
  });
}
