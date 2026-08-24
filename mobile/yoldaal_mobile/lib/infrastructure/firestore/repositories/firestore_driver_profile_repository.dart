import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../application/driver_access/driver_profile_repository.dart';
import '../../../domain/driver/driver_profile.dart';
import '../firestore_collections.dart';
import '../mappers/driver_profile_firestore_mapper.dart';

class FirestoreDriverProfileRepository implements DriverProfileRepository {
  final FirebaseFirestore _firestore;

  FirestoreDriverProfileRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  @override
  Future<DriverProfile?> findByAuthenticatedUserId(
    String authenticatedUserId,
  ) async {
    if (authenticatedUserId.trim().isEmpty) {
      throw ArgumentError.value(
        authenticatedUserId,
        'authenticatedUserId',
        'Boş olamaz.',
      );
    }
    final snapshot = await _firestore
        .collection(FirestoreCollections.driverProfiles)
        .where('authUserId', isEqualTo: authenticatedUserId)
        .limit(2)
        .get();
    if (snapshot.docs.isEmpty) return null;
    if (snapshot.docs.length > 1) {
      throw StateError(
        'Kimliği doğrulanmış kullanıcı için birden fazla sürücü profili bulundu.',
      );
    }
    final document = snapshot.docs.single;
    return mapDriverProfileDocument(
      documentId: document.id,
      data: document.data(),
    );
  }
}
