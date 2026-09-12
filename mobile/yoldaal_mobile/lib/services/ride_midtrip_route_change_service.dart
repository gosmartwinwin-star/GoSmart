import '../application/ride/ride_gateway.dart';
import '../application/ride/ride_midtrip_route_change_gateway.dart';
import '../core/firebase/firebase_functions_registry.dart';
import '../domain/ride/canonical_ride.dart';
import 'ride_lifecycle_service.dart';

class RideMidtripRouteChangeService implements RideMidtripRouteChangeGateway {
  RideMidtripRouteChangeService({RideCallableInvoker? invoker})
    : _invoker = invoker ?? FirebaseRideCallableInvoker();

  final RideCallableInvoker _invoker;

  static const Set<String> _proposalResponseKeys = <String>{
    'rideId',
    'proposalId',
    'status',
    'compatible',
    'requiresCounterpartyAcknowledgement',
    'version',
  };

  static const Set<String> _pendingReadResponseKeys = <String>{
    'rideId',
    'proposalId',
    'status',
    'requestedDropoff',
  };

  static const Set<String> _locationResponseKeys = <String>{
    'latitude',
    'longitude',
    'addressLabel',
  };
  static const Set<String> _ackResponseKeys = <String>{
    'rideId',
    'proposalId',
    'status',
    'decision',
    'version',
    'yoldaalRegimeEnded',
  };

  @override
  Future<RideDropoffChangeProposalResult> proposeDropoffChange({
    required String rideId,
    required RideLocation newDropoff,
    required String requestId,
  }) async {
    _validatePathId(rideId, 'rideId');
    final normalizedDropoff = _validateLocation(newDropoff);
    _validateRequestId(requestId);

    final data = await _call(
      FirebaseFunctionsRegistry.proposeRideDropoffChange,
      <String, dynamic>{
        'rideId': rideId,
        'newDropoff': <String, dynamic>{
          'latitude': normalizedDropoff.latitude,
          'longitude': normalizedDropoff.longitude,
          'addressLabel': normalizedDropoff.addressLabel,
        },
        'requestId': requestId,
      },
    );

    if (!_hasExactKeys(data, _proposalResponseKeys)) {
      throw const RideGatewayException('invalid-response');
    }

    final rawRideId = data['rideId'];
    final rawProposalId = data['proposalId'];
    final rawStatus = data['status'];
    final rawCompatible = data['compatible'];
    final rawRequiresAck = data['requiresCounterpartyAcknowledgement'];
    final rawVersion = data['version'];

    if (rawRideId != rideId ||
        rawProposalId is! String ||
        !_isValidPathId(rawProposalId) ||
        rawStatus is! String ||
        rawCompatible is! bool ||
        rawRequiresAck is! bool ||
        rawVersion is! int ||
        rawVersion < 1) {
      throw const RideGatewayException('invalid-response');
    }

    final status = _parseProposalStatus(rawStatus);

    final expectedStatus = rawCompatible
        ? RideDropoffChangeProposalStatus.appliedCompatible
        : RideDropoffChangeProposalStatus.pendingAcknowledgement;

    if (status != expectedStatus || rawRequiresAck != !rawCompatible) {
      throw const RideGatewayException('invalid-response');
    }

    return RideDropoffChangeProposalResult(
      rideId: rideId,
      proposalId: rawProposalId,
      status: status,
      compatible: rawCompatible,
      requiresCounterpartyAcknowledgement: rawRequiresAck,
      version: rawVersion,
    );
  }

  @override
  Future<RidePendingDropoffChangeProposalResult>
  getPendingDropoffChangeProposal({
    required String rideId,
    required String proposalId,
  }) async {
    _validatePathId(rideId, 'rideId');
    _validatePathId(proposalId, 'proposalId');

    final data = await _call(
      FirebaseFunctionsRegistry.getPendingRideDropoffChangeProposal,
      <String, dynamic>{'rideId': rideId, 'proposalId': proposalId},
    );

    if (!_hasExactKeys(data, _pendingReadResponseKeys)) {
      throw const RideGatewayException('invalid-response');
    }

    final rawRideId = data['rideId'];
    final rawProposalId = data['proposalId'];
    final rawStatus = data['status'];

    if (rawRideId != rideId ||
        rawProposalId != proposalId ||
        rawStatus !=
            RideDropoffChangeProposalStatus.pendingAcknowledgement.name) {
      throw const RideGatewayException('invalid-response');
    }

    final requestedDropoff = _parseResponseLocation(data['requestedDropoff']);

    return RidePendingDropoffChangeProposalResult(
      rideId: rideId,
      proposalId: proposalId,
      status: RideDropoffChangeProposalStatus.pendingAcknowledgement,
      requestedDropoff: requestedDropoff,
    );
  }

  @override
  Future<RideDropoffChangeAcknowledgementResult> acknowledgeDropoffChange({
    required String rideId,
    required String proposalId,
    required RideDropoffChangeDecision decision,
    required String requestId,
  }) async {
    _validatePathId(rideId, 'rideId');
    _validatePathId(proposalId, 'proposalId');
    _validateRequestId(requestId);

    final data = await _call(
      FirebaseFunctionsRegistry.acknowledgeRideDropoffChange,
      <String, dynamic>{
        'rideId': rideId,
        'proposalId': proposalId,
        'decision': decision.name,
        'requestId': requestId,
      },
    );

    if (!_hasExactKeys(data, _ackResponseKeys)) {
      throw const RideGatewayException('invalid-response');
    }

    final rawRideId = data['rideId'];
    final rawProposalId = data['proposalId'];
    final rawStatus = data['status'];
    final rawDecision = data['decision'];
    final rawVersion = data['version'];
    final rawRegimeEnded = data['yoldaalRegimeEnded'];

    if (rawRideId != rideId ||
        rawProposalId != proposalId ||
        rawStatus is! String ||
        rawDecision is! String ||
        rawVersion is! int ||
        rawVersion < 1 ||
        rawRegimeEnded is! bool) {
      throw const RideGatewayException('invalid-response');
    }

    final status = _parseProposalStatus(rawStatus);

    final responseDecision = _parseDecision(rawDecision);

    if (responseDecision != decision) {
      throw const RideGatewayException('invalid-response');
    }

    final expectedStatus = decision == RideDropoffChangeDecision.accept
        ? RideDropoffChangeProposalStatus.acceptedIncompatible
        : RideDropoffChangeProposalStatus.rejectedIncompatible;

    final expectedRegimeEnded = decision == RideDropoffChangeDecision.accept;

    if (status != expectedStatus || rawRegimeEnded != expectedRegimeEnded) {
      throw const RideGatewayException('invalid-response');
    }

    return RideDropoffChangeAcknowledgementResult(
      rideId: rideId,
      proposalId: proposalId,
      status: status,
      decision: responseDecision,
      version: rawVersion,
      yoldaalRegimeEnded: rawRegimeEnded,
    );
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> payload,
  ) async {
    try {
      return await _invoker.call(name, payload);
    } on RideGatewayException {
      rethrow;
    } catch (_) {
      throw const RideGatewayException('invalid-response');
    }
  }

  static bool _hasExactKeys(Map<String, dynamic> data, Set<String> expected) =>
      data.length == expected.length && expected.every(data.containsKey);

  static RideDropoffChangeProposalStatus _parseProposalStatus(String value) {
    for (final status in RideDropoffChangeProposalStatus.values) {
      if (status.name == value) {
        return status;
      }
    }

    throw const RideGatewayException('invalid-response');
  }

  static RideDropoffChangeDecision _parseDecision(String value) {
    for (final decision in RideDropoffChangeDecision.values) {
      if (decision.name == value) {
        return decision;
      }
    }

    throw const RideGatewayException('invalid-response');
  }

  static RideLocation _parseResponseLocation(Object? value) {
    if (value is! Map) {
      throw const RideGatewayException('invalid-response');
    }

    late final Map<String, dynamic> data;

    try {
      data = Map<String, dynamic>.from(value);
    } catch (_) {
      throw const RideGatewayException('invalid-response');
    }

    if (!_hasExactKeys(data, _locationResponseKeys)) {
      throw const RideGatewayException('invalid-response');
    }

    final rawLatitude = data['latitude'];
    final rawLongitude = data['longitude'];
    final rawAddressLabel = data['addressLabel'];

    if (rawLatitude is! num ||
        rawLongitude is! num ||
        rawAddressLabel is! String) {
      throw const RideGatewayException('invalid-response');
    }

    final latitude = rawLatitude.toDouble();
    final longitude = rawLongitude.toDouble();
    final addressLabel = rawAddressLabel.trim();

    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180 ||
        addressLabel.isEmpty ||
        addressLabel != rawAddressLabel) {
      throw const RideGatewayException('invalid-response');
    }

    return RideLocation(
      latitude: latitude,
      longitude: longitude,
      addressLabel: addressLabel,
    );
  }

  static RideLocation _validateLocation(RideLocation value) {
    if (!value.latitude.isFinite ||
        !value.longitude.isFinite ||
        value.latitude < -90 ||
        value.latitude > 90 ||
        value.longitude < -180 ||
        value.longitude > 180) {
      throw ArgumentError.value(
        value,
        'newDropoff',
        'Invalid ride location coordinates.',
      );
    }

    final addressLabel = value.addressLabel.trim();

    if (addressLabel.isEmpty) {
      throw ArgumentError.value(
        value,
        'newDropoff',
        'Ride location address must not be empty.',
      );
    }

    return RideLocation(
      latitude: value.latitude,
      longitude: value.longitude,
      addressLabel: addressLabel,
    );
  }

  static bool _isValidPathId(String value) =>
      value.isNotEmpty &&
      value.length <= 128 &&
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);

  static void _validatePathId(String value, String fieldName) {
    if (!_isValidPathId(value)) {
      throw ArgumentError.value(value, fieldName, 'Invalid path id.');
    }
  }

  static void _validateRequestId(String value) {
    if (value.length < 16 ||
        value.length > 128 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw ArgumentError.value(value, 'requestId', 'Invalid request id.');
    }
  }
}
