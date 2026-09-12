import '../../domain/ride/canonical_ride.dart';

enum RideDropoffChangeProposalStatus {
  appliedCompatible,
  pendingAcknowledgement,
  acceptedIncompatible,
  rejectedIncompatible,
}

enum RideDropoffChangeDecision { accept, reject }

class RideDropoffChangeProposalResult {
  const RideDropoffChangeProposalResult({
    required this.rideId,
    required this.proposalId,
    required this.status,
    required this.compatible,
    required this.requiresCounterpartyAcknowledgement,
    required this.version,
  });

  final String rideId;
  final String proposalId;
  final RideDropoffChangeProposalStatus status;
  final bool compatible;
  final bool requiresCounterpartyAcknowledgement;
  final int version;
}

class RidePendingDropoffChangeProposalResult {
  const RidePendingDropoffChangeProposalResult({
    required this.rideId,
    required this.proposalId,
    required this.status,
    required this.requestedDropoff,
  });

  final String rideId;
  final String proposalId;
  final RideDropoffChangeProposalStatus status;
  final RideLocation requestedDropoff;
}

class RideDropoffChangeAcknowledgementResult {
  const RideDropoffChangeAcknowledgementResult({
    required this.rideId,
    required this.proposalId,
    required this.status,
    required this.decision,
    required this.version,
    required this.yoldaalRegimeEnded,
  });

  final String rideId;
  final String proposalId;
  final RideDropoffChangeProposalStatus status;
  final RideDropoffChangeDecision decision;
  final int version;
  final bool yoldaalRegimeEnded;
}

abstract interface class RideMidtripRouteChangeGateway {
  Future<RideDropoffChangeProposalResult> proposeDropoffChange({
    required String rideId,
    required RideLocation newDropoff,
    required String requestId,
  });

  Future<RidePendingDropoffChangeProposalResult>
  getPendingDropoffChangeProposal({
    required String rideId,
    required String proposalId,
  });
  Future<RideDropoffChangeAcknowledgementResult> acknowledgeDropoffChange({
    required String rideId,
    required String proposalId,
    required RideDropoffChangeDecision decision,
    required String requestId,
  });
}
