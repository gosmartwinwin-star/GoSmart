import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/ride/ride_gateway.dart';
import 'package:yoldaal_mobile/application/ride/ride_midtrip_route_change_gateway.dart';
import 'package:yoldaal_mobile/core/firebase/firebase_functions_registry.dart';
import 'package:yoldaal_mobile/domain/ride/canonical_ride.dart';
import 'package:yoldaal_mobile/services/ride_lifecycle_service.dart';
import 'package:yoldaal_mobile/services/ride_midtrip_route_change_service.dart';

void main() {
  const dropoff = RideLocation(
    latitude: 41.0082,
    longitude: 28.9784,
    addressLabel: 'Yeni hedef',
  );

  test(
    'propose sends exact frozen payload and parses compatible result',
    () async {
      final invoker = _Invoker()
        ..response = <String, dynamic>{
          'rideId': 'ride_1',
          'proposalId': 'proposal_1',
          'status': 'appliedCompatible',
          'compatible': true,
          'requiresCounterpartyAcknowledgement': false,
          'version': 5,
        };

      final service = RideMidtripRouteChangeService(invoker: invoker);

      final result = await service.proposeDropoffChange(
        rideId: 'ride_1',
        newDropoff: dropoff,
        requestId: 'midtrip_request_1234567890',
      );

      expect(invoker.names, <String>[
        FirebaseFunctionsRegistry.proposeRideDropoffChange,
      ]);

      expect(invoker.payloads, <Map<String, dynamic>>[
        <String, dynamic>{
          'rideId': 'ride_1',
          'newDropoff': <String, dynamic>{
            'latitude': 41.0082,
            'longitude': 28.9784,
            'addressLabel': 'Yeni hedef',
          },
          'requestId': 'midtrip_request_1234567890',
        },
      ]);

      expect(result.rideId, 'ride_1');
      expect(result.proposalId, 'proposal_1');
      expect(result.status, RideDropoffChangeProposalStatus.appliedCompatible);
      expect(result.compatible, isTrue);
      expect(result.requiresCounterpartyAcknowledgement, isFalse);
      expect(result.version, 5);
    },
  );

  test(
    'propose parses pending incompatible result without client authority',
    () async {
      final invoker = _Invoker()
        ..response = <String, dynamic>{
          'rideId': 'ride_1',
          'proposalId': 'proposal_2',
          'status': 'pendingAcknowledgement',
          'compatible': false,
          'requiresCounterpartyAcknowledgement': true,
          'version': 4,
        };

      final result = await RideMidtripRouteChangeService(invoker: invoker)
          .proposeDropoffChange(
            rideId: 'ride_1',
            newDropoff: dropoff,
            requestId: 'midtrip_pending_1234567890',
          );

      expect(
        result.status,
        RideDropoffChangeProposalStatus.pendingAcknowledgement,
      );
      expect(result.compatible, isFalse);
      expect(result.requiresCounterpartyAcknowledgement, isTrue);

      expect(invoker.payloads.single.keys.toList(), <String>[
        'rideId',
        'newDropoff',
        'requestId',
      ]);
    },
  );

  test(
    'pending read sends exact payload and parses privacy-minimal result',
    () async {
      final invoker = _Invoker()
        ..response = <String, dynamic>{
          'rideId': 'ride_1',
          'proposalId': 'proposal_2',
          'status': 'pendingAcknowledgement',
          'requestedDropoff': <String, dynamic>{
            'latitude': 41.0082,
            'longitude': 28.9784,
            'addressLabel': 'Yeni hedef',
          },
        };

      final result = await RideMidtripRouteChangeService(invoker: invoker)
          .getPendingDropoffChangeProposal(
            rideId: 'ride_1',
            proposalId: 'proposal_2',
          );

      expect(invoker.names, <String>[
        FirebaseFunctionsRegistry.getPendingRideDropoffChangeProposal,
      ]);

      expect(invoker.payloads.single, <String, dynamic>{
        'rideId': 'ride_1',
        'proposalId': 'proposal_2',
      });

      expect(result.rideId, 'ride_1');
      expect(result.proposalId, 'proposal_2');
      expect(
        result.status,
        RideDropoffChangeProposalStatus.pendingAcknowledgement,
      );
      expect(result.requestedDropoff.latitude, 41.0082);
      expect(result.requestedDropoff.longitude, 28.9784);
      expect(result.requestedDropoff.addressLabel, 'Yeni hedef');
    },
  );

  test(
    'pending read rejects private extras and malformed response semantics',
    () async {
      final invalidResponses = <Map<String, dynamic>>[
        <String, dynamic>{
          'rideId': 'ride_1',
          'proposalId': 'proposal_2',
          'status': 'pendingAcknowledgement',
          'requestedDropoff': <String, dynamic>{
            'latitude': 41.0082,
            'longitude': 28.9784,
            'addressLabel': 'Yeni hedef',
          },
          'driverId': 'must-not-leak',
        },
        <String, dynamic>{
          'rideId': 'ride_1',
          'proposalId': 'proposal_2',
          'status': 'appliedCompatible',
          'requestedDropoff': <String, dynamic>{
            'latitude': 41.0082,
            'longitude': 28.9784,
            'addressLabel': 'Yeni hedef',
          },
        },
        <String, dynamic>{
          'rideId': 'ride_1',
          'proposalId': 'proposal_2',
          'status': 'pendingAcknowledgement',
          'requestedDropoff': <String, dynamic>{
            'latitude': 91,
            'longitude': 28.9784,
            'addressLabel': 'Yeni hedef',
          },
        },
        <String, dynamic>{
          'rideId': 'ride_1',
          'proposalId': 'proposal_2',
          'status': 'pendingAcknowledgement',
          'requestedDropoff': <String, dynamic>{
            'latitude': 41.0082,
            'longitude': 28.9784,
            'addressLabel': 'Yeni hedef',
            'encodedPolyline': 'must-not-leak',
          },
        },
      ];

      for (final response in invalidResponses) {
        final invoker = _Invoker()..response = response;

        await expectLater(
          RideMidtripRouteChangeService(
            invoker: invoker,
          ).getPendingDropoffChangeProposal(
            rideId: 'ride_1',
            proposalId: 'proposal_2',
          ),
          throwsA(
            isA<RideGatewayException>().having(
              (error) => error.code,
              'code',
              'invalid-response',
            ),
          ),
        );
      }
    },
  );

  test(
    'pending read validates ids and preserves backend error reason',
    () async {
      final service = RideMidtripRouteChangeService(invoker: _Invoker());

      await expectLater(
        service.getPendingDropoffChangeProposal(
          rideId: 'ride_1',
          proposalId: 'proposal/invalid',
        ),
        throwsArgumentError,
      );

      final invoker = _Invoker()
        ..error = const RideGatewayException(
          'permission-denied',
          reason: 'route_change_counterparty_required',
        );

      await expectLater(
        RideMidtripRouteChangeService(
          invoker: invoker,
        ).getPendingDropoffChangeProposal(
          rideId: 'ride_1',
          proposalId: 'proposal_2',
        ),
        throwsA(
          isA<RideGatewayException>()
              .having((error) => error.code, 'code', 'permission-denied')
              .having(
                (error) => error.reason,
                'reason',
                'route_change_counterparty_required',
              ),
        ),
      );
    },
  );
  test('ack accept sends exact payload and parses regime-end result', () async {
    final invoker = _Invoker()
      ..response = <String, dynamic>{
        'rideId': 'ride_1',
        'proposalId': 'proposal_1',
        'status': 'acceptedIncompatible',
        'decision': 'accept',
        'version': 5,
        'yoldaalRegimeEnded': true,
      };

    final result = await RideMidtripRouteChangeService(invoker: invoker)
        .acknowledgeDropoffChange(
          rideId: 'ride_1',
          proposalId: 'proposal_1',
          decision: RideDropoffChangeDecision.accept,
          requestId: 'midtrip_accept_1234567890',
        );

    expect(invoker.names, <String>[
      FirebaseFunctionsRegistry.acknowledgeRideDropoffChange,
    ]);

    expect(invoker.payloads.single, <String, dynamic>{
      'rideId': 'ride_1',
      'proposalId': 'proposal_1',
      'decision': 'accept',
      'requestId': 'midtrip_accept_1234567890',
    });

    expect(result.status, RideDropoffChangeProposalStatus.acceptedIncompatible);
    expect(result.decision, RideDropoffChangeDecision.accept);
    expect(result.version, 5);
    expect(result.yoldaalRegimeEnded, isTrue);
  });

  test('ack reject parses unchanged-regime result', () async {
    final invoker = _Invoker()
      ..response = <String, dynamic>{
        'rideId': 'ride_1',
        'proposalId': 'proposal_1',
        'status': 'rejectedIncompatible',
        'decision': 'reject',
        'version': 4,
        'yoldaalRegimeEnded': false,
      };

    final result = await RideMidtripRouteChangeService(invoker: invoker)
        .acknowledgeDropoffChange(
          rideId: 'ride_1',
          proposalId: 'proposal_1',
          decision: RideDropoffChangeDecision.reject,
          requestId: 'midtrip_reject_1234567890',
        );

    expect(result.status, RideDropoffChangeProposalStatus.rejectedIncompatible);
    expect(result.decision, RideDropoffChangeDecision.reject);
    expect(result.version, 4);
    expect(result.yoldaalRegimeEnded, isFalse);
  });

  test('caller-owned requestId remains unchanged across retry', () async {
    final invoker = _Invoker()
      ..failuresRemaining = 1
      ..response = <String, dynamic>{
        'rideId': 'ride_1',
        'proposalId': 'proposal_retry',
        'status': 'pendingAcknowledgement',
        'compatible': false,
        'requiresCounterpartyAcknowledgement': true,
        'version': 4,
      };

    final service = RideMidtripRouteChangeService(invoker: invoker);

    const stableRequestId = 'midtrip_retry_1234567890';

    await expectLater(
      service.proposeDropoffChange(
        rideId: 'ride_1',
        newDropoff: dropoff,
        requestId: stableRequestId,
      ),
      throwsA(
        isA<RideGatewayException>().having(
          (error) => error.code,
          'code',
          'unavailable',
        ),
      ),
    );

    final result = await service.proposeDropoffChange(
      rideId: 'ride_1',
      newDropoff: dropoff,
      requestId: stableRequestId,
    );

    expect(result.proposalId, 'proposal_retry');

    expect(
      invoker.payloads.map((payload) => payload['requestId']),
      everyElement(stableRequestId),
    );
  });

  test('local validation rejects malformed ids request and dropoff', () async {
    final service = RideMidtripRouteChangeService(invoker: _Invoker());

    await expectLater(
      service.proposeDropoffChange(
        rideId: 'ride/invalid',
        newDropoff: dropoff,
        requestId: 'midtrip_request_1234567890',
      ),
      throwsArgumentError,
    );

    await expectLater(
      service.proposeDropoffChange(
        rideId: 'ride_1',
        newDropoff: const RideLocation(
          latitude: 91,
          longitude: 29,
          addressLabel: 'Hedef',
        ),
        requestId: 'midtrip_request_1234567890',
      ),
      throwsArgumentError,
    );

    await expectLater(
      service.proposeDropoffChange(
        rideId: 'ride_1',
        newDropoff: const RideLocation(
          latitude: 41,
          longitude: 29,
          addressLabel: '   ',
        ),
        requestId: 'midtrip_request_1234567890',
      ),
      throwsArgumentError,
    );

    await expectLater(
      service.acknowledgeDropoffChange(
        rideId: 'ride_1',
        proposalId: 'proposal/invalid',
        decision: RideDropoffChangeDecision.reject,
        requestId: 'midtrip_request_1234567890',
      ),
      throwsArgumentError,
    );

    await expectLater(
      service.proposeDropoffChange(
        rideId: 'ride_1',
        newDropoff: dropoff,
        requestId: 'short',
      ),
      throwsArgumentError,
    );
  });

  test(
    'proposal response is exact and semantic mismatches fail closed',
    () async {
      final invalidResponses = <Map<String, dynamic>>[
        <String, dynamic>{
          'rideId': 'ride_1',
          'proposalId': 'proposal_1',
          'status': 'appliedCompatible',
          'compatible': true,
          'requiresCounterpartyAcknowledgement': false,
          'version': 5,
          'driverId': 'must-not-leak',
        },
        <String, dynamic>{
          'rideId': 'ride_1',
          'proposalId': 'proposal_1',
          'status': 'pendingAcknowledgement',
          'compatible': true,
          'requiresCounterpartyAcknowledgement': false,
          'version': 5,
        },
        <String, dynamic>{
          'rideId': 'ride_1',
          'proposalId': 'proposal_1',
          'status': 'pendingAcknowledgement',
          'compatible': false,
          'requiresCounterpartyAcknowledgement': false,
          'version': 4,
        },
      ];

      for (final response in invalidResponses) {
        final invoker = _Invoker()..response = response;

        await expectLater(
          RideMidtripRouteChangeService(invoker: invoker).proposeDropoffChange(
            rideId: 'ride_1',
            newDropoff: dropoff,
            requestId: 'midtrip_invalid_1234567890',
          ),
          throwsA(
            isA<RideGatewayException>().having(
              (error) => error.code,
              'code',
              'invalid-response',
            ),
          ),
        );
      }
    },
  );

  test(
    'ack response is exact and accept reject semantics fail closed',
    () async {
      final invalidResponses = <Map<String, dynamic>>[
        <String, dynamic>{
          'rideId': 'ride_1',
          'proposalId': 'proposal_1',
          'status': 'acceptedIncompatible',
          'decision': 'accept',
          'version': 5,
          'yoldaalRegimeEnded': true,
          'fare': 100,
        },
        <String, dynamic>{
          'rideId': 'ride_1',
          'proposalId': 'proposal_1',
          'status': 'rejectedIncompatible',
          'decision': 'accept',
          'version': 4,
          'yoldaalRegimeEnded': false,
        },
        <String, dynamic>{
          'rideId': 'ride_1',
          'proposalId': 'proposal_1',
          'status': 'acceptedIncompatible',
          'decision': 'accept',
          'version': 5,
          'yoldaalRegimeEnded': false,
        },
      ];

      for (final response in invalidResponses) {
        final invoker = _Invoker()..response = response;

        await expectLater(
          RideMidtripRouteChangeService(
            invoker: invoker,
          ).acknowledgeDropoffChange(
            rideId: 'ride_1',
            proposalId: 'proposal_1',
            decision: RideDropoffChangeDecision.accept,
            requestId: 'midtrip_invalid_1234567890',
          ),
          throwsA(
            isA<RideGatewayException>().having(
              (error) => error.code,
              'code',
              'invalid-response',
            ),
          ),
        );
      }
    },
  );

  test('gateway errors propagate with backend reason unchanged', () async {
    final invoker = _Invoker()
      ..error = const RideGatewayException(
        'failed-precondition',
        reason: 'midtrip_legacy_missing_frozen_context',
      );

    await expectLater(
      RideMidtripRouteChangeService(invoker: invoker).proposeDropoffChange(
        rideId: 'ride_1',
        newDropoff: dropoff,
        requestId: 'midtrip_error_1234567890',
      ),
      throwsA(
        isA<RideGatewayException>()
            .having((error) => error.code, 'code', 'failed-precondition')
            .having(
              (error) => error.reason,
              'reason',
              'midtrip_legacy_missing_frozen_context',
            ),
      ),
    );
  });
}

class _Invoker implements RideCallableInvoker {
  final names = <String>[];
  final payloads = <Map<String, dynamic>>[];

  Map<String, dynamic> response = const <String, dynamic>{};
  RideGatewayException? error;
  int failuresRemaining = 0;

  @override
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> payload,
  ) async {
    names.add(name);
    payloads.add(Map<String, dynamic>.from(payload));

    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw const RideGatewayException('unavailable');
    }

    final currentError = error;

    if (currentError != null) {
      throw currentError;
    }

    return Map<String, dynamic>.from(response);
  }
}
