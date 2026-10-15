import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/domain/models/story_language.dart';

// Converts between the `stories/{id}` Firestore documents and the domain
// Story/StoryPart, so Firestore types (Timestamp, snapshots) stay in the
// data layer.

/// The [Story] stored in [doc]. Stories created before language rooms have
/// no `language` and count as [kDefaultStoryLanguage]; stories without
/// `keywords` (never extracted, or legacy) have none.
Story storyFromSnapshot(DocumentSnapshot doc) {
  final data = doc.data() as Map<String, dynamic>;
  return Story(
    id: doc.id,
    status: data['status'] as String,
    currentPosition: data['currentPosition'] as String,
    parts: (data['parts'] as List<dynamic>? ?? [])
        .map((p) => storyPartFromMap(p as Map<String, dynamic>))
        .toList(),
    lockedBy: data['lockedBy'] as String?,
    lockedAt: (data['lockedAt'] as Timestamp?)?.toDate(),
    language: data['language'] as String? ?? kDefaultStoryLanguage,
    roomId: data['roomId'] as String?,
    title: data['title'] as String?,
    mature: data['mature'] as bool?,
    keywords: keywordsFromField(data['keywords']),
  );
}

/// The keywords stored in a story's `keywords` field: only its strings, at
/// most 4. Anything that isn't a list (including a missing field) gives
/// none, so a malformed document can't break the story lists.
List<String> keywordsFromField(Object? field) {
  if (field is! List) return const [];
  return List.unmodifiable(field.whereType<String>().take(4));
}

StoryPart storyPartFromMap(Map<String, dynamic> map) {
  return StoryPart(
    position: map['position'] as String,
    text: map['text'] as String,
    author: map['author'] as String,
    timestamp: (map['timestamp'] as Timestamp).toDate(),
  );
}

Map<String, dynamic> storyPartToMap(StoryPart part) {
  return {
    'position': part.position,
    'text': part.text,
    'author': part.author,
    'timestamp': Timestamp.fromDate(part.timestamp),
  };
}
