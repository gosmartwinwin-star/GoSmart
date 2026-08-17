import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/domain/matching/matching_policy.dart';

void main() {
  final contract = _loadContract();

  test('Flutter constants match shared backend parity contract', () {
    expect(contract.version, 1);

    expect(
      MatchingPolicy.maximumPickupDetourMeters,
      contract.maximumDetourMeters,
    );

    expect(
      MatchingPolicy.maximumDropoffDetourMeters,
      contract.maximumDetourMeters,
    );

    expect(
      MatchingPolicy.maximumPickupDetourSeconds,
      contract.maximumDetourSeconds,
    );

    expect(
      MatchingPolicy.maximumDropoffDetourSeconds,
      contract.maximumDetourSeconds,
    );

    expect(MatchingPolicy.subscriptionRequired, contract.subscriptionRequired);

    expect(
      MatchingPolicy.subscriptionRequiredReason,
      contract.subscriptionRequiredReason,
    );
  });

  for (final entry in contract.cases) {
    test('Flutter shared parity case: ${entry.name}', () {
      final deviation = RouteDeviationResult(
        pickupDetourMeters: entry.pickupDetourMeters,
        pickupDetourSeconds: entry.pickupDetourSeconds,
        dropoffDetourMeters: entry.dropoffDetourMeters,
        dropoffDetourSeconds: entry.dropoffDetourSeconds,
        pickupRouteIndex: entry.pickupRouteIndex,
        dropoffRouteIndex: entry.dropoffRouteIndex,
      );

      final evaluation = const MatchingPolicy().evaluate(
        subscriptionActive: true,
        deviation: deviation,
      );

      expect(evaluation.isEligible, entry.expectedEligible, reason: entry.name);

      final expectedReason = entry.expectedReason;

      if (expectedReason == null) {
        expect(evaluation.rejectionReasons, isEmpty, reason: entry.name);
      } else {
        expect(evaluation.rejectionReasons, [
          expectedReason,
        ], reason: entry.name);
      }
    });
  }

  test('Flutter subscription gate matches shared parity contract', () {
    final baseline = contract.cases.firstWhere(
      (entry) => entry.name == 'zero_detour_forward',
    );

    final evaluation = const MatchingPolicy().evaluate(
      subscriptionActive: false,
      deviation: RouteDeviationResult(
        pickupDetourMeters: baseline.pickupDetourMeters,
        pickupDetourSeconds: baseline.pickupDetourSeconds,
        dropoffDetourMeters: baseline.dropoffDetourMeters,
        dropoffDetourSeconds: baseline.dropoffDetourSeconds,
        pickupRouteIndex: baseline.pickupRouteIndex,
        dropoffRouteIndex: baseline.dropoffRouteIndex,
      ),
    );

    expect(evaluation.isEligible, isFalse);

    expect(evaluation.rejectionReasons, [contract.subscriptionRequiredReason]);
  });
}

_ParityContract _loadContract() {
  final raw = File(
    'test/fixtures/matching_policy_parity.json',
  ).readAsStringSync();

  final decoded = jsonDecode(raw);

  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Matching parity contract must be an object.');
  }

  return _ParityContract.fromMap(decoded);
}

class _ParityContract {
  const _ParityContract({
    required this.version,
    required this.maximumDetourMeters,
    required this.maximumDetourSeconds,
    required this.subscriptionRequired,
    required this.subscriptionRequiredReason,
    required this.cases,
  });

  final int version;
  final int maximumDetourMeters;
  final int maximumDetourSeconds;
  final bool subscriptionRequired;
  final String subscriptionRequiredReason;
  final List<_ParityCase> cases;

  factory _ParityContract.fromMap(Map<String, dynamic> map) {
    final rawCases = map['cases'];

    if (rawCases is! List<dynamic>) {
      throw const FormatException('Matching parity cases must be a list.');
    }

    final cases = rawCases
        .map((rawCase) {
          if (rawCase is! Map<String, dynamic>) {
            throw const FormatException(
              'Matching parity case must be an object.',
            );
          }

          return _ParityCase.fromMap(rawCase);
        })
        .toList(growable: false);

    if (cases.isEmpty) {
      throw const FormatException('Matching parity cases cannot be empty.');
    }

    final names = cases.map((entry) => entry.name).toSet();

    if (names.length != cases.length) {
      throw const FormatException('Matching parity case names must be unique.');
    }

    return _ParityContract(
      version: _requiredInt(map, 'version'),
      maximumDetourMeters: _requiredInt(map, 'maximumDetourMeters'),
      maximumDetourSeconds: _requiredInt(map, 'maximumDetourSeconds'),
      subscriptionRequired: _requiredBool(map, 'subscriptionRequired'),
      subscriptionRequiredReason: _requiredString(
        map,
        'subscriptionRequiredReason',
      ),
      cases: cases,
    );
  }
}

class _ParityCase {
  const _ParityCase({
    required this.name,
    required this.pickupRouteIndex,
    required this.dropoffRouteIndex,
    required this.pickupDetourMeters,
    required this.pickupDetourSeconds,
    required this.dropoffDetourMeters,
    required this.dropoffDetourSeconds,
    required this.expectedEligible,
    required this.expectedReason,
  });

  final String name;
  final int pickupRouteIndex;
  final int dropoffRouteIndex;
  final int pickupDetourMeters;
  final int pickupDetourSeconds;
  final int dropoffDetourMeters;
  final int dropoffDetourSeconds;
  final bool expectedEligible;
  final String? expectedReason;

  factory _ParityCase.fromMap(Map<String, dynamic> map) {
    final reason = map['expectedReason'];

    if (reason != null && reason is! String) {
      throw const FormatException('expectedReason must be string or null.');
    }

    return _ParityCase(
      name: _requiredString(map, 'name'),
      pickupRouteIndex: _requiredInt(map, 'pickupRouteIndex'),
      dropoffRouteIndex: _requiredInt(map, 'dropoffRouteIndex'),
      pickupDetourMeters: _requiredInt(map, 'pickupDetourMeters'),
      pickupDetourSeconds: _requiredInt(map, 'pickupDetourSeconds'),
      dropoffDetourMeters: _requiredInt(map, 'dropoffDetourMeters'),
      dropoffDetourSeconds: _requiredInt(map, 'dropoffDetourSeconds'),
      expectedEligible: _requiredBool(map, 'expectedEligible'),
      expectedReason: reason as String?,
    );
  }
}

int _requiredInt(Map<String, dynamic> map, String key) {
  final value = map[key];

  if (value is! int) {
    throw FormatException('$key must be int.');
  }

  return value;
}

bool _requiredBool(Map<String, dynamic> map, String key) {
  final value = map[key];

  if (value is! bool) {
    throw FormatException('$key must be bool.');
  }

  return value;
}

String _requiredString(Map<String, dynamic> map, String key) {
  final value = map[key];

  if (value is! String || value.isEmpty) {
    throw FormatException('$key must be non-empty string.');
  }

  return value;
}
