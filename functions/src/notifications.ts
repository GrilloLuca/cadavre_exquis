import { getFirestore } from "firebase-admin/firestore";
import { getMessaging, Message } from "firebase-admin/messaging";
import { logger } from "firebase-functions";

// Push notifications to the authors of a story when it moves on. Devices
// register in `pushTokens/{fcmToken}` (see NotificationRepositoryFirebase in
// the app); see docs/PUSH_NOTIFICATIONS_PLAN.md.

/** What happened to the story. Must match StoryNotificationKind's wire names in lib/domain/models/story_notification.dart. */
export type NotificationKind = "story_continued" | "story_completed";

/** Must match the channel created in android/.../MainActivity.java. */
const ANDROID_CHANNEL_ID = "story_updates";

/** `in` queries take at most 30 values. */
const IN_QUERY_LIMIT = 30;

/**
 * The key a user's per-email documents are stored under. Must match
 * emailKey() in lib/domain/models/email_key.dart.
 */
export function emailKey(email: string): string {
  return email.trim().toLowerCase();
}

/**
 * The distinct email keys of the authors of [parts], without [excludeAuthor]
 * and without anonymized (deleted) authors.
 */
export function recipientsFor(
  parts: { author?: string }[] | undefined,
  excludeAuthor: string | undefined,
): string[] {
  const excluded = excludeAuthor === undefined ? undefined : emailKey(excludeAuthor);
  const keys = new Set<string>();
  for (const part of parts ?? []) {
    if (typeof part.author !== "string") continue;
    const key = emailKey(part.author);
    if (key === "" || key === excluded) continue;
    keys.add(key);
  }
  return [...keys];
}

// The texts of the notifications, in the app's languages (lib/l10n). Only
// the nickname and the AI title (child-safe by construction) are shown:
// never the story text, which isn't moderated until the story is complete
// and can show on a lock screen.
const STRINGS = {
  it: {
    someone: "Qualcuno",
    continuedTitle: (name: string) => `${name} ha continuato una tua storia ✍️`,
    continuedBody: "Tocca per scrivere il prossimo pezzo.",
    completedTitle: (title?: string) => (title ? `«${title}» è completa! 📖` : "Una tua storia è completa! 📖"),
    completedBody: "Tocca per leggerla.",
  },
  en: {
    someone: "Someone",
    continuedTitle: (name: string) => `${name} continued one of your stories ✍️`,
    continuedBody: "Tap to write the next part.",
    completedTitle: (title?: string) => (title ? `“${title}” is complete! 📖` : "One of your stories is complete! 📖"),
    completedBody: "Tap to read it.",
  },
};

/** The app's UI languages: Italian, and English for everything else. */
function stringsFor(locale: string | undefined) {
  return locale?.toLowerCase().startsWith("it") ? STRINGS.it : STRINGS.en;
}

/** The title and body of a [kind] notification in [locale]. */
export function messageFor(
  kind: NotificationKind,
  locale: string | undefined,
  details: { nickname?: string; title?: string },
): { title: string; body: string } {
  const s = stringsFor(locale);
  if (kind === "story_continued") {
    const name = details.nickname?.trim() || s.someone;
    return { title: s.continuedTitle(name), body: s.continuedBody };
  }
  return { title: s.completedTitle(details.title?.trim() || undefined), body: s.completedBody };
}

/** Error codes meaning the token will never work again. */
const DEAD_TOKEN_ERRORS = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

/**
 * Sends a [kind] notification about [storyId] to every device of the users
 * [emailKeys], each in its own language. Deletes tokens FCM reports as dead.
 * Never throws: a failed notification must not fail (and retry) the
 * trigger that sent it.
 */
export async function sendToUsers(
  emailKeys: string[],
  kind: NotificationKind,
  storyId: string,
  details: { nickname?: string; title?: string },
): Promise<void> {
  if (emailKeys.length === 0) return;
  try {
    const db = getFirestore();
    const tokens: { token: string; locale?: string }[] = [];
    for (let i = 0; i < emailKeys.length; i += IN_QUERY_LIMIT) {
      const snapshot = await db
        .collection("pushTokens")
        .where("emailKey", "in", emailKeys.slice(i, i + IN_QUERY_LIMIT))
        .get();
      for (const doc of snapshot.docs) tokens.push({ token: doc.id, locale: doc.get("locale") });
    }
    if (tokens.length === 0) return;

    // One notification per story on the device: a newer one replaces the
    // previous (and a duplicate trigger delivery replaces itself).
    const tag = `story-${storyId}`;
    const messages: Message[] = tokens.map(({ token, locale }) => ({
      token,
      notification: messageFor(kind, locale, details),
      data: { type: kind, storyId },
      android: { notification: { channelId: ANDROID_CHANNEL_ID, tag, icon: "ic_stat_notify" } },
      apns: { headers: { "apns-collapse-id": tag }, payload: { aps: { sound: "default" } } },
    }));

    const response = await getMessaging().sendEach(messages);
    const dead = response.responses
      .map((r, i) => (!r.success && DEAD_TOKEN_ERRORS.has(r.error?.code ?? "") ? tokens[i].token : null))
      .filter((t): t is string => t !== null);
    await Promise.all(dead.map((token) => db.doc(`pushTokens/${token}`).delete()));
    logger.info("Sent story notifications", {
      storyId,
      kind,
      users: emailKeys.length,
      sent: response.successCount,
      failed: response.failureCount,
      pruned: dead.length,
    });
  } catch (error) {
    logger.error("Sending story notifications failed", { storyId, kind, error });
  }
}

/** The nickname of the user with [email], if they chose one. */
export async function nicknameOf(email: string): Promise<string | undefined> {
  try {
    const snapshot = await getFirestore().doc(`userProfiles/${emailKey(email)}`).get();
    const nickname = snapshot.get("nickname");
    return typeof nickname === "string" && nickname.trim() ? nickname.trim() : undefined;
  } catch {
    return undefined;
  }
}

/**
 * Tells the earlier authors of a story that someone wrote the next part,
 * when [before] → [after] appended a part and the story is still open (the
 * last part is notified once reviewed, see [notifyStoryCompleted]).
 */
export async function notifyIfContinued(
  storyId: string,
  before: FirebaseFirestore.DocumentData,
  after: FirebaseFirestore.DocumentData,
): Promise<void> {
  const previous = (before.parts ?? []) as { author?: string }[];
  const parts = (after.parts ?? []) as { author?: string }[];
  if (parts.length !== previous.length + 1 || after.status !== "incomplete") return;
  const newAuthor = parts[parts.length - 1].author;
  const recipients = recipientsFor(previous, newAuthor);
  if (recipients.length === 0) return;
  const nickname = newAuthor ? await nicknameOf(newAuthor) : undefined;
  await sendToUsers(recipients, "story_continued", storyId, { nickname });
}

/**
 * Tells the authors of a completed, just reviewed story that it can be read,
 * except the one who wrote the last part.
 */
export async function notifyStoryCompleted(storyId: string): Promise<void> {
  const snapshot = await getFirestore().doc(`stories/${storyId}`).get();
  const parts = (snapshot.get("parts") ?? []) as { author?: string }[];
  if (parts.length === 0) return;
  const recipients = recipientsFor(parts, parts[parts.length - 1].author);
  const title = snapshot.get("title");
  await sendToUsers(recipients, "story_completed", storyId, {
    title: typeof title === "string" ? title : undefined,
  });
}

/** Deletes every push token of the user with [email]. */
export async function deleteTokensOf(email: string, writer: FirebaseFirestore.BulkWriter): Promise<number> {
  const snapshot = await getFirestore()
    .collection("pushTokens")
    .where("emailKey", "==", emailKey(email))
    .select()
    .get();
  for (const doc of snapshot.docs) writer.delete(doc.ref);
  return snapshot.size;
}
