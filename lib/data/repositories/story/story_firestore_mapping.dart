import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/domain/models/story_language.dart';

// Converts between the `stories/{id}` Firestore documents and the domain
// Story/StoryPart, so Firestore types (Timestamp, snapshots) stay in the
// data layer.

/// The [Story] stored in [doc]. Stories created before language rooms have
/// no `language` and count as [kDefaultStoryLanguage]; stories without
/// `keywords` (never extracted, or legacy) have none; stories without
/// `partReviews` or `reviewedAt` (legacy, or not reviewed yet) have no
/// verdicts and no review date.
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
    mature: data['mature'] is bool ? data['mature'] as bool : null,
    partReviews: partReviewsFromField(data['partReviews']),
    reviewedAt: data['reviewedAt'] is Timestamp
        ? (data['reviewedAt'] as Timestamp).toDate()
        : null,
    keywords: keywordsFromField(data['keywords']),
  );
}

/// The verdicts stored in a story's `partReviews` field: the entries whose
/// value is a known verdict (`"safe"` or `"mature"`). Anything else, a
/// missing field included, gives none, as the server's `hasVerdict` counts
/// only known values; so a malformed document can't break the story lists.
Map<String, PartVerdict> partReviewsFromField(Object? field) {
  if (field is! Map) return const {};
  return Map.unmodifiable({
    for (final MapEntry(:key, :value) in field.entries)
      if (key is String)
        if (PartVerdict.values.asNameMap()[value] case final verdict?)
          key: verdict,
  });
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
    removed: map['removed'] == true,
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
