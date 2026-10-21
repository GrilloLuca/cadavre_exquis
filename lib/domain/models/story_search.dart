/// Search of completed stories by keyword, on the device (see
/// docs/STORY_SEARCH_PLAN.md §2.2). Only the AI title and keywords are
/// searched, never the part text: both are generated child-safe, even for
/// mature stories, so a match on a locked story reveals nothing.
library;

import 'package:cadavre_exquisite/domain/models/story.dart';

/// Accented letters of the room languages and what they fold to. Dart core
/// has no Unicode normalization (NFD), so the table is explicit. Applied
/// after lowercasing, so only lowercase letters are needed.
const Map<String, String> _accentFolds = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', //
  'æ': 'ae',
  'ç': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', //
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', //
  'ñ': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', //
  'œ': 'oe',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', //
  'ý': 'y', 'ÿ': 'y', //
  'ß': 'ss',
};

final RegExp _foldable = RegExp('[${_accentFolds.keys.join()}]');

final RegExp _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Query tokens shorter than this are ignored when the query has a longer
/// one, which drops articles ("il", "la", "un", "of", the "l" of "l'")
/// without per-language stopword lists.
const int _minTokenLength = 3;

/// [text] lowercased, with the accented letters of the room languages
/// folded to their base letters (`Città` → `citta`, `Straße` → `strasse`).
String foldForSearch(String text) =>
    text.toLowerCase().replaceAllMapped(_foldable, (m) => _accentFolds[m[0]]!);

/// The words of [text] for search: [foldForSearch] applied, then split on
/// anything that isn't a letter or a digit, empty pieces dropped. So
/// `L'isola` gives `l`, `isola`, and `castello-fantasma` gives two tokens.
List<String> searchTokens(String text) => foldForSearch(text)
    .split(_separators)
    .where((token) => token.isNotEmpty)
    .toList();

/// A search query, built once from the raw text the user typed.
class StoryQuery {
  /// The raw text the query was built from.
  final String text;

  /// The tokens a story must match: those of [text], without the ones
  /// shorter than 3 characters if at least one is longer. In input order.
  final List<String> tokens;

  StoryQuery._(this.text, this.tokens);

  factory StoryQuery(String text) {
    final all = searchTokens(text);
    final long = all.where((t) => t.length >= _minTokenLength).toList();
    return StoryQuery._(text, List.unmodifiable(long.isEmpty ? all : long));
  }

  /// The query that matches every story.
  static final StoryQuery empty = StoryQuery('');

  /// Whether the query has no tokens (empty or only separators), so it
  /// matches every story and the list stays unfiltered.
  bool get isEmpty => tokens.isEmpty;

  /// Whether [other] has the same effective [tokens], so it filters
  /// exactly the same stories (e.g. `drago` and `Drago `, or `il drago`).
  bool hasSameTokens(StoryQuery other) {
    if (tokens.length != other.tokens.length) return false;
    for (var i = 0; i < tokens.length; i++) {
      if (tokens[i] != other.tokens[i]) return false;
    }
    return true;
  }

  /// Whether every query token is a prefix of at least one token of the
  /// story's title or keywords. An empty query matches every story; a
  /// story without title and keywords matches only the empty query.
  bool matches(Story story) {
    if (isEmpty) return true;
    final storyTokens = [
      ...searchTokens(story.title ?? ''),
      for (final keyword in story.keywords) ...searchTokens(keyword),
    ];
    return tokens.every(
      (token) => storyTokens.any((word) => word.startsWith(token)),
    );
  }

  /// Whether [keyword] (one of a story's keywords) helps the story match:
  /// the query isn't empty and at least one of its [tokens] is a prefix of
  /// a token of [keyword], with the same folding as [matches]. The View
  /// highlights such keywords on the tiles.
  bool highlights(String keyword) {
    if (isEmpty) return false;
    final words = searchTokens(keyword);
    return tokens.any(
      (token) => words.any((word) => word.startsWith(token)),
    );
  }

  /// The stories of [stories] that [matches], in their order.
  List<Story> filter(Iterable<Story> stories) =>
      stories.where(matches).toList();
}
