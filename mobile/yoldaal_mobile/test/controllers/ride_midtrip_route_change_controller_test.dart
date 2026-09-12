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
    'controller only subscribes while exact ride status is inProgress',
    () async {
      final ride = _RideState(
        rideId: 'ride_1',
        status: RideStatus.driverArrived,
      );

      final events = _EventGateway();
      final routeChanges = _RouteChangeGateway();

      addTearDown(events.close);

      final controller = RideMidtripRouteChangeController(
        rideListenable: ride,
        rideId: () => ride.rideId,
        rideStatus: () => ride.status,
        eventGateway: events,
        routeChangeGateway: routeChanges,
      )..start();

      expect(events.watchCalls, 0);
      expect(controller.isActive, isFalse);

      ride.set(rideId: 'ride_1', status: RideStatus.inProgress);

      await settle();

      expect(events.watchCalls, 1);
      expect(controller.isActive, isTrue);
      expect(controller.isUpdating, isTrue);

      events.emit('ride_1', const <String>[]);

      await settle();

      expect(controller.isUpdating, isFalse);
      expect(controller.pendingProposals, isEmpty);

      ride.set(rideId: 'ride_1', status: RideStatus.completed);

      await settle();

      expect(controller.isActive, isFalse);
      expect(events.cancelledRideIds, contains('ride_1'));

      controller.dispose();
    },
  );

  test(
    'counterparty pending proposals are exposed while proposer and resolved proposals are ignored',
    () async {
      final ride = _RideState(rideId: 'ride_1', status: RideStatus.inProgress);

      final events = _EventGateway();
      final routeChanges = _RouteChangeGateway();

      addTearDown(events.close);

      routeChanges.handler = (rideId, proposalId) async {
        switch (proposalId) {
          case 'pending_1':
            return _pending(rideId, proposalId, 'Birinci hedef');

          case 'proposer_1':
            throw const RideGatewayException(
              'permission-denied',
              reason: 'route_change_counterparty_required',
            );

          case 'resolved_1':
            throw const RideGatewayException(
              'failed-precondition',
              reason: 'route_change_proposal_already_resolved',
            );

          case 'pending_2':
            return _pending(rideId, proposalId, 'İkinci hedef');
        }

        throw StateError('Unexpected proposal: $proposalId');
      };

      final controller = RideMidtripRouteChangeController(
        rideListenable: ride,
        rideId: () => ride.rideId,
        rideStatus: () => ride.status,
        eventGateway: events,
        routeChangeGateway: routeChanges,
      )..start();

      events.emit('ride_1', const <String>[
        'pending_1',
        'proposer_1',
        'resolved_1',
        'pending_2',
      ]);

      await settle();

      expect(routeChanges.calls, const <String>[
        'ride_1:pending_1',
        'ride_1:proposer_1',
        'ride_1:resolved_1',
        'ride_1:pending_2',
      ]);

      expect(
        controller.pendingProposals
            .map((proposal) => proposal.proposalId)
            .toList(),
        const <String>['pending_1', 'pending_2'],
      );

      expect(controller.lastError, isNull);
      expect(controller.isUpdating, isFalse);

      controller.dispose();
    },
  );

  test('multiple simultaneous pending proposals remain separate', () async {
    final ride = _RideState(rideId: 'ride_1', status: RideStatus.inProgress);

    final events = _EventGateway();
    final routeChanges = _RouteChangeGateway();

    addTearDown(events.close);

    routeChanges.handler = (rideId, proposalId) async =>
        _pending(rideId, proposalId, proposalId);

    final controller = RideMidtripRouteChangeController(
      rideListenable: ride,
      rideId: () => ride.rideId,
      rideStatus: () => ride.status,
      eventGateway: events,
      routeChangeGateway: routeChanges,
    )..start();

    events.emit('ride_1', const <String>[
      'proposal_a',
      'proposal_b',
      'proposal_c',
    ]);

    await settle();

    expect(controller.pendingProposals.length, 3);

    expect(
      controller.pendingProposals
          .map((proposal) => proposal.proposalId)
          .toList(),
      const <String>['proposal_a', 'proposal_b', 'proposal_c'],
    );

    controller.dispose();
  });

  test(
    'unexpected getter failure clears actionable proposal state fail closed',
    () async {
      final ride = _RideState(rideId: 'ride_1', status: RideStatus.inProgress);

      final events = _EventGateway();
      final routeChanges = _RouteChangeGateway();

      addTearDown(events.close);

      routeChanges.handler = (rideId, proposalId) async =>
          _pending(rideId, proposalId, 'İlk hedef');

      final controller = RideMidtripRouteChangeController(
        rideListenable: ride,
        rideId: () => ride.rideId,
        rideStatus: () => ride.status,
        eventGateway: events,
        routeChangeGateway: routeChanges,
      )..start();

      events.emit('ride_1', const <String>['proposal_1']);

      await settle();

      expect(controller.pendingProposals.length, 1);

      routeChanges.handler = (rideId, proposalId) async {
        if (proposalId == 'proposal_2') {
          throw const RideGatewayException('unavailable');
        }

        return _pending(rideId, proposalId, 'Yeniden doğrulanan hedef');
      };

      events.emit('ride_1', const <String>['proposal_1', 'proposal_2']);

      await settle();

      expect(controller.pendingProposals, isEmpty);

      expect(
        controller.lastError,
        isA<RideGatewayException>().having(
          (error) => error.code,
          'code',
          'unavailable',
        ),
      );

      expect(controller.isUpdating, isFalse);

      controller.dispose();
    },
  );

  test(
    'event stream failure clears actionable proposal state fail closed',
    () async {
      final ride = _RideState(rideId: 'ride_1', status: RideStatus.inProgress);

      final events = _EventGateway();
      final routeChanges = _RouteChangeGateway();

      addTearDown(events.close);

      routeChanges.handler = (rideId, proposalId) async =>
          _pending(rideId, proposalId, 'Hedef');

      final controller = RideMidtripRouteChangeController(
        rideListenable: ride,
        rideId: () => ride.rideId,
        rideStatus: () => ride.status,
        eventGateway: events,
        routeChangeGateway: routeChanges,
      )..start();

      events.emit('ride_1', const <String>['proposal_1']);

      await settle();

      expect(controller.pendingProposals.length, 1);

      events.emitError('ride_1', StateError('event read failed'));

      await settle();

      expect(controller.pendingProposals, isEmpty);
      expect(controller.lastError, isA<StateError>());
      expect(controller.isUpdating, isFalse);

      controller.dispose();
    },
  );

  test(
    'manual refresh revalidates known ids and removes newly resolved proposal',
    () async {
      final ride = _RideState(rideId: 'ride_1', status: RideStatus.inProgress);

      final events = _EventGateway();
      final routeChanges = _RouteChangeGateway();

      addTearDown(events.close);

      var resolved = false;

      routeChanges.handler = (rideId, proposalId) async {
        if (resolved) {
          throw const RideGatewayException(
            'failed-precondition',
            reason: 'route_change_proposal_already_resolved',
          );
        }

        return _pending(rideId, proposalId, 'Bekleyen hedef');
      };

      final controller = RideMidtripRouteChangeController(
        rideListenable: ride,
        rideId: () => ride.rideId,
        rideStatus: () => ride.status,
        eventGateway: events,
        routeChangeGateway: routeChanges,
      )..start();

      events.emit('ride_1', const <String>['proposal_1']);

      await settle();

      expect(controller.pendingProposals.length, 1);

      resolved = true;

      await controller.refresh();

      expect(controller.pendingProposals, isEmpty);
      expect(controller.lastError, isNull);

      controller.dispose();
    },
  );

  test(
    'newer event snapshot wins over stale in-flight getter result',
    () async {
      final ride = _RideState(rideId: 'ride_1', status: RideStatus.inProgress);

      final events = _EventGateway();
      final routeChanges = _RouteChangeGateway();

      addTearDown(events.close);

      final staleRead = Completer<RidePendingDropoffChangeProposalResult>();

      routeChanges.handler = (rideId, proposalId) {
        if (proposalId == 'proposal_old') {
          return staleRead.future;
        }

        return Future<RidePendingDropoffChangeProposalResult>.value(
          _pending(rideId, proposalId, 'Yeni hedef'),
        );
      };

      final controller = RideMidtripRouteChangeController(
        rideListenable: ride,
        rideId: () => ride.rideId,
        rideStatus: () => ride.status,
        eventGateway: events,
        routeChangeGateway: routeChanges,
      )..start();

      events.emit('ride_1', const <String>['proposal_old']);

      await settle();

      events.emit('ride_1', const <String>['proposal_new']);

      await settle();

      expect(
        controller.pendingProposals
            .map((proposal) => proposal.proposalId)
            .toList(),
        const <String>['proposal_new'],
      );

      staleRead.complete(_pending('ride_1', 'proposal_old', 'Eski hedef'));

      await settle();

      expect(
        controller.pendingProposals
            .map((proposal) => proposal.proposalId)
            .toList(),
        const <String>['proposal_new'],
      );

      controller.dispose();
    },
  );

  test(
    'ride switch cancels old discovery and stale old ride result cannot win',
    () async {
      final ride = _RideState(rideId: 'ride_1', status: RideStatus.inProgress);

      final events = _EventGateway();
      final routeChanges = _RouteChangeGateway();

      addTearDown(events.close);

      final oldRead = Completer<RidePendingDropoffChangeProposalResult>();

      routeChanges.handler = (rideId, proposalId) {
        if (rideId == 'ride_1') {
          return oldRead.future;
        }

        return Future<RidePendingDropoffChangeProposalResult>.value(
          _pending(rideId, proposalId, 'Yeni yolculuk hedefi'),
        );
      };

      final controller = RideMidtripRouteChangeController(
        rideListenable: ride,
        rideId: () => ride.rideId,
        rideStatus: () => ride.status,
        eventGateway: events,
        routeChangeGateway: routeChanges,
      )..start();

      events.emit('ride_1', const <String>['proposal_old']);

      await settle();

      ride.set(rideId: 'ride_2', status: RideStatus.inProgress);

      await settle();

      expect(events.cancelledRideIds, contains('ride_1'));

      events.emit('ride_2', const <String>['proposal_new']);

      await settle();

      expect(controller.pendingProposals.single.proposalId, 'proposal_new');

      oldRead.complete(
        _pending('ride_1', 'proposal_old', 'Eski yolculuk hedefi'),
      );

      await settle();

      expect(controller.pendingProposals.single.proposalId, 'proposal_new');

      controller.dispose();
    },
  );
}

RidePendingDropoffChangeProposalResult _pending(
  String rideId,
  String proposalId,
  String addressLabel,
) => RidePendingDropoffChangeProposalResult(
  rideId: rideId,
  proposalId: proposalId,
  status: RideDropoffChangeProposalStatus.pendingAcknowledgement,
  requestedDropoff: RideLocation(
    latitude: 41.0082,
    longitude: 28.9784,
    addressLabel: addressLabel,
  ),
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
  int watchCalls = 0;

  final Map<String, StreamController<List<String>>> _controllers =
      <String, StreamController<List<String>>>{};

  final Set<String> cancelledRideIds = <String>{};

  StreamController<List<String>> _controller(String rideId) =>
      _controllers.putIfAbsent(
        rideId,
        () => StreamController<List<String>>.broadcast(
          onCancel: () {
            cancelledRideIds.add(rideId);
          },
        ),
      );

  @override
  Stream<List<String>> watchProposalIds({required String rideId}) {
    watchCalls += 1;

    return _controller(rideId).stream;
  }

  void emit(String rideId, List<String> proposalIds) {
    _controller(rideId).add(proposalIds);
  }

  void emitError(String rideId, Object error) {
    _controller(rideId).addError(error);
  }

  Future<void> close() async {
    for (final controller in _controllers.values) {
      await controller.close();
    }
  }
}

class _RouteChangeGateway implements RideMidtripRouteChangeGateway {
  Future<RidePendingDropoffChangeProposalResult> Function(
    String rideId,
    String proposalId,
  )?
  handler;

  final List<String> calls = <String>[];

  @override
  Future<RidePendingDropoffChangeProposalResult>
  getPendingDropoffChangeProposal({
    required String rideId,
    required String proposalId,
  }) {
    calls.add('$rideId:$proposalId');

    final currentHandler = handler;

    if (currentHandler == null) {
      throw StateError('No pending proposal handler configured.');
    }

    return currentHandler(rideId, proposalId);
  }

  @override
  Future<RideDropoffChangeProposalResult> proposeDropoffChange({
    required String rideId,
    required RideLocation newDropoff,
    required String requestId,
  }) {
    throw UnsupportedError(
      'proposeDropoffChange is outside R25 controller scope.',
    );
  }

  @override
  Future<RideDropoffChangeAcknowledgementResult> acknowledgeDropoffChange({
    required String rideId,
    required String proposalId,
    required RideDropoffChangeDecision decision,
    required String requestId,
  }) {
    throw UnsupportedError(
      'acknowledgeDropoffChange is outside R25 controller scope.',
    );
  }
}
