import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../application/driver_access/driver_access_mode_repository.dart';
import '../../../domain/subscription/driver_access_mode.dart';
import '../firestore_collections.dart';

class FirestoreDriverAccessModeRepository
    implements DriverAccessModeRepository {
  final FirebaseFirestore _firestore;

  FirestoreDriverAccessModeRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  @override
  Future<DriverAccessMode> load() async {
    try {
      final document = await _firestore
          .collection(FirestoreCollections.platformConfig)
          .doc('driverAccess')
          .get();

      if (!document.exists) {
        return DriverAccessMode.paid;
      }

      return driverAccessModeFromValue(document.data()?['mode']);
    } catch (_) {
      // Client-side mode lookup is fail-closed. Backend authority
      // remains authoritative for every protected driver operation.
      return DriverAccessMode.paid;
    }
  }
}
