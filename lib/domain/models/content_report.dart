import 'package:cadavre_exquisite/domain/models/email_key.dart';

/// Why a player reports a part. Stored by [name] in `reports/{id}.reason`;
/// must match `reportReasons()` in firestore.rules.
enum ReportReason { offensive, sexual, harassment, spam, other }

/// Whether the signed-in user [me] can report or block the author of a
/// part written by [author]: not their own parts, nor anonymized ones (a
/// deleted account's parts have an empty author).
bool canReportAuthor({required String author, required String? me}) {
  if (me == null || author.trim().isEmpty) return false;
  return emailKey(author) != emailKey(me);
}
