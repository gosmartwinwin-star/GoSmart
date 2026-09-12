import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../application/ride/ride_dropoff_change_proposal_event_gateway.dart';

typedef RideDropoffChangeProposalEventSnapshotReader =
    Stream<List<Map<String, dynamic>>> Function(String rideId);

class FirestoreRideDropoffChangeProposalEventRepository
    implements RideDropoffChangeProposalEventGateway {
  FirestoreRideDropoffChangeProposalEventRepository({
    FirebaseFirestore? firestore,
    RideDropoffChangeProposalEventSnapshotReader? snapshotReader,
  }) : _firestore = firestore,
       _snapshotReader = snapshotReader;

  static const String _eventType = 'rideDropoffChangeProposed';

  final FirebaseFirestore? _firestore;
  final RideDropoffChangeProposalEventSnapshotReader? _snapshotReader;

  @override
  Stream<List<String>> watchProposalIds({required String rideId}) {
    _validatePathId(rideId, 'rideId');

    final injectedReader = _snapshotReader;

    final source = injectedReader != null
        ? injectedReader(rideId)
        : _watchFirestore(rideId);

    return source.map(_parseProposalIds);
  }

  Stream<List<Map<String, dynamic>>> _watchFirestore(String rideId) {
    final firestore = _firestore ?? FirebaseFirestore.instance;

    return firestore
        .collection('rides')
        .doc(rideId)
        .collection('events')
        .where('type', isEqualTo: _eventType)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((document) => document.data())
              .toList(growable: false),
        );
  }

  static List<String> _parseProposalIds(List<Map<String, dynamic>> documents) {
    final proposalIds = <String>[];
    final seen = <String>{};

    for (final data in documents) {
      if (data['type'] != _eventType) {
        throw const FormatException(
          'Invalid ride dropoff change proposal event.',
        );
      }

      final rawProposalId = data['proposalId'];

      if (rawProposalId is! String || !_isPathSafeId(rawProposalId)) {
        throw const FormatException(
          'Invalid ride dropoff change proposal event.',
        );
      }

      if (seen.add(rawProposalId)) {
        proposalIds.add(rawProposalId);
      }
    }

    return List<String>.unmodifiable(proposalIds);
  }

  static void _validatePathId(String value, String fieldName) {
    if (!_isPathSafeId(value)) {
      throw ArgumentError.value(
        value,
        fieldName,
        'must be a non-empty path-safe document id',
      );
    }
  }

  static bool _isPathSafeId(String value) =>
      value.isNotEmpty && value.trim() == value && !value.contains('/');
}
