import { Type } from "@google/genai";
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import * as functionsV1 from "firebase-functions/v1";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { BLOCKED_FINISH_REASONS, client, DEFAULT_LANGUAGE, LANGUAGE_NAMES, MODEL } from "./gemini";
import { extractKeywords, keywordsPartCountFor, saveKeywords } from "./keywords";
import {
  currentStory,
  MATURE_CRITERION,
  moderatePart,
  needsCompletionReview,
  partToModerate,
  reviewCompletion,
  reviewPart,
  saveCompletionReview,
  savePartReview,
  StoryReview,
} from "./moderation";
import { deleteTokensOf, notifyContinued, notifyStoryCompleted } from "./notifications";

initializeApp();

// The backfill script imports these from lib/index.js.
export { canSaveKeywords, cleanKeywords, extractKeywords, keywordsPartCountFor, saveKeywords } from "./keywords";
export {
  isLegacyReviewed,
  lastPartToReview,
  markLegacyReviewed,
  needsBackfillReview,
  partsToReview,
  reviewPart,
  saveCompletionReview,
  savePartReview,
} from "./moderation";

const MAX_TITLE_LENGTH = 80;

/**
 * Fields the story lists filter on in Firestore (see `_roomQuery` in
 * lib/data/repositories/story/story_repository_firestore.dart) that are
 * missing from [data]: older app versions omit `roomId` for public stories,
 * and the oldest stories have no `language`. Firestore can't match a
 * missing field, so these are filled in.
 */
export function missingRoomFields(data: FirebaseFirestore.DocumentData): Record<string, unknown> {
  const fields: Record<string, unknown> = {};
  if (!("roomId" in data)) fields.roomId = null;
  if (!("language" in data)) fields.language = DEFAULT_LANGUAGE;
  return fields;
}

export const normalizeStory = onDocumentCreated(
  { document: "stories/{storyId}", region: "us-central1" },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const fields = missingRoomFields(data);
    if (Object.keys(fields).length === 0) return;
    await event.data!.ref.update(fields);
  },
);

export type { StoryReview } from "./moderation";

// Players are mostly children and teenagers, so the bar is deliberately low:
// anything a parent wouldn't want a 10-year-old to read counts as mature
// (MATURE_CRITERION, shared with the part review in moderation.ts).
// The app shows the title even on mature stories, so the title itself must
// always be suitable for a 10-year-old.
const REVIEW_INSTRUCTION = (language: string) =>
  "You review short stories written collaboratively by several players, " +
  "each continuing the previous part without seeing the whole text. Most " +
  "players are children and teenagers.\n\n" +
  "1. title: a title for the story, at most 8 words, in " +
  `${language}, no quotes, no trailing punctuation. Everyone sees the ` +
  "title, even when the story is mature, so the title must always be " +
  "suitable for a 10-year-old: no sexual or suggestive words, graphic " +
  "violence, gore, profanity, slurs, drugs, alcohol, self-harm or " +
  "suicide. If the story contains such content, allude to its plot, " +
  "characters or setting in neutral terms instead of quoting or " +
  "describing the explicit parts.\n" +
  `2. mature: true if the story is ${MATURE_CRITERION}`;

const REVIEW_SCHEMA = {
  type: Type.OBJECT,
  properties: {
    title: { type: Type.STRING },
    mature: { type: Type.BOOLEAN },
  },
  required: ["title", "mature"],
  propertyOrdering: ["title", "mature"],
};

/**
 * Asks Gemini for a title and a children's-suitability verdict. A story
 * the model refuses to read is mature by definition. Throws on network or
 * API errors, leaving the story unreviewed (and hidden from every list).
 */
export async function reviewStory(data: FirebaseFirestore.DocumentData): Promise<StoryReview> {
  const parts = (data.parts ?? []) as { text: string }[];
  const story = parts.map((p) => p.text).join("\n\n");
  const language = LANGUAGE_NAMES[data.language ?? DEFAULT_LANGUAGE] ?? "Italian";

  const response = await client().models.generateContent({
    model: MODEL,
    contents: story,
    config: {
      systemInstruction: REVIEW_INSTRUCTION(language),
      responseMimeType: "application/json",
      responseSchema: REVIEW_SCHEMA,
      temperature: 0.7,
    },
  });

  if (
    response.promptFeedback?.blockReason ||
    BLOCKED_FINISH_REASONS.has(response.candidates?.[0]?.finishReason)
  ) {
    return { mature: true };
  }
  const parsed = JSON.parse(response.text ?? "{}") as { title?: string; mature?: boolean };
  if (typeof parsed.mature !== "boolean") {
    throw new Error(`Unexpected review response: ${response.text}`);
  }
  return { title: cleanTitle(parsed.title), mature: parsed.mature };
}

/**
 * Reviews a story once its last part is written, together with that part
 * (moderateStoryPart skips it): the title, the story's `mature` verdict and
 * the last part's verdict are stored in one transaction with `reviewedAt`,
 * which is what makes a complete story readable in the app (see
 * [reviewCompletion] and [completionFields] in moderation.ts). Stories with
 * `mature == true` appear in the complete list locked behind the app's age
 * check, and one a part review already flagged keeps `mature: true` (never
 * downgraded). Once reviewed, its authors are told it can be read. Failures
 * are retried for up to 6 hours, then logged as "Story review gave up" and
 * left to scripts/review-complete-stories.js, which uses the same review and
 * transaction but never notifies anyone.
 */
export const reviewCompletedStory = onDocumentUpdated(
  { document: "stories/{storyId}", region: "us-central1", retry: true },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (!needsCompletionReview(before, after)) return;

    const storyId = event.params.storyId;
    await reviewCompletion(
      { storyId, eventTime: event.time },
      {
        read: () => currentStory(storyId),
        reviewStory,
        reviewPart,
        save: (review, partVerdict) => saveCompletionReview(storyId, review, partVerdict),
        notify: () => notifyStoryCompleted(storyId),
        now: () => new Date(),
        logger,
      },
    );
  },
);

/**
 * Extracts up to 4 keywords from the parts written so far each time a part
 * is added, so the next player has some context, and, on the part that
 * completes the story, so the complete stories can be searched by keyword
 * (see keywords.ts). Separate from moderateStoryPart and from
 * reviewCompletedStory so that a Gemini failure here doesn't block a story
 * or delay its notifications, and vice versa: on completion
 * both fire and write disjoint fields in separate transactions, and each
 * write re-triggers both, which then exit early. Failures are logged, not
 * retried: the story keeps the previous part's keywords, if any.
 */
export const extractStoryKeywords = onDocumentUpdated(
  { document: "stories/{storyId}", region: "us-central1" },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    const partCount = keywordsPartCountFor(before, after);
    if (partCount === undefined) return;

    const storyId = event.params.storyId;
    try {
      const keywords = await extractKeywords(after);
      await saveKeywords(storyId, partCount, keywords);
    } catch (error) {
      logger.error("Keyword extraction failed", { storyId, error });
    }
  },
);

/**
 * Reviews each part when it's submitted, except the 4th, which the
 * completion review covers (see [partToModerate]), so the last five words
 * shown to anyone in the room are moderated before the story is complete
 * (see moderation.ts and docs/PART_MODERATION_PLAN.md): the verdict goes to
 * `partReviews.<position>`, and a mature one also sets the story's
 * `mature: true`, which gates it in the app even while incomplete. Nobody
 * can lock or continue the story until the verdict is stored (firestore.rules),
 * so the earlier authors get the story_continued push only then, from the
 * run that stored it (see [moderatePart]). Separate from the keywords and
 * the completion review, so a Gemini failure in one doesn't affect the
 * others. Its write re-triggers all of them, and they exit early: the part
 * count and the status don't change. Failures are retried for up to 6
 * hours, then logged as "Part review gave up" and left to
 * scripts/review-incomplete-parts.js, which doesn't notify. The story isn't
 * marked mature because of an outage.
 */
export const moderateStoryPart = onDocumentUpdated(
  { document: "stories/{storyId}", region: "us-central1", retry: true },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    const part = partToModerate(before, after);
    if (!part) return;

    const storyId = event.params.storyId;
    const position = part.position;
    if (typeof position !== "string" || position === "" || typeof part.text !== "string") {
      logger.warn("Added part has no position or text", { storyId });
      return;
    }
    await moderatePart(
      { storyId, position, text: part.text, language: after.language, eventTime: event.time },
      {
        read: () => currentStory(storyId),
        review: reviewPart,
        save: (verdict) => savePartReview(storyId, position, verdict),
        notify: () => notifyContinued(storyId, after),
        now: () => new Date(),
        logger,
      },
    );
  },
);

function cleanTitle(raw: string | undefined): string | undefined {
  const line = raw?.trim().split("\n")[0] ?? "";
  const title = line
    .replace(/^["'«“”*#\s]+|["'»“”*\s.]+$/g, "")
    .slice(0, MAX_TITLE_LENGTH)
    .trim();
  return title || undefined;
}

// Shown as "Anonymous" in the app: authorDisplayName() in
// lib/domain/models/author_name.dart returns null for an empty author.
const DELETED_AUTHOR = "";

/**
 * The [parts] with every part written by [email] anonymized, or undefined if
 * none was. Emails are compared case-insensitively, like profile keys.
 */
export function anonymizeParts(
  parts: { author?: string }[] | undefined,
  email: string,
): { author?: string }[] | undefined {
  const key = email.trim().toLowerCase();
  let changed = false;
  const result = (parts ?? []).map((part) => {
    if (part.author?.trim().toLowerCase() !== key) return part;
    changed = true;
    return { ...part, author: DELETED_AUTHOR };
  });
  return changed ? result : undefined;
}

/**
 * Removes a deleted account's email from Firestore: its profile and push
 * tokens are deleted, its story parts stay (they belong to stories other people wrote too) but
 * become anonymous, its story locks are released and it's removed as the
 * creator of its private rooms. There is no 2nd-gen trigger for deleted
 * users, hence the 1st-gen function.
 */
export const anonymizeDeletedUser = functionsV1
  .region("us-central1")
  .auth.user()
  .onDelete(async (user) => {
    const email = user.email;
    if (!email) return;
    const key = email.trim().toLowerCase();
    const db = getFirestore();
    const writer = db.bulkWriter();

    writer.delete(db.doc(`userProfiles/${key}`));
    const tokenCount = await deleteTokensOf(email, writer);

    // Parts can't be queried by author, so every story is checked.
    const stories = await db.collection("stories").select("parts", "lockedBy").get();
    let storyCount = 0;
    for (const doc of stories.docs) {
      const fields: Record<string, unknown> = {};
      const parts = anonymizeParts(doc.get("parts"), email);
      if (parts) fields.parts = parts;
      const lockedBy = doc.get("lockedBy");
      if (typeof lockedBy === "string" && lockedBy.trim().toLowerCase() === key) {
        fields.lockedBy = null;
        fields.lockedAt = null;
      }
      if (Object.keys(fields).length === 0) continue;
      storyCount++;
      writer.update(doc.ref, fields);
    }

    const rooms = await db.collection("privateRooms").where("createdBy", "==", email).get();
    for (const doc of rooms.docs) writer.update(doc.ref, { createdBy: null });

    await writer.close();
    logger.info("Anonymized deleted user", {
      uid: user.uid,
      stories: storyCount,
      rooms: rooms.size,
      tokens: tokenCount,
    });
  });
