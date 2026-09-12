import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/ride/ride_dropoff_change_proposal_event_gateway.dart';
import 'package:yoldaal_mobile/application/ride/ride_gateway.dart';
import 'package:yoldaal_mobile/application/ride/ride_midtrip_route_change_gateway.dart';
import 'package:yoldaal_mobile/controllers/ride_midtrip_route_change_controller.dart';
import 'package:yoldaal_mobile/domain/ride/canonical_ride.dart';
import 'package:yoldaal_mobile/widgets/ride/ride_midtrip_route_change_panel.dart';

void main() {
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  Future<void> showPanel(
    WidgetTester tester,
    _Fixture fixture, {
    Future<RideLocation?> Function()? picker,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RideMidtripRouteChangePanel(
            rideId: fixture.ride.rideId ?? 'none',
            controller: fixture.controller,
            selectDropoff:
                picker ??
                () async => const RideLocation(
                  latitude: 41.02,
                  longitude: 29.02,
                  addressLabel: 'Yeni Hedef',
                ),
          ),
        ),
      ),
    );

    await tester.pump();
  }

  testWidgets('panel exact inProgress dışında görünmez', (tester) async {
    final fixture = _Fixture(status: RideStatus.driverArrived);

    addTearDown(fixture.dispose);

    await showPanel(tester, fixture);

    expect(
      find.byKey(const ValueKey('ride-midtrip-panel-ride_1')),
      findsNothing,
    );
  });

  testWidgets(
    'adres seçimi compatible sonucu uygular ve başarı geri bildirimi gösterir',
    (tester) async {
      final fixture = _Fixture();

      addTearDown(fixture.dispose);

      fixture.gateway.proposeHandler = (rideId, dropoff, requestId) async {
        expect(rideId, 'ride_1');
        expect(dropoff.latitude, 41.02);
        expect(dropoff.longitude, 29.02);
        expect(dropoff.addressLabel, 'Yeni Hedef');

        return const RideDropoffChangeProposalResult(
          rideId: 'ride_1',
          proposalId: 'proposal_compatible',
          status: RideDropoffChangeProposalStatus.appliedCompatible,
          compatible: true,
          requiresCounterpartyAcknowledgement: false,
          version: 4,
        );
      };

      await showPanel(tester, fixture);

      await tester.tap(
        find.byKey(const ValueKey('ride-midtrip-select-dropoff-ride_1')),
      );

      await tester.pumpAndSettle();

      expect(fixture.gateway.proposeCalls, 1);
      expect(find.text('Yeni varış noktası uygulandı.'), findsOneWidget);
    },
  );

  testWidgets('incompatible öneri karşı taraf onayı geri bildirimi gösterir', (
    tester,
  ) async {
    final fixture = _Fixture();

    addTearDown(fixture.dispose);

    fixture.gateway.proposeHandler = (rideId, dropoff, requestId) async =>
        const RideDropoffChangeProposalResult(
          rideId: 'ride_1',
          proposalId: 'proposal_pending',
          status: RideDropoffChangeProposalStatus.pendingAcknowledgement,
          compatible: false,
          requiresCounterpartyAcknowledgement: true,
          version: 3,
        );

    await showPanel(tester, fixture);

    await tester.tap(
      find.byKey(const ValueKey('ride-midtrip-select-dropoff-ride_1')),
    );

    await tester.pumpAndSettle();

    expect(
      find.text('Değişiklik karşı tarafın onayına gönderildi.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'birden fazla pending proposal bağımsız gösterilir ve ayrı ayrı ACK edilir',
    (tester) async {
      final fixture = _Fixture();

      addTearDown(fixture.dispose);

      fixture.gateway.pending['proposal_1'] =
          const RidePendingDropoffChangeProposalResult(
            rideId: 'ride_1',
            proposalId: 'proposal_1',
            status: RideDropoffChangeProposalStatus.pendingAcknowledgement,
            requestedDropoff: RideLocation(
              latitude: 41.03,
              longitude: 29.03,
              addressLabel: 'Birinci Hedef',
            ),
          );

      fixture.gateway.pending['proposal_2'] =
          const RidePendingDropoffChangeProposalResult(
            rideId: 'ride_1',
            proposalId: 'proposal_2',
            status: RideDropoffChangeProposalStatus.pendingAcknowledgement,
            requestedDropoff: RideLocation(
              latitude: 41.04,
              longitude: 29.04,
              addressLabel: 'İkinci Hedef',
            ),
          );

      fixture.gateway.ackHandler =
          (rideId, proposalId, decision, requestId) async {
            fixture.gateway.resolved.add(proposalId);

            return RideDropoffChangeAcknowledgementResult(
              rideId: rideId,
              proposalId: proposalId,
              status: decision == RideDropoffChangeDecision.accept
                  ? RideDropoffChangeProposalStatus.acceptedIncompatible
                  : RideDropoffChangeProposalStatus.rejectedIncompatible,
              decision: decision,
              version: 5,
              yoldaalRegimeEnded: decision == RideDropoffChangeDecision.accept,
            );
          };

      await showPanel(tester, fixture);

      fixture.events.emit('ride_1', const <String>['proposal_1', 'proposal_2']);

      await settle(tester);
      await tester.pump();

      expect(find.text('Birinci Hedef'), findsOneWidget);
      expect(find.text('İkinci Hedef'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('ride-midtrip-accept-proposal_1')),
      );

      await tester.pump();
      await settle(tester);
      await tester.pump();
      expect(fixture.controller.isActionInFlight, isFalse);
      expect(fixture.controller.isUpdating, isFalse);

      expect(fixture.gateway.ackCalls.single.proposalId, 'proposal_1');

      expect(
        fixture.gateway.ackCalls.single.decision,
        RideDropoffChangeDecision.accept,
      );

      expect(
        find.byKey(const ValueKey('ride-midtrip-proposal-proposal_1')),
        findsNothing,
      );

      expect(
        find.byKey(const ValueKey('ride-midtrip-proposal-proposal_2')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('ride-midtrip-reject-proposal_2')),
      );

      await tester.pump();
      await settle(tester);
      await tester.pump();
      expect(fixture.controller.isActionInFlight, isFalse);
      expect(fixture.controller.isUpdating, isFalse);

      expect(fixture.gateway.ackCalls.length, 2);
      expect(fixture.gateway.ackCalls.last.proposalId, 'proposal_2');
      expect(
        fixture.gateway.ackCalls.last.decision,
        RideDropoffChangeDecision.reject,
      );

      expect(
        find.byKey(const ValueKey('ride-midtrip-proposal-proposal_2')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'global action in-flight iken propose ve tüm ACK butonları disable olur',
    (tester) async {
      final fixture = _Fixture();

      addTearDown(fixture.dispose);

      fixture.gateway.pending['proposal_1'] =
          const RidePendingDropoffChangeProposalResult(
            rideId: 'ride_1',
            proposalId: 'proposal_1',
            status: RideDropoffChangeProposalStatus.pendingAcknowledgement,
            requestedDropoff: RideLocation(
              latitude: 41.03,
              longitude: 29.03,
              addressLabel: 'Bekleyen Hedef',
            ),
          );

      final proposalCompleter = Completer<RideDropoffChangeProposalResult>();

      fixture.gateway.proposeHandler = (rideId, dropoff, requestId) =>
          proposalCompleter.future;

      await showPanel(tester, fixture);

      fixture.events.emit('ride_1', const <String>['proposal_1']);

      await settle(tester);
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey('ride-midtrip-select-dropoff-ride_1')),
      );

      await tester.pump();
      await settle(tester);
      await tester.pump();

      final selectButton = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('ride-midtrip-select-dropoff-ride_1')),
      );

      final rejectButton = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('ride-midtrip-reject-proposal_1')),
      );

      final acceptButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('ride-midtrip-accept-proposal_1')),
      );

      expect(selectButton.onPressed, isNull);
      expect(rejectButton.onPressed, isNull);
      expect(acceptButton.onPressed, isNull);

      proposalCompleter.complete(
        const RideDropoffChangeProposalResult(
          rideId: 'ride_1',
          proposalId: 'proposal_compatible',
          status: RideDropoffChangeProposalStatus.appliedCompatible,
          compatible: true,
          requiresCounterpartyAcknowledgement: false,
          version: 4,
        ),
      );

      await tester.pumpAndSettle();

      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('ride-midtrip-select-dropoff-ride_1')),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('discovery hatası generic gösterilir ve refresh yüzeyi sunulur', (
    tester,
  ) async {
    final fixture = _Fixture();

    addTearDown(fixture.dispose);

    await showPanel(tester, fixture);

    fixture.events.error('ride_1', StateError('private backend detail'));

    await settle(tester);
    await tester.pump();

    expect(find.text('Bekleyen değişiklikler yüklenemedi.'), findsOneWidget);

    expect(find.textContaining('private backend detail'), findsNothing);

    expect(
      find.byKey(const ValueKey('ride-midtrip-refresh-ride_1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('ride-midtrip-refresh-ride_1')));

    await tester.pumpAndSettle();

    expect(find.text('Bekleyen değişiklikler yüklenemedi.'), findsNothing);
  });

  testWidgets(
    'action hatası backend ayrıntısı sızdırmadan generic retry mesajı gösterir',
    (tester) async {
      final fixture = _Fixture();

      addTearDown(fixture.dispose);

      fixture.gateway.proposeHandler = (rideId, dropoff, requestId) async {
        throw const RideGatewayException(
          'unavailable',
          reason: 'private_internal_reason',
        );
      };

      await showPanel(tester, fixture);

      await tester.tap(
        find.byKey(const ValueKey('ride-midtrip-select-dropoff-ride_1')),
      );

      await tester.pumpAndSettle();

      expect(
        find.text(
          'Varış noktası değişikliği tamamlanamadı. '
          'Lütfen tekrar deneyin.',
        ),
        findsOneWidget,
      );

      expect(find.textContaining('private_internal_reason'), findsNothing);
    },
  );
}

class _Fixture {
  _Fixture({RideStatus status = RideStatus.inProgress})
    : ride = _RideState(rideId: 'ride_1', status: status) {
    controller = RideMidtripRouteChangeController(
      rideListenable: ride,
      rideId: () => ride.rideId,
      rideStatus: () => ride.status,
      eventGateway: events,
      routeChangeGateway: gateway,
      requestIdGenerator: _requestId,
    )..start();
  }

  final _RideState ride;
  final _EventGateway events = _EventGateway();
  final _Gateway gateway = _Gateway();

  late final RideMidtripRouteChangeController controller;

  int _requestSequence = 0;

  String _requestId() {
    _requestSequence += 1;
    return 'panel_request_${_requestSequence}_1234567890';
  }

  Future<void> dispose() async {
    controller.dispose();
    ride.dispose();
    await events.close();
  }
}

class _RideState extends ChangeNotifier {
  _RideState({required this.rideId, required this.status});

  String? rideId;
  RideStatus? status;
}

class _EventGateway implements RideDropoffChangeProposalEventGateway {
  final Map<String, StreamController<List<String>>> _controllers =
      <String, StreamController<List<String>>>{};

  StreamController<List<String>> _controller(String rideId) => _controllers
      .putIfAbsent(rideId, () => StreamController<List<String>>.broadcast());

  @override
  Stream<List<String>> watchProposalIds({required String rideId}) async* {
    // Firestore query snapshots deliver an initial snapshot even when
    // the result set is empty. Mirror that production behavior so the
    // controller can finish its initial discovery state.
    yield const <String>[];
    yield* _controller(rideId).stream;
  }

  void emit(String rideId, List<String> proposalIds) {
    _controller(rideId).add(proposalIds);
  }

  void error(String rideId, Object error) {
    _controller(rideId).addError(error);
  }

  Future<void> close() async {
    for (final controller in _controllers.values) {
      await controller.close();
    }
  }
}

class _AckCall {
  const _AckCall({required this.proposalId, required this.decision});

  final String proposalId;
  final RideDropoffChangeDecision decision;
}

class _Gateway implements RideMidtripRouteChangeGateway {
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

  final Map<String, RidePendingDropoffChangeProposalResult> pending =
      <String, RidePendingDropoffChangeProposalResult>{};

  final Set<String> resolved = <String>{};

  final List<_AckCall> ackCalls = <_AckCall>[];

  int proposeCalls = 0;

  @override
  Future<RidePendingDropoffChangeProposalResult>
  getPendingDropoffChangeProposal({
    required String rideId,
    required String proposalId,
  }) async {
    if (resolved.contains(proposalId)) {
      throw const RideGatewayException(
        'failed-precondition',
        reason: 'route_change_proposal_already_resolved',
      );
    }

    final result = pending[proposalId];

    if (result == null) {
      throw const RideGatewayException('not-found');
    }

    return result;
  }

  @override
  Future<RideDropoffChangeProposalResult> proposeDropoffChange({
    required String rideId,
    required RideLocation newDropoff,
    required String requestId,
  }) {
    proposeCalls += 1;

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
    ackCalls.add(_AckCall(proposalId: proposalId, decision: decision));

    final handler = ackHandler;

    if (handler == null) {
      throw StateError('No acknowledgement handler configured.');
    }

    return handler(rideId, proposalId, decision, requestId);
  }
}
