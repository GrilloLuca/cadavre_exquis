import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:cadavre_exquisite/data/repositories/feature_flags/feature_flags_repository.dart';

/// [FeatureFlagsRepository] on the public `appConfig/flags` document, which
/// signed-out users can read (firestore.rules) and only the console writes.
class FeatureFlagsRepositoryFirestore implements FeatureFlagsRepository {
  FeatureFlagsRepositoryFirestore({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> get _flags =>
      _firestore.collection('appConfig').doc('flags');

  @override
  Stream<bool> watchEmailLoginOnIos() => _flags
      .snapshots()
      .map((doc) => doc.data()?['iosEmailLogin'] == true)
      // Offline or denied: keep the button hidden rather than fail.
      .handleError((Object _) {});
}
