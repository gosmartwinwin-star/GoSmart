import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/ride/ride_dropoff_change_proposal_event_gateway.dart';
import 'package:yoldaal_mobile/application/ride/ride_gateway.dart';
import 'package:yoldaal_mobile/application/ride/ride_midtrip_route_change_gateway.dart';
import 'package:yoldaal_mobile/controllers/ride_midtrip_route_change_controller.dart';
import 'package:yoldaal_mobile/domain/ride/canonical_ride.dart';

void main() {
  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'inactive controller does not generate request id or invoke mutation',
    () async {
      final ride = _RideState(
        rideId: 'ride_1',
        status: RideStatus.driverArrived,
      );

      final events = _EventGateway();
      final gateway = _Gateway();

      addTearDown(events.close);

      var generatedIds = 0;

      final controller = RideMidtripRouteChangeController(
        rideListenable: ride,
        rideId: () => ride.rideId,
        rideStatus: () => ride.status,
        eventGateway: events,
        routeChangeGateway: gateway,
        requestIdGenerator: () {
          generatedIds += 1;
          return 'midtrip_request_$generatedIds';
        },
      )..start();

      final result = await controller.proposeDropoffChange(
        newDropoff: dropoffA,
      );

      expect(result, isNull);
      expect(generatedIds, 0);
      expect(gateway.proposeRequestIds, isEmpty);

      controller.dispose();
    },
  );

  test(
    'duplicate propose tap is blocked and unavailable retry reuses request id',
    () async {
      final ride = _RideState(rideId: 'ride_1', status: RideStatus.inProgress);

      final events = _EventGateway();
      final gateway = _Gateway();

      addTearDown(events.close);

      var generatedIds = 0;

      final firstCall = Completer<RideDropoffChangeProposalResult>();

      gateway.proposeHandler = (rideId, newDropoff, requestId) {
        if (gateway.proposeRequestIds.length == 1) {
          return firstCall.future;
        }

        return Future<RideDropoffChangeProposalResult>.value(
          _proposal(rideId, 'proposal_retry', compatible: false),
        );
      };

      final controller = RideMidtripRouteChangeController(
        rideListenable: ride,
        rideId: () => ride.rideId,
        rideStatus: () => ride.status,
        eventGateway: events,
        routeChangeGateway: gateway,
        requestIdGenerator: () {
          generatedIds += 1;
          return 'midtrip_retry_${generatedIds}_1234567890';
        },
      )..start();

      final first = controller.proposeDropoffChange(newDropoff: dropoffA);

      await settle();

      expect(controller.isActionInFlight, isTrue);
      expect(gateway.proposeRequestIds.length, 1);

      final duplicate = await controller.proposeDropoffChange(
        newDropoff: dropoffA,
      );

      expect(duplicate, isNull);
      expect(gateway.proposeRequestIds.length, 1);
      expect(generatedIds, 1);

      firstCall.completeError(const RideGatewayException('unavailable'));

      expect(await first, isNull);

      expect(
        controller.actionError,
        isA<RideGatewayException>().having(
          (error) => error.code,
          'code',
          'unavailable',
        ),
      );

      final retry = await controller.proposeDropoffChange(newDropoff: dropoffA);

      expect(retry?.proposalId, 'proposal_retry');

      expect(gateway.proposeRequestIds, <String>[
        'midtrip_retry_1_1234567890',
        'midtrip_retry_1_1234567890',
      ]);

      expect(generatedIds, 1);
      expect(controller.actionError, isNull);

      controller.dispose();
    },
  );

  test(
    'changed proposal payload after unavailable receives a new request id',
    () async {
      final ride = _RideState(rideId: 'ride_1', status: RideStatus.inProgress);

      final events = _EventGateway();
      final gateway = _Gateway();

      addTearDown(events.close);

      var generatedIds = 0;

      gateway.proposeHandler = (rideId, newDropoff, requestId) async {
        if (gateway.proposeRequestIds.length == 1) {
          throw const RideGatewayException('unavailable');
        }

        return _proposal(rideId, 'proposal_new_payload', compatible: true);
      };

      final controller = RideMidtripRouteChangeController(
        rideListenable: ride,
        rideId: () => ride.rideId,
        rideStatus: () => ride.status,
        eventGateway: events,
        routeChangeGateway: gateway,
        requestIdGenerator: () {
          generatedIds += 1;
          return 'midtrip_payload_${generatedIds}_1234567890';
        },
      )..start();

      expect(
        await controller.proposeDropoffChange(newDropoff: dropoffA),
        isNull,
      );

      final result = await controller.proposeDropoffChange(
        newDropoff: dropoffB,
      );

      expect(result?.compatible, isTrue);

      expect(gateway.proposeRequestIds, <String>[
        'midtrip_payload_1_1234567890',
        'midtrip_payload_2_1234567890',
      ]);

      expect(generatedIds, 2);

      controller.dispose();
    },
  );

  test(
    'successful proposal consumes request id for next logical proposal',
    () async {
      final ride = _RideState(rideId: 'ride_1', status: RideStatus.inProgress);

      final events = _EventGateway();
      final gateway = _Gateway();

      addTearDown(events.close);

      var generatedIds = 0;

      gateway.proposeHandler = (rideId, newDropoff, requestId) async =>
          _proposal(
            rideId,
            'proposal_${gateway.proposeRequestIds.length}',
            compatible: true,
          );

      final controller = RideMidtripRouteChangeController(
        rideListenable: ride,
        rideId: () => ride.rideId,
        rideStatus: () => ride.status,
        eventGateway: events,
        routeChangeGateway: gateway,
        requestIdGenerator: () {
          generatedIds += 1;
          return 'midtrip_success_${generatedIds}_1234567890';
        },
      )..start();

      final first = await controller.proposeDropoffChange(newDropoff: dropoffA);

      final second = await controller.proposeDropoffChange(
        newDropoff: dropoffA,
      );

      expect(first, isNotNull);
      expect(second, isNotNull);

      expect(gateway.proposeRequestIds, <String>[
        'midtrip_success_1_1234567890',
        'midtrip_success_2_1234567890',
      ]);

      controller.dispose();
    },
  );

  test(
    'acknowledgement is limited to a backend-verified pending proposal',
    () async {
      final ride = _RideState(rideId: 'ride_1', status: RideStatus.inProgress);

      final events = _EventGateway();
      final gateway = _Gateway();

      addTearDown(events.close);

      var generatedIds = 0;

      final controller = RideMidtripRouteChangeController(
        rideListenable: ride,
        rideId: () => ride.rideId,
        rideStatus: () => ride.status,
        eventGateway: events,
        routeChangeGateway: gateway,
        requestIdGenerator: () {
          generatedIds += 1;
          return 'midtrip_ack_$generatedIds';
        },
      )..start();

      final result = await controller.acknowledgeDropoffChange(
        proposalId: 'not_discovered',
        decision: RideDropoffChangeDecision.reject,
      );

      expect(result, isNull);
      expect(generatedIds, 0);
      expect(gateway.ackRequestIds, isEmpty);

      controller.dispose();
    },
  );

  test(
    'ack unavailable retry reuses request id and success refreshes resolved proposal',
    () async {
      final ride = _RideState(rideId: 'ride_1', status: RideStatus.inProgress);

      final events = _EventGateway();
      final gateway = _Gateway();

      addTearDown(events.close);

      var resolved = false;
      var generatedIds = 0;

      gateway.getHandler = (rideId, proposalId) async {
        if (resolved) {
          throw const RideGatewayException(
            'failed-precondition',
            reason: 'route_change_proposal_already_resolved',
          );
        }

        return _pending(rideId, proposalId);
      };

      gateway.ackHandler = (rideId, proposalId, decision, requestId) async {
        if (gateway.ackRequestIds.length == 1) {
          throw const RideGatewayException('unavailable');
        }

        resolved = true;

        return _ack(rideId, proposalId, decision);
      };

      final controller = RideMidtripRouteChangeController(
        rideListenable: ride,
        rideId: () => ride.rideId,
        rideStatus: () => ride.status,
        eventGateway: events,
        routeChangeGateway: gateway,
        requestIdGenerator: () {
          generatedIds += 1;
          return 'midtrip_ack_retry_${generatedIds}_1234567890';
        },
      )..start();

      events.emit('ride_1', const <String>['proposal_1']);

      await settle();

      expect(controller.pendingProposals.length, 1);

      final first = await controller.acknowledgeDropoffChange(
        proposalId: 'proposal_1',
        decision: RideDropoffChangeDecision.reject,
      );

      expect(first, isNull);
      expect(controller.pendingProposals.length, 1);

      final retry = await controller.acknowledgeDropoffChange(
        proposalId: 'proposal_1',
        decision: RideDropoffChangeDecision.reject,
      );

      expect(
        retry?.status,
        RideDropoffChangeProposalStatus.rejectedIncompatible,
      );

      expect(gateway.ackRequestIds, <String>[
        'midtrip_ack_retry_1_1234567890',
        'midtrip_ack_retry_1_1234567890',
      ]);

      expect(generatedIds, 1);
      expect(controller.pendingProposals, isEmpty);
      expect(controller.actionError, isNull);

      controller.dispose();
    },
  );

  test(
    'changing ack decision after unavailable uses a new request id',
    () async {
      final ride = _RideState(rideId: 'ride_1', status: RideStatus.inProgress);

      final events = _EventGateway();
      final gateway = _Gateway();

      addTearDown(events.close);

      var resolved = false;
      var generatedIds = 0;

      gateway.getHandler = (rideId, proposalId) async {
        if (resolved) {
          throw const RideGatewayException(
            'failed-precondition',
            reason: 'route_change_proposal_already_resolved',
          );
        }

        return _pending(rideId, proposalId);
      };

      gateway.ackHandler = (rideId, proposalId, decision, requestId) async {
        if (gateway.ackRequestIds.length == 1) {
          throw const RideGatewayException('unavailable');
        }

        resolved = true;

        return _ack(rideId, proposalId, decision);
      };

      final controller = RideMidtripRouteChangeController(
        rideListenable: ride,
        rideId: () => ride.rideId,
        rideStatus: () => ride.status,
        eventGateway: events,
        routeChangeGateway: gateway,
        requestIdGenerator: () {
          generatedIds += 1;
          return 'midtrip_decision_${generatedIds}_1234567890';
        },
      )..start();

      events.emit('ride_1', const <String>['proposal_1']);

      await settle();

      expect(
        await controller.acknowledgeDropoffChange(
          proposalId: 'proposal_1',
          decision: RideDropoffChangeDecision.accept,
        ),
        isNull,
      );

      final result = await controller.acknowledgeDropoffChange(
        proposalId: 'proposal_1',
        decision: RideDropoffChangeDecision.reject,
      );

      expect(result?.decision, RideDropoffChangeDecision.reject);

      expect(gateway.ackRequestIds, <String>[
        'midtrip_decision_1_1234567890',
        'midtrip_decision_2_1234567890',
      ]);

      controller.dispose();
    },
  );

  test(
    'already-resolved ack error refreshes stale pending state without blind retry',
    () async {
      final ride = _RideState(rideId: 'ride_1', status: RideStatus.inProgress);

      final events = _EventGateway();
      final gateway = _Gateway();

      addTearDown(events.close);

      var alreadyResolved = false;

      gateway.getHandler = (rideId, proposalId) async {
        if (alreadyResolved) {
          throw const RideGatewayException(
            'failed-precondition',
            reason: 'route_change_proposal_already_resolved',
          );
        }

        return _pending(rideId, proposalId);
      };

      gateway.ackHandler = (rideId, proposalId, decision, requestId) async {
        alreadyResolved = true;

        throw const RideGatewayException(
          'failed-precondition',
          reason: 'route_change_proposal_already_resolved',
        );
      };

      final controller = RideMidtripRouteChangeController(
        rideListenable: ride,
        rideId: () => ride.rideId,
        rideStatus: () => ride.status,
        eventGateway: events,
        routeChangeGateway: gateway,
        requestIdGenerator: () => 'midtrip_resolved_1234567890',
      )..start();

      events.emit('ride_1', const <String>['proposal_1']);

      await settle();

      expect(controller.pendingProposals.length, 1);

      final result = await controller.acknowledgeDropoffChange(
        proposalId: 'proposal_1',
        decision: RideDropoffChangeDecision.reject,
      );

      expect(result, isNull);
      expect(gateway.ackRequestIds.length, 1);
      expect(controller.pendingProposals, isEmpty);

      expect(
        controller.actionError,
        isA<RideGatewayException>()
            .having((error) => error.code, 'code', 'failed-precondition')
            .having(
              (error) => error.reason,
              'reason',
              'route_change_proposal_already_resolved',
            ),
      );

      controller.dispose();
    },
  );

  test(
    'old ride in-flight proposal completion cannot overwrite new ride action state',
    () async {
      final ride = _RideState(rideId: 'ride_1', status: RideStatus.inProgress);

      final events = _EventGateway();
      final gateway = _Gateway();

      addTearDown(events.close);

      final oldCall = Completer<RideDropoffChangeProposalResult>();

      gateway.proposeHandler = (rideId, newDropoff, requestId) {
        if (rideId == 'ride_1') {
          return oldCall.future;
        }

        return Future<RideDropoffChangeProposalResult>.value(
          _proposal(rideId, 'proposal_new', compatible: true),
        );
      };

      var generatedIds = 0;

      final controller = RideMidtripRouteChangeController(
        rideListenable: ride,
        rideId: () => ride.rideId,
        rideStatus: () => ride.status,
        eventGateway: events,
        routeChangeGateway: gateway,
        requestIdGenerator: () {
          generatedIds += 1;
          return 'midtrip_switch_${generatedIds}_1234567890';
        },
      )..start();

      final oldFuture = controller.proposeDropoffChange(newDropoff: dropoffA);

      await settle();

      expect(controller.isActionInFlight, isTrue);

      ride.set(rideId: 'ride_2', status: RideStatus.inProgress);

      await settle();

      expect(controller.isActionInFlight, isFalse);

      final newResult = await controller.proposeDropoffChange(
        newDropoff: dropoffB,
      );

      expect(newResult?.rideId, 'ride_2');
      expect(controller.actionError, isNull);

      oldCall.completeError(const RideGatewayException('unavailable'));

      expect(await oldFuture, isNull);

      expect(controller.actionError, isNull);
      expect(controller.isActionInFlight, isFalse);

      expect(gateway.proposeRequestIds, <String>[
        'midtrip_switch_1_1234567890',
        'midtrip_switch_2_1234567890',
      ]);

      controller.dispose();
    },
  );
}

const dropoffA = RideLocation(
  latitude: 41.01,
  longitude: 29.01,
  addressLabel: 'Dropoff A',
);

const dropoffB = RideLocation(
  latitude: 41.02,
  longitude: 29.02,
  addressLabel: 'Dropoff B',
);

RideDropoffChangeProposalResult _proposal(
  String rideId,
  String proposalId, {
  required bool compatible,
}) => RideDropoffChangeProposalResult(
  rideId: rideId,
  proposalId: proposalId,
  status: compatible
      ? RideDropoffChangeProposalStatus.appliedCompatible
      : RideDropoffChangeProposalStatus.pendingAcknowledgement,
  compatible: compatible,
  requiresCounterpartyAcknowledgement: !compatible,
  version: 4,
);

RidePendingDropoffChangeProposalResult _pending(
  String rideId,
  String proposalId,
) => RidePendingDropoffChangeProposalResult(
  rideId: rideId,
  proposalId: proposalId,
  status: RideDropoffChangeProposalStatus.pendingAcknowledgement,
  requestedDropoff: dropoffA,
);

RideDropoffChangeAcknowledgementResult _ack(
  String rideId,
  String proposalId,
  RideDropoffChangeDecision decision,
) => RideDropoffChangeAcknowledgementResult(
  rideId: rideId,
  proposalId: proposalId,
  status: decision == RideDropoffChangeDecision.accept
      ? RideDropoffChangeProposalStatus.acceptedIncompatible
      : RideDropoffChangeProposalStatus.rejectedIncompatible,
  decision: decision,
  version: 5,
  yoldaalRegimeEnded: decision == RideDropoffChangeDecision.accept,
);

class _RideState extends ChangeNotifier {
  _RideState({this.rideId, this.status});

  String? rideId;
  RideStatus? status;

  void set({required String? rideId, required RideStatus? status}) {
    this.rideId = rideId;
    this.status = status;
    notifyListeners();
  }
}

class _EventGateway implements RideDropoffChangeProposalEventGateway {
  final Map<String, StreamController<List<String>>> _controllers =
      <String, StreamController<List<String>>>{};

  StreamController<List<String>> _controller(String rideId) => _controllers
      .putIfAbsent(rideId, () => StreamController<List<String>>.broadcast());

  @override
  Stream<List<String>> watchProposalIds({required String rideId}) =>
      _controller(rideId).stream;

  void emit(String rideId, List<String> proposalIds) {
    _controller(rideId).add(proposalIds);
  }

  Future<void> close() async {
    for (final controller in _controllers.values) {
      await controller.close();
    }
  }
}

class _Gateway implements RideMidtripRouteChangeGateway {
  Future<RidePendingDropoffChangeProposalResult> Function(
    String rideId,
    String proposalId,
  )?
  getHandler;

  Future<RideDropoffChangeProposalResult> Function(
    String rideId,
    RideLocation newDropoff,
    String requestId,
  )?
  proposeHandler;

  Future<RideDropoffChangeAcknowledgementResult> Function(
    String rideId,
    String proposalId,
    RideDropoffChangeDecision decision,
    String requestId,
  )?
  ackHandler;

  final List<String> proposeRequestIds = <String>[];

  final List<String> ackRequestIds = <String>[];

  @override
  Future<RidePendingDropoffChangeProposalResult>
  getPendingDropoffChangeProposal({
    required String rideId,
    required String proposalId,
  }) {
    final handler = getHandler;

    if (handler == null) {
      throw StateError('No pending proposal handler configured.');
    }

    return handler(rideId, proposalId);
  }

  @override
  Future<RideDropoffChangeProposalResult> proposeDropoffChange({
    required String rideId,
    required RideLocation newDropoff,
    required String requestId,
  }) {
    proposeRequestIds.add(requestId);

    final handler = proposeHandler;

    if (handler == null) {
      throw StateError('No proposal handler configured.');
    }

    return handler(rideId, newDropoff, requestId);
  }

  @override
  Future<RideDropoffChangeAcknowledgementResult> acknowledgeDropoffChange({
    required String rideId,
    required String proposalId,
    required RideDropoffChangeDecision decision,
    required String requestId,
  }) {
    ackRequestIds.add(requestId);

    final handler = ackHandler;

    if (handler == null) {
      throw StateError('No acknowledgement handler configured.');
    }

    return handler(rideId, proposalId, decision, requestId);
  }
}
