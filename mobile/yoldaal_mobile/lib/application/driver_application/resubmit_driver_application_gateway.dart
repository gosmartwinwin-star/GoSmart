abstract interface class ResubmitDriverApplicationGateway {
  Future<int> resubmit({
    required int expectedSubmissionVersion,
    required String requestId,
  });
}
