/// Build-time switches of the app, read from `--dart-define` once in
/// `lib/config/dependencies.dart` and provided to the screens, so
/// ViewModels and tests take plain values instead of reading the
/// environment.
class AppConfig {
  const AppConfig({this.matureVisibleToMinors = true});

  /// Whether known minors see mature stories as disabled "unavailable"
  /// tiles (true, docs/PART_MODERATION_PLAN.md D4b) or don't see them at
  /// all (false, the earlier rule of docs/MATURE_INLINE_PLAN.md D5). Set
  /// with `--dart-define=MATURE_VISIBLE_TO_MINORS=false`.
  final bool matureVisibleToMinors;
}

/// Where players write for help and reports, shown in the profile and the
/// terms of use. Must match hosting/support.html.
const String kSupportEmail = 'grillo.luca@gmail.com';
