abstract interface class RideDropoffChangeProposalEventGateway {
  Stream<List<String>> watchProposalIds({required String rideId});
}
