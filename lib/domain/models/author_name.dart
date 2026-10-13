import 'package:characters/characters.dart';

/// Masks [email] for public display: the first two characters
/// (grapheme-safe) of the local part followed by a fixed `***`, with the
/// domain hidden entirely. `luca.grillo@gmail.com` becomes `lu***`.
///
/// A string without `@` is treated as all local part. Returns `null` for a
/// null, empty or whitespace-only value, or when the local part is empty
/// (e.g. `@x.it`), so callers can decide on their own fallback.
String? maskEmail(String? email) {
  if (email == null) return null;
  final trimmed = email.trim();
  if (trimmed.isEmpty) return null;
  final at = trimmed.indexOf('@');
  final local = (at == -1 ? trimmed : trimmed.substring(0, at)).trim();
  if (local.isEmpty) return null;
  return '${local.characters.take(2)}***';
}

/// The name to show for a story author: the trimmed [nickname] when it's
/// non-empty, otherwise the masked [email] (see [maskEmail]).
String? authorDisplayName({String? nickname, String? email}) {
  final trimmedNickname = nickname?.trim();
  if (trimmedNickname != null && trimmedNickname.isNotEmpty) {
    return trimmedNickname;
  }
  return maskEmail(email);
}
