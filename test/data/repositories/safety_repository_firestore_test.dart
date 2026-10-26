import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/data/repositories/safety/safety_repository_firestore.dart';
import 'package:cadavre_exquisite/domain/models/content_report.dart';

import '../../../testing/fakes/repositories/fake_auth_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FakeAuthRepository auth;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = FakeAuthRepository(email: 'Me@Example.com');
  });

  SafetyRepositoryFirestore create() =>
      SafetyRepositoryFirestore(authRepository: auth, firestore: firestore);

  test('loads the blocked keys of the signed-in user', () async {
    await firestore.doc('userBlocks/me@example.com').set({
      'blocked': ['troll@example.com'],
    });

    final repository = create();
    await pumpEventQueue();

    expect(repository.blockedKeys, {'troll@example.com'});
  });

  test('block stores the email key, unblock removes it', () async {
    final repository = create();
    await pumpEventQueue();

    await repository.block('Troll@Example.com');
    expect(repository.blockedKeys, {'troll@example.com'});
    await pumpEventQueue();
    var doc = await firestore.doc('userBlocks/me@example.com').get();
    expect(doc.get('blocked'), ['troll@example.com']);

    await repository.unblock('troll@example.com');
    await pumpEventQueue();
    expect(repository.blockedKeys, isEmpty);
    doc = await firestore.doc('userBlocks/me@example.com').get();
    expect(doc.get('blocked'), isEmpty);
  });

  test('never blocks the user themselves', () async {
    final repository = create();

    await repository.block('me@example.com');

    expect(repository.blockedKeys, isEmpty);
  });

  test('signing out forgets the blocked keys', () async {
    await firestore.doc('userBlocks/me@example.com').set({
      'blocked': ['troll@example.com'],
    });
    final repository = create();
    await pumpEventQueue();

    await auth.signOut();

    expect(repository.blockedKeys, isEmpty);
  });

  test('report stores the part, the reason and the reporter', () async {
    final repository = create();

    await repository.report(
      storyId: 's1',
      position: 'sviluppo1',
      reason: ReportReason.offensive,
    );
    await pumpEventQueue();

    final reports = await firestore.collection('reports').get();
    expect(reports.docs, hasLength(1));
    // One per player and part, see firestore.rules.
    expect(reports.docs.single.id, 's1_sviluppo1_me@example.com');
    final data = reports.docs.single.data();
    expect(data['storyId'], 's1');
    expect(data['position'], 'sviluppo1');
    expect(data['reason'], 'offensive');
    expect(data['reporterKey'], 'me@example.com');
    expect(data.containsKey('createdAt'), isTrue);
  });
}
