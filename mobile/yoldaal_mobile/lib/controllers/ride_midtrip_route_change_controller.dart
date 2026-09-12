import 'dart:async';

import 'package:flutter/foundation.dart';

import '../application/ride/ride_dropoff_change_proposal_event_gateway.dart';
import '../application/ride/ride_gateway.dart';
import '../application/ride/ride_midtrip_route_change_gateway.dart';
import '../domain/ride/canonical_ride.dart';

typedef RideMidtripRouteChangeRideIdReader = String? Function();
typedef RideMidtripRouteChangeStatusReader = RideStatus? Function();
typedef RideMidtripRouteChangeRequestIdGenerator = String Function();

class RideMidtripRouteChangeController extends ChangeNotifier {
  RideMidtripRouteChangeController({
    required Listenable rideListenable,
    required RideMidtripRouteChangeRideIdReader rideId,
    required RideMidtripRouteChangeStatusReader rideStatus,
    required RideDropoffChangeProposalEventGateway eventGateway,
    required RideMidtripRouteChangeGateway routeChangeGateway,
    RideMidtripRouteChangeRequestIdGenerator? requestIdGenerator,
  }) : _rideListenable = rideListenable,
       _rideId = rideId,
       _rideStatus = rideStatus,
       _eventGateway = eventGateway,
       _routeChangeGateway = routeChangeGateway,
       _requestIdGenerator = requestIdGenerator ?? _defaultRequestIdGenerator;

  final Listenable _rideListenable;
  final RideMidtripRouteChangeRideIdReader _rideId;
  final RideMidtripRouteChangeStatusReader _rideStatus;
  final RideDropoffChangeProposalEventGateway _eventGateway;
  final RideMidtripRouteChangeGateway _routeChangeGateway;
  final RideMidtripRouteChangeRequestIdGenerator _requestIdGenerator;

  StreamSubscription<List<String>>? _eventSubscription;

  String? _trackedRideId;
  List<String> _knownProposalIds = const <String>[];

  List<RidePendingDropoffChangeProposalResult> _pendingProposals =
      const <RidePendingDropoffChangeProposalResult>[];

  Object? _lastError;
  Object? _actionError;

  _ProposeAttempt? _proposeAttempt;
  _AcknowledgementAttempt? _acknowledgementAttempt;

  bool _started = false;
  bool _active = false;
  bool _updating = false;
  bool _actionInFlight = false;
  bool _disposed = false;

  int _rideGeneration = 0;
  int _readGeneration = 0;

  static int _requestSequence = 0;

  bool get isActive => _active && !_disposed;

  bool get isUpdating => isActive && _updating;

  bool get isActionInFlight => isActive && _actionInFlight;

  List<RidePendingDropoffChangeProposalResult> get pendingProposals =>
      _pendingProposals;

  Object? get lastError => _lastError;

  Object? get actionError => _actionError;

  void start() {
    if (_started || _disposed) {
      return;
    }

    _started = true;

    _rideListenable.addListener(_syncRideState);

    _syncRideState();
  }

  Future<void> refresh() {
    if (!isActive) {
      return Future<void>.value();
    }

    return _resolveProposalIds(
      _knownProposalIds,
      rideGeneration: _rideGeneration,
    );
  }

  Future<RideDropoffChangeProposalResult?> proposeDropoffChange({
    required RideLocation newDropoff,
  }) async {
    if (!isActive || _actionInFlight) {
      return null;
    }

    final rideId = _trackedRideId;

    if (rideId == null) {
      return null;
    }

    final rideGeneration = _rideGeneration;

    var attempt = _proposeAttempt;

    if (attempt == null ||
        !attempt.matches(rideId: rideId, newDropoff: newDropoff)) {
      attempt = _ProposeAttempt(
        rideId: rideId,
        newDropoff: newDropoff,
        requestId: _requestIdGenerator(),
      );

      _proposeAttempt = attempt;
    }

    _beginAction();

    late final RideDropoffChangeProposalResult result;

    try {
      result = await _routeChangeGateway.proposeDropoffChange(
        rideId: rideId,
        newDropoff: newDropoff,
        requestId: attempt.requestId,
      );
    } catch (error) {
      if (!_isCurrentRideGeneration(rideId, rideGeneration)) {
        return null;
      }

      if (!_shouldRetainRequestId(error)) {
        _proposeAttempt = null;
      }

      _actionError = error;
      _actionInFlight = false;
      _notify();

      return null;
    }

    if (!_isCurrentRideGeneration(rideId, rideGeneration)) {
      return null;
    }

    _proposeAttempt = null;
    _actionError = null;
    _actionInFlight = false;
    _notify();

    return result;
  }

  Future<RideDropoffChangeAcknowledgementResult?> acknowledgeDropoffChange({
    required String proposalId,
    required RideDropoffChangeDecision decision,
  }) async {
    if (!isActive || _actionInFlight) {
      return null;
    }

    final rideId = _trackedRideId;

    if (rideId == null ||
        !_pendingProposals.any(
          (proposal) => proposal.proposalId == proposalId,
        )) {
      return null;
    }

    final rideGeneration = _rideGeneration;

    var attempt = _acknowledgementAttempt;

    if (attempt == null ||
        !attempt.matches(
          rideId: rideId,
          proposalId: proposalId,
          decision: decision,
        )) {
      attempt = _AcknowledgementAttempt(
        rideId: rideId,
        proposalId: proposalId,
        decision: decision,
        requestId: _requestIdGenerator(),
      );

      _acknowledgementAttempt = attempt;
    }

    _beginAction();

    late final RideDropoffChangeAcknowledgementResult result;

    try {
      result = await _routeChangeGateway.acknowledgeDropoffChange(
        rideId: rideId,
        proposalId: proposalId,
        decision: decision,
        requestId: attempt.requestId,
      );
    } catch (error) {
      if (!_isCurrentRideGeneration(rideId, rideGeneration)) {
        return null;
      }

      final alreadyResolved =
          error is RideGatewayException &&
          error.code == 'failed-precondition' &&
          error.reason == 'route_change_proposal_already_resolved';

      if (!_shouldRetainRequestId(error)) {
        _acknowledgementAttempt = null;
      }

      _actionError = error;
      _actionInFlight = false;
      _notify();

      if (alreadyResolved) {
        await refresh();
      }

      return null;
    }

    if (!_isCurrentRideGeneration(rideId, rideGeneration)) {
      return null;
    }

    _acknowledgementAttempt = null;
    _actionError = null;

    await refresh();

    if (!_isCurrentRideGeneration(rideId, rideGeneration)) {
      return null;
    }

    _actionInFlight = false;
    _notify();

    return result;
  }

  void _beginAction() {
    _actionError = null;
    _actionInFlight = true;
    _notify();
  }

  void _syncRideState() {
    if (_disposed) {
      return;
    }

    final rideId = _rideId();
    final status = _rideStatus();

    final shouldTrack =
        rideId != null && rideId.isNotEmpty && status == RideStatus.inProgress;

    if (!shouldTrack) {
      _stopTracking();
      return;
    }

    if (!_active || _trackedRideId != rideId) {
      _beginTracking(rideId);
    }
  }

  void _beginTracking(String rideId) {
    _rideGeneration += 1;
    _readGeneration += 1;

    final oldSubscription = _eventSubscription;
    _eventSubscription = null;

    if (oldSubscription != null) {
      unawaited(oldSubscription.cancel());
    }

    _active = true;
    _trackedRideId = rideId;
    _knownProposalIds = const <String>[];
    _pendingProposals = const <RidePendingDropoffChangeProposalResult>[];
    _lastError = null;

    _clearActionState();

    _updating = true;

    final rideGeneration = _rideGeneration;

    try {
      _eventSubscription = _eventGateway
          .watchProposalIds(rideId: rideId)
          .listen(
            (proposalIds) {
              if (!_isCurrentRideGeneration(rideId, rideGeneration)) {
                return;
              }

              _knownProposalIds = List<String>.unmodifiable(proposalIds);

              unawaited(
                _resolveProposalIds(
                  _knownProposalIds,
                  rideGeneration: rideGeneration,
                ),
              );
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!_isCurrentRideGeneration(rideId, rideGeneration)) {
                return;
              }

              _readGeneration += 1;
              _pendingProposals =
                  const <RidePendingDropoffChangeProposalResult>[];
              _lastError = error;
              _updating = false;
              _notify();
            },
          );
    } catch (error) {
      if (_isCurrentRideGeneration(rideId, rideGeneration)) {
        _pendingProposals = const <RidePendingDropoffChangeProposalResult>[];
        _lastError = error;
        _updating = false;
      }
    }

    _notify();
  }

  Future<void> _resolveProposalIds(
    List<String> proposalIds, {
    required int rideGeneration,
  }) async {
    final rideId = _trackedRideId;

    if (rideId == null || !_isCurrentRideGeneration(rideId, rideGeneration)) {
      return;
    }

    final readGeneration = ++_readGeneration;

    _pendingProposals = const <RidePendingDropoffChangeProposalResult>[];
    _lastError = null;
    _updating = true;
    _notify();

    final uniqueProposalIds = <String>[];
    final seen = <String>{};

    for (final proposalId in proposalIds) {
      if (seen.add(proposalId)) {
        uniqueProposalIds.add(proposalId);
      }
    }

    final pending = <RidePendingDropoffChangeProposalResult>[];

    try {
      for (final proposalId in uniqueProposalIds) {
        late final RidePendingDropoffChangeProposalResult result;

        try {
          result = await _routeChangeGateway.getPendingDropoffChangeProposal(
            rideId: rideId,
            proposalId: proposalId,
          );
        } on RideGatewayException catch (error) {
          if (_isExpectedNonActionable(error)) {
            continue;
          }

          rethrow;
        }

        if (!_isCurrentRead(
          rideId: rideId,
          rideGeneration: rideGeneration,
          readGeneration: readGeneration,
        )) {
          return;
        }

        pending.add(result);
      }
    } catch (error) {
      if (!_isCurrentRead(
        rideId: rideId,
        rideGeneration: rideGeneration,
        readGeneration: readGeneration,
      )) {
        return;
      }

      _pendingProposals = const <RidePendingDropoffChangeProposalResult>[];
      _lastError = error;
      _updating = false;
      _notify();
      return;
    }

    if (!_isCurrentRead(
      rideId: rideId,
      rideGeneration: rideGeneration,
      readGeneration: readGeneration,
    )) {
      return;
    }

    _pendingProposals =
        List<RidePendingDropoffChangeProposalResult>.unmodifiable(pending);
    _lastError = null;
    _updating = false;
    _notify();
  }

  bool _isCurrentRideGeneration(String rideId, int generation) =>
      !_disposed &&
      _active &&
      generation == _rideGeneration &&
      rideId == _trackedRideId;

  bool _isCurrentRead({
    required String rideId,
    required int rideGeneration,
    required int readGeneration,
  }) =>
      _isCurrentRideGeneration(rideId, rideGeneration) &&
      readGeneration == _readGeneration;

  static bool _isExpectedNonActionable(RideGatewayException error) =>
      (error.code == 'permission-denied' &&
          error.reason == 'route_change_counterparty_required') ||
      (error.code == 'failed-precondition' &&
          error.reason == 'route_change_proposal_already_resolved');

  static bool _shouldRetainRequestId(Object error) =>
      error is RideGatewayException && error.code == 'unavailable';

  void _clearActionState() {
    _proposeAttempt = null;
    _acknowledgementAttempt = null;
    _actionError = null;
    _actionInFlight = false;
  }

  void _stopTracking() {
    final hadVisibleState =
        _active ||
        _eventSubscription != null ||
        _knownProposalIds.isNotEmpty ||
        _pendingProposals.isNotEmpty ||
        _lastError != null ||
        _actionError != null ||
        _updating ||
        _actionInFlight;

    _rideGeneration += 1;
    _readGeneration += 1;

    final subscription = _eventSubscription;
    _eventSubscription = null;

    if (subscription != null) {
      unawaited(subscription.cancel());
    }

    _active = false;
    _trackedRideId = null;
    _knownProposalIds = const <String>[];
    _pendingProposals = const <RidePendingDropoffChangeProposalResult>[];
    _lastError = null;
    _updating = false;

    _clearActionState();

    if (hadVisibleState) {
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  static String _defaultRequestIdGenerator() {
    _requestSequence += 1;

    return 'midtrip_${DateTime.now().microsecondsSinceEpoch}_$_requestSequence';
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }

    if (_started) {
      _rideListenable.removeListener(_syncRideState);
    }

    _stopTracking();
    _disposed = true;

    super.dispose();
  }
}

class _ProposeAttempt {
  const _ProposeAttempt({
    required this.rideId,
    required this.newDropoff,
    required this.requestId,
  });

  final String rideId;
  final RideLocation newDropoff;
  final String requestId;

  bool matches({required String rideId, required RideLocation newDropoff}) =>
      this.rideId == rideId &&
      this.newDropoff.latitude == newDropoff.latitude &&
      this.newDropoff.longitude == newDropoff.longitude &&
      this.newDropoff.addressLabel == newDropoff.addressLabel;
}

class _AcknowledgementAttempt {
  const _AcknowledgementAttempt({
    required this.rideId,
    required this.proposalId,
    required this.decision,
    required this.requestId,
  });

  final String rideId;
  final String proposalId;
  final RideDropoffChangeDecision decision;
  final String requestId;

  bool matches({
    required String rideId,
    required String proposalId,
    required RideDropoffChangeDecision decision,
  }) =>
      this.rideId == rideId &&
      this.proposalId == proposalId &&
      this.decision == decision;
}
