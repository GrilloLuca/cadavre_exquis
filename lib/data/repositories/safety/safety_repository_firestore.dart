import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/safety/safety_repository.dart';
import 'package:cadavre_exquisite/domain/models/content_report.dart';
import 'package:cadavre_exquisite/domain/models/email_key.dart';

/// [SafetyRepository] on Firestore. Reports are added to `reports`, which
/// only the Cloud Functions read (`reviewReport` has the AI review the
/// part and removes it if it breaks the terms). The blocked authors' email
/// keys are kept in `userBlocks/{emailKey}.blocked`, readable by its owner
/// only; the document is followed while someone is signed in.
class SafetyRepositoryFirestore extends SafetyRepository {
  SafetyRepositoryFirestore({
    required AuthRepository authRepository,
    FirebaseFirestore? firestore,
  })  : _auth = authRepository,
        _firestoreOverride = firestore {
    _auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  final AuthRepository _auth;
  final FirebaseFirestore? _firestoreOverride;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  /// The user [_subscription] follows, null when signed out.
  String? _followedKey;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;

  Set<String> _blockedKeys = const {};

  @override
  Set<String> get blockedKeys => _blockedKeys;

  DocumentReference<Map<String, dynamic>> _blocksOf(String key) =>
      _firestore.collection('userBlocks').doc(key);

  void _setBlocked(Set<String> keys) {
    if (setEquals(keys, _blockedKeys)) return;
    _blockedKeys = keys;
    notifyListeners();
  }

  void _onAuthChanged() {
    final email = _auth.currentEmail;
    final key = email == null ? null : emailKey(email);
    if (key == _followedKey) return;
    _followedKey = key;
    _subscription?.cancel();
    _subscription = null;
    _setBlocked(const {});
    if (key == null) return;
    _subscription = _blocksOf(key).snapshots().listen((snapshot) {
      final blocked = snapshot.data()?['blocked'];
      _setBlocked(blocked is List ? blocked.whereType<String>().toSet() : {});
    }, onError: (Object _) {
      // E.g. offline at start: nobody is hidden until the next snapshot.
    });
  }

  String _myKey() {
    final email = _auth.currentEmail;
    if (email == null) throw StateError('Not signed in');
    return emailKey(email);
  }

  @override
  Future<void> report({
    required String storyId,
    required String position,
    required ReportReason reason,
  }) async {
    await _firestore.collection('reports').add({
      'storyId': storyId,
      'position': position,
      'reason': reason.name,
      'reporterKey': _myKey(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> block(String email) async {
    final key = emailKey(email);
    final mine = _myKey();
    if (key == mine || _blockedKeys.contains(key)) return;
    // Hidden at once, even before the write (or the snapshot) lands.
    _setBlocked({..._blockedKeys, key});
    await _blocksOf(mine).set({
      'blocked': FieldValue.arrayUnion([key]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> unblock(String key) async {
    final mine = _myKey();
    _setBlocked({..._blockedKeys}..remove(key));
    await _blocksOf(mine).set({
      'blocked': FieldValue.arrayRemove([key]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _subscription?.cancel();
    super.dispose();
  }
}
