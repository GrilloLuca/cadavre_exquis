import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/models/story_language.dart';

const List<String> kStoryPositions = [
  'introduzione',
  'sviluppo1',
  'sviluppo2',
  'epilogo',
];

String positionLabel(BuildContext context, String position) {
  final l10n = AppLocalizations.of(context)!;
  switch (position) {
    case 'introduzione':
      return l10n.positionIntroduction;
    case 'sviluppo1':
      return l10n.positionDevelopment1;
    case 'sviluppo2':
      return l10n.positionDevelopment2;
    case 'epilogo':
      return l10n.positionEpilogue;
    default:
      return position;
  }
}

/// Returns the position that follows [position], or null if [position] is the last one.
String? nextPosition(String position) {
  final index = kStoryPositions.indexOf(position);
  if (index == -1 || index == kStoryPositions.length - 1) return null;
  return kStoryPositions[index + 1];
}

class StoryPart {
  final String position;
  final String text;
  final String author;
  final Timestamp timestamp;

  StoryPart({
    required this.position,
    required this.text,
    required this.author,
    required this.timestamp,
  });

  factory StoryPart.fromMap(Map<String, dynamic> map) {
    return StoryPart(
      position: map['position'] as String,
      text: map['text'] as String,
      author: map['author'] as String,
      timestamp: map['timestamp'] as Timestamp,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'position': position,
      'text': text,
      'author': author,
      'timestamp': timestamp,
    };
  }
}

class Story {
  final String id;
  final String status;
  final String currentPosition;
  final List<StoryPart> parts;
  final String? lockedBy;
  final String language;

  /// Id of the private room this story belongs to, or null for a story in
  /// one of the public language rooms.
  final String? roomId;

  Story({
    required this.id,
    required this.status,
    required this.currentPosition,
    required this.parts,
    this.lockedBy,
    this.language = kDefaultStoryLanguage,
    this.roomId,
  });

  factory Story.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Story(
      id: doc.id,
      status: data['status'] as String,
      currentPosition: data['currentPosition'] as String,
      parts: (data['parts'] as List<dynamic>? ?? [])
          .map((p) => StoryPart.fromMap(p as Map<String, dynamic>))
          .toList(),
      lockedBy: data['lockedBy'] as String?,
      language: data['language'] as String? ?? kDefaultStoryLanguage,
      roomId: data['roomId'] as String?,
    );
  }

  bool get isComplete => status == 'complete';

  /// Whether [email] wrote the most recent part, which would make this
  /// their second consecutive turn. A user may write several parts of the
  /// same story, just not two in a row.
  bool wasLastWrittenBy(String? email) =>
      email != null && parts.isNotEmpty && parts.last.author == email;

  /// Whether the story is currently locked by a different user than [email].
  bool isLockedFor(String? email) => lockedBy != null && lockedBy != email;

  /// Last 5 words of the most recently written part, shown as a preview
  /// to the next player. Empty if no part has been written yet.
  String get lastFiveWords {
    if (parts.isEmpty) return '';
    final words = parts.last.text.trim().split(RegExp(r'\s+'));
    final lastWords = words.length <= 5 ? words : words.sublist(words.length - 5);
    return lastWords.join(' ');
  }

  String get fullText => parts.map((p) => p.text).join('\n\n');
}
