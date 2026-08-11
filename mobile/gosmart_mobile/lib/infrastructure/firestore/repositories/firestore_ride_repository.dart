import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../application/ride/ride_gateway.dart';
import '../../../domain/ride/canonical_ride.dart';

class FirestoreRideRepository implements RideStreamRepository {
  FirestoreRideRepository({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _ride(String id) => _firestore.collection('rides').doc(id);

  @override
  Stream<CanonicalRide> watchRide(String rideId) => _ride(rideId).snapshots().map((snapshot) {
    final data = snapshot.data();
    if (!snapshot.exists || data == null) throw const FormatException('Yolculuk bulunamadı.');
    return CanonicalRide.fromMap(data, rideId: snapshot.id);
  });

  @override
  Future<CanonicalRide> getRide(String rideId) async {
    final snapshot = await _ride(rideId).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) throw const FormatException('Yolculuk bulunamadı.');
    return CanonicalRide.fromMap(data, rideId: snapshot.id);
  }
}
