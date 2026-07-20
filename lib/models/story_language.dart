/// A language a story room can be created in. Stories carry the [code] of
/// the room they were created in, and users only see stories in the room
/// they have joined, so a story is written entirely in one language.
class StoryLanguage {
  final String code;
  final String flag;
  final String nativeName;

  const StoryLanguage({
    required this.code,
    required this.flag,
    required this.nativeName,
  });
}

/// Stories created before language rooms existed have no `language` field
/// in Firestore; they are treated as Italian, the app's original language.
const String kDefaultStoryLanguage = 'it';

const List<StoryLanguage> kStoryLanguages = [
  StoryLanguage(code: 'it', flag: '🇮🇹', nativeName: 'Italiano'),
  StoryLanguage(code: 'en', flag: '🇬🇧', nativeName: 'English'),
  StoryLanguage(code: 'es', flag: '🇪🇸', nativeName: 'Español'),
  StoryLanguage(code: 'fr', flag: '🇫🇷', nativeName: 'Français'),
  StoryLanguage(code: 'de', flag: '🇩🇪', nativeName: 'Deutsch'),
];

StoryLanguage storyLanguageByCode(String code) {
  return kStoryLanguages.firstWhere(
    (language) => language.code == code,
    orElse: () => kStoryLanguages.first,
  );
}
