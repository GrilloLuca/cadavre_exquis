import { GenerateContentResponse, Type } from "@google/genai";
import { FieldValue, getFirestore, Transaction } from "firebase-admin/firestore";
import type { logger as functionsLogger } from "firebase-functions";
import { BLOCKED_FINISH_REASONS, client, DEFAULT_LANGUAGE, LANGUAGE_NAMES, MODEL } from "./gemini";
import { keywordsPartCountFor } from "./keywords";

// Moderation of stories for children: each part is reviewed when it's
// submitted (moderateStoryPart in index.ts, see [moderatePart]), except the
// part that completes the story, which is reviewed together with the whole
// story by the completion review (reviewCompletedStory, see
// [reviewCompletion]). Both write the story-level `mature`, which is
// one-way: missing → true, missing → false (completion review only, when no
// part was flagged), false → true. It's never downgraded from true to false.
// Incomplete stories therefore have `mature: true` or no `mature` at all.
// The verdicts per part go to `partReviews`, keyed by part position, and the
// completion review marks itself done with `reviewedAt`. All three are
// written by the Admin SDK only; clients can't write them (see
// `isValidSubmit` in firestore.rules).
//
// Nobody can open a story until it's reviewed: an incomplete one until its
// last part has a verdict (`lastPartReviewed` in firestore.rules refuses
// locks and submits meanwhile), a complete one until `reviewedAt` is set.
// So a failed review blocks the story, and both triggers retry: they throw
// on Gemini or Firestore errors so the event is redelivered, until it's
// older than [RETRY_CAP_MS]. Then they log "Part review gave up" / "Story
// review gave up" and the backfill scripts are the last resort. See
// docs/PART_MODERATION_PLAN.md.
//
// The part review also tells whether the part makes no sense (keyboard
// mashing, a lone "oh"): such a part is reported automatically, in the
// same transaction that stores its verdict, with a report that is already
// reviewed (outcome "nonsense", see [nonsenseReport]), so reviewReport
// skips it and the part stays in the story. It's a record for the
// moderators, logged as "Nonsense part reported".

/**
 * What makes a text unsuitable for children, shared by the story review
 * (REVIEW_INSTRUCTION in index.ts) and the part review, so the two can't
 * drift. Reads after "true if the story is " / "true if the text is ".
 * Players are mostly children and teenagers, so the bar is deliberately
 * low: anything a parent wouldn't want a 10-year-old to read counts.
 */
export const MATURE_CRITERION =
  "unsuitable for a 10-year-old: sexual " +
  "or sexually suggestive content, graphic violence or gore, strong " +
  "profanity or slurs, drug or alcohol abuse, self-harm or suicide, hate " +
  "or harassment towards real people or groups. Cartoonish peril, mild " +
  "scares and slapstick are fine. When unsure, answer true.";

/** The verdict on one part, stored in `partReviews.<position>`. */
export type PartVerdict = "safe" | "mature";

const PART_VERDICTS: readonly unknown[] = ["safe", "mature"];

/** What the part review decided: [verdict] and whether it makes no sense. */
export interface PartReview {
  verdict: PartVerdict;
  nonsense: boolean;
}

// The last five words of a part are shown to anyone in the room, so a
// single part is judged on its own, without the rest of the story.
const PART_REVIEW_INSTRUCTION = (language: string) =>
  "You review one part of a short story written collaboratively by several " +
  "players, each continuing the previous part without seeing the whole " +
  "text. Most players are children and teenagers. The part is in " +
  `${language} and may start or end mid-sentence.\n\n` +
  `mature: true if the text is ${MATURE_CRITERION}\n\n` +
  "nonsense: true if the text is not a real attempt at writing the story: " +
  "random letters or keyboard mashing, a lone interjection or a few " +
  "monosyllables, words piled up with no meaning, or something unrelated " +
  'to the story (e.g. "test", "ciao", "boh"). The game is surreal by ' +
  "design: absurd or silly but readable sentences, sudden changes of " +
  "topic, invented names, wordplay, typos and a start or end mid-sentence " +
  "are fine. When unsure, answer false.";

const PART_REVIEW_SCHEMA = {
  type: Type.OBJECT,
  properties: {
    mature: { type: Type.BOOLEAN },
    nonsense: { type: Type.BOOLEAN },
  },
  required: ["mature", "nonsense"],
};

/**
 * The review in a part review [response]. A part the model refuses to
 * read is mature by definition (and not nonsense: it was readable enough
 * to refuse). Throws on a malformed `mature`, leaving the part without a
 * verdict; a missing `nonsense` counts as false, so it never blocks the
 * story.
 */
export function partReviewFrom(
  response: Pick<GenerateContentResponse, "promptFeedback" | "candidates" | "text">,
): PartReview {
  if (
    response.promptFeedback?.blockReason ||
    BLOCKED_FINISH_REASONS.has(response.candidates?.[0]?.finishReason)
  ) {
    return { verdict: "mature", nonsense: false };
  }
  const parsed = JSON.parse(response.text ?? "{}") as { mature?: unknown; nonsense?: unknown };
  if (typeof parsed.mature !== "boolean") {
    throw new Error(`Unexpected part review response: ${response.text}`);
  }
  return { verdict: parsed.mature ? "mature" : "safe", nonsense: parsed.nonsense === true };
}

/**
 * Asks Gemini whether the part [text], written in the story language
 * [languageCode], is unsuitable for children and whether it makes no
 * sense. Throws on network or API errors and on malformed responses: the
 * part then stays pending (no verdict) until a retry or the backfill
 * script reviews it.
 */
export async function reviewPart(text: string, languageCode: string | undefined): Promise<PartReview> {
  const language = LANGUAGE_NAMES[languageCode ?? DEFAULT_LANGUAGE] ?? "Italian";
  const response = await client().models.generateContent({
    model: MODEL,
    contents: text,
    config: {
      systemInstruction: PART_REVIEW_INSTRUCTION(language),
      responseMimeType: "application/json",
      responseSchema: PART_REVIEW_SCHEMA,
      temperature: 0.2,
    },
  });
  return partReviewFrom(response);
}

/** A story part as stored in `parts[]`. */
export interface StoryPart {
  position?: unknown;
  text?: unknown;
  author?: unknown;
  /** Set with an empty `text` when a report review removed it (reports.ts). */
  removed?: unknown;
}

/**
 * The part [before] → [after] added, or undefined if that isn't "a part was
 * added" (same condition as [keywordsPartCountFor], so the 4th part, which
 * completes the story, counts too). Lock changes, author anonymization and
 * the server writes (`partReviews`, `mature`, `keywords`, `title`,
 * `reviewedAt`) don't change the part count, so they're all ignored.
 */
export function addedPartFor(
  before: FirebaseFirestore.DocumentData,
  after: FirebaseFirestore.DocumentData,
): StoryPart | undefined {
  const n = keywordsPartCountFor(before, after);
  if (n === undefined) return undefined;
  return (after.parts as StoryPart[])[n - 1];
}

/**
 * The part moderateStoryPart reviews for [before] → [after]: the added part
 * (see [addedPartFor]), or undefined if there's none or it completes the
 * story. The completing part is reviewed by the completion review, in the
 * same transaction as the story (see [completionFields]), so a complete
 * story never becomes readable before its last part has a verdict.
 */
export function partToModerate(
  before: FirebaseFirestore.DocumentData,
  after: FirebaseFirestore.DocumentData,
): StoryPart | undefined {
  if (after.status === "complete") return undefined;
  return addedPartFor(before, after);
}

/** Whether [data] already has a verdict for the part at [position]. */
function hasVerdict(data: FirebaseFirestore.DocumentData, position: string): boolean {
  const reviews = data.partReviews;
  if (typeof reviews !== "object" || reviews === null) return false;
  return PART_VERDICTS.includes((reviews as Record<string, unknown>)[position]);
}

/**
 * Whether a verdict on the part at [position] may be stored on a story
 * whose current document is [data] (undefined if it doesn't exist): it
 * must exist, have a part at [position], and have no verdict for it yet
 * (a duplicate event, or a re-run of the backfill). Legacy documents have
 * no `partReviews` at all.
 */
export function canSavePartReview(data: FirebaseFirestore.DocumentData | undefined, position: string): boolean {
  if (data === undefined) return false;
  const parts = (data.parts ?? []) as StoryPart[];
  if (!parts.some((part) => part.position === position)) return false;
  return !hasVerdict(data, position);
}

/**
 * The fields that store [verdict] on the part at [position] of [data], or
 * undefined if it can't be stored (see [canSavePartReview]). A mature
 * verdict also sets the story's `mature: true`, incomplete or complete,
 * unless it's already true. A safe verdict never touches `mature`, so it's
 * never downgraded.
 */
export function partReviewFields(
  data: FirebaseFirestore.DocumentData | undefined,
  position: string,
  verdict: PartVerdict,
): Record<string, unknown> | undefined {
  if (!canSavePartReview(data, position)) return undefined;
  const fields: Record<string, unknown> = { [`partReviews.${position}`]: verdict };
  if (verdict === "mature" && data!.mature !== true) fields.mature = true;
  return fields;
}

/**
 * The report filed on its author when the part at [position] of the story
 * [storyId], whose current document is [data], makes no sense: its id
 * (one per part, so a re-run overwrites rather than duplicates) and its
 * fields. It's created already reviewed, with the text and author the
 * moderators need, like a report reviewReport has closed (reports.ts), and
 * `reporterKey: "ai"`, which no player's email key can be. Undefined if
 * the part is gone or has no text.
 */
export function nonsenseReport(
  storyId: string,
  position: string,
  data: FirebaseFirestore.DocumentData | undefined,
): { id: string; fields: Record<string, unknown> } | undefined {
  const part = ((data?.parts ?? []) as StoryPart[]).find((p) => p.position === position);
  if (!part || typeof part.text !== "string" || part.text === "") return undefined;
  return {
    id: `nonsense_${storyId}_${position}`,
    fields: {
      storyId,
      position,
      reason: "nonsense",
      reporterKey: "ai",
      createdAt: FieldValue.serverTimestamp(),
      reportedText: part.text,
      reportedAuthor: part.author ?? null,
      review: {
        outcome: "nonsense",
        category: "nonsense",
        model: MODEL,
        reviewedAt: FieldValue.serverTimestamp(),
      },
    },
  };
}

/** Adds the [nonsenseReport] on the part at [position] to [tx], if any. */
function fileNonsenseReport(
  tx: Transaction,
  storyId: string,
  position: string,
  data: FirebaseFirestore.DocumentData | undefined,
): void {
  const report = nonsenseReport(storyId, position, data);
  if (report) tx.set(getFirestore().doc(`reports/${report.id}`), report.fields);
}

/**
 * Stores [review]'s verdict on the part at [position] of the story, see
 * [partReviewFields], and reports the part if it makes no sense (see
 * [nonsenseReport]). Transactional and idempotent. Returns whether it was
 * stored.
 */
export async function savePartReview(storyId: string, position: string, review: PartReview): Promise<boolean> {
  const db = getFirestore();
  const ref = db.doc(`stories/${storyId}`);
  return db.runTransaction(async (tx: Transaction) => {
    const snapshot = await tx.get(ref);
    const data = snapshot.exists ? snapshot.data() : undefined;
    const fields = partReviewFields(data, position, review.verdict);
    if (!fields) return false;
    tx.update(ref, fields);
    if (review.nonsense) fileNonsenseReport(tx, storyId, position, data);
    return true;
  });
}

/**
 * Whether the complete story [data] has been marked reviewed by the
 * completion review (or by the legacy backfill, see [isLegacyReviewed]).
 */
function isReviewed(data: FirebaseFirestore.DocumentData): boolean {
  return data.reviewedAt !== undefined && data.reviewedAt !== null;
}

/**
 * The parts of [data] that have a position and no verdict yet, in order:
 * what the backfill script reviews.
 */
export function partsToReview(data: FirebaseFirestore.DocumentData): (StoryPart & { position: string })[] {
  const parts = (data.parts ?? []) as StoryPart[];
  return parts.filter(
    (part): part is StoryPart & { position: string } =>
      typeof part.position === "string" && part.position !== "" && !hasVerdict(data, part.position),
  );
}

/** What the completion review (reviewStory in index.ts) decided. */
export interface StoryReview {
  /** Absent when the model gave no usable title. */
  title?: string;
  /** Whether the story is unsuitable for children and teenagers. */
  mature: boolean;
}

/**
 * Whether [before] → [after] should run the completion review: the story
 * has just become complete and hasn't been reviewed yet (`reviewedAt`).
 * The status transition comes first, so legacy stories reviewed before
 * `reviewedAt` existed (they have `mature` but no `reviewedAt`) are never
 * reviewed again by the trigger: they're already complete.
 */
export function needsCompletionReview(
  before: FirebaseFirestore.DocumentData,
  after: FirebaseFirestore.DocumentData,
): boolean {
  if (before.status === "complete" || after.status !== "complete") return false;
  return !isReviewed(after);
}

/**
 * Whether the complete story [data] was reviewed before `reviewedAt` and
 * `partReviews` existed: it has a boolean `mature`, no `reviewedAt` and no
 * `partReviews`. `review-complete-stories.js --mark-legacy` sets its
 * `reviewedAt`, so the app, which shows a complete story only once
 * `reviewedAt` is set, keeps listing it. A story of the part-moderation era
 * always has `partReviews` once it has a part verdict, and the completion
 * review sets `mature` and `reviewedAt` together.
 */
export function isLegacyReviewed(data: FirebaseFirestore.DocumentData): boolean {
  return (
    typeof data.mature === "boolean" &&
    !isReviewed(data) &&
    (data.partReviews === undefined || data.partReviews === null)
  );
}

/**
 * Whether the backfill (scripts/review-complete-stories.js) should review
 * the complete story [data]: not reviewed (`reviewedAt`), and not a legacy
 * reviewed story with a title (those are marked by --mark-legacy instead).
 * That covers stories with no `mature` verdict (completed before reviews
 * existed, or whose review failed), stories a part flagged `mature: true`
 * whose completion review failed, and legacy reviewed stories without a
 * title. A complete story without `reviewedAt` is therefore picked by one
 * mode or the other.
 */
export function needsBackfillReview(data: FirebaseFirestore.DocumentData): boolean {
  if (isReviewed(data)) return false;
  return !(isLegacyReviewed(data) && data.title);
}

/**
 * The last part of the complete story [data] if it still needs a verdict:
 * it has a position and a text and no verdict yet. Undefined otherwise,
 * e.g. when moderateStoryPart reviewed it before the completing part was
 * left to the completion review, or on a legacy document.
 */
export function lastPartToReview(data: FirebaseFirestore.DocumentData): (StoryPart & { position: string; text: string }) | undefined {
  const parts = (data.parts ?? []) as StoryPart[];
  const last = parts[parts.length - 1];
  if (last === undefined || typeof last.position !== "string" || last.position === "") return undefined;
  if (typeof last.text !== "string" || hasVerdict(data, last.position)) return undefined;
  return last as StoryPart & { position: string; text: string };
}

/**
 * The fields that store the completion review on a story whose current
 * document is [data] (undefined if it doesn't exist): [review] of the whole
 * story and [partVerdict] of its last part (undefined if it wasn't
 * reviewed, see [lastPartToReview]). Also whether they set `reviewedAt`,
 * i.e. whether this is the review that makes the story readable (and
 * notifies). Nothing is written once `reviewedAt` is set. Otherwise:
 * `partReviews.<last position>` if it has no verdict yet (an existing one
 * is never overwritten), the title if there's none yet, `reviewedAt`, and
 * `mature = (stored mature is true) || review.mature || the last part is
 * mature`, so it's never downgraded and a part flagged meanwhile is kept.
 */
export function completionFields(
  data: FirebaseFirestore.DocumentData | undefined,
  review: StoryReview,
  partVerdict: PartVerdict | undefined,
): { fields: Record<string, unknown>; setsReviewedAt: boolean } {
  if (data === undefined || isReviewed(data)) {
    return { fields: {}, setsReviewedAt: false };
  }
  const fields: Record<string, unknown> = {};
  const last = lastPartToReview(data);
  const savesPart = partVerdict !== undefined && last !== undefined;
  if (savesPart) fields[`partReviews.${last.position}`] = partVerdict;
  if (review.title && !data.title) fields.title = review.title;
  fields.mature = data.mature === true || review.mature || (savesPart && partVerdict === "mature");
  fields.reviewedAt = FieldValue.serverTimestamp();
  return { fields, setsReviewedAt: true };
}

/**
 * Stores the completion review once, see [completionFields], with
 * [partReview]'s verdict on the last part, which is reported if it makes no
 * sense (see [nonsenseReport]). Transactional and idempotent: clients
 * can't write these fields (see `isValidSubmit` in firestore.rules), so a
 * duplicate event changes nothing. Returns whether this call set
 * `reviewedAt`, i.e. the story has just become readable.
 */
export async function saveCompletionReview(
  storyId: string,
  review: StoryReview,
  partReview: PartReview | undefined,
): Promise<boolean> {
  const db = getFirestore();
  const ref = db.doc(`stories/${storyId}`);
  return db.runTransaction(async (tx: Transaction) => {
    const snapshot = await tx.get(ref);
    const data = snapshot.exists ? snapshot.data() : undefined;
    const last = data === undefined ? undefined : lastPartToReview(data);
    const { fields, setsReviewedAt } = completionFields(data, review, partReview?.verdict);
    if (Object.keys(fields).length > 0) tx.update(ref, fields);
    if (setsReviewedAt && last && partReview?.nonsense) fileNonsenseReport(tx, storyId, last.position, data);
    return setsReviewedAt;
  });
}

/**
 * Marks the legacy reviewed story [storyId] reviewed (see
 * [isLegacyReviewed]) by setting `reviewedAt`. Transactional and
 * idempotent. Returns whether it was marked.
 */
export async function markLegacyReviewed(storyId: string): Promise<boolean> {
  const db = getFirestore();
  const ref = db.doc(`stories/${storyId}`);
  return db.runTransaction(async (tx: Transaction) => {
    const snapshot = await tx.get(ref);
    const data = snapshot.exists ? snapshot.data() : undefined;
    if (data === undefined || data.status !== "complete" || !isLegacyReviewed(data)) return false;
    tx.update(ref, { reviewedAt: FieldValue.serverTimestamp() });
    return true;
  });
}

/** The story [storyId] as it is now, or undefined if it doesn't exist. */
export async function currentStory(storyId: string): Promise<FirebaseFirestore.DocumentData | undefined> {
  const snapshot = await getFirestore().doc(`stories/${storyId}`).get();
  return snapshot.exists ? snapshot.data() : undefined;
}

// --- Retries ---------------------------------------------------------------

/**
 * How long a failed review is retried, counted from the event: long enough
 * for a Gemini outage, short enough that a permanent error (e.g. a
 * malformed response every time) doesn't burn calls for the 24 hours
 * Eventarc keeps redelivering.
 */
export const RETRY_CAP_MS = 6 * 60 * 60 * 1000;

/**
 * Whether a review that failed on an event fired at [eventTime] (the
 * CloudEvent `time`, RFC 3339) should be retried at [now]: the event is
 * younger than [RETRY_CAP_MS]. An unreadable time is retried, since giving
 * up leaves the story blocked, and Eventarc stops redelivering anyway.
 */
export function shouldRetry(eventTime: string, now: Date): boolean {
  const firedAt = Date.parse(eventTime);
  if (Number.isNaN(firedAt)) return true;
  return now.getTime() - firedAt < RETRY_CAP_MS;
}

/** The logger calls the handlers make, injected so tests can check them. */
export type ReviewLogger = Pick<typeof functionsLogger, "warn" | "error">;

/** What [moderatePart] reads, calls and writes, injected so tests can drive it. */
export interface PartModerationDeps {
  /** The story as it is now (undefined if deleted). */
  read(): Promise<FirebaseFirestore.DocumentData | undefined>;
  review(text: string, language: string | undefined): Promise<PartReview>;
  /** Stores the review, see [savePartReview]. */
  save(review: PartReview): Promise<boolean>;
  /** Sends the story_continued push. */
  notify(): Promise<void>;
  now(): Date;
  logger: ReviewLogger;
}

/**
 * The body of moderateStoryPart, for the part at [position] with [text] of
 * the story [storyId], from an event fired at [eventTime]. Idempotent, so
 * the trigger can retry: a redelivered event finds the verdict already
 * stored (or the part gone) with a plain read and returns without calling
 * Gemini. Otherwise it reviews the part and stores the verdict, and only
 * the run that stored it sends the story_continued push, mature verdicts
 * included (the text is neutral and the app gates the tap). The push is
 * sent only now, not on submit, because nobody can open the story before
 * the verdict. A part that makes no sense is reported by the save (see
 * [savePartReview]) and logged. On a read, Gemini or transaction error it throws, so the
 * event is retried, unless it's past the cap (see [shouldRetry]): then it
 * logs "Part review gave up" and returns. Notification errors are logged,
 * never thrown: a retry would find the verdict stored and not notify.
 */
export async function moderatePart(
  job: { storyId: string; position: string; text: string; language: string | undefined; eventTime: string },
  deps: PartModerationDeps,
): Promise<void> {
  const { storyId, position } = job;
  try {
    if (!canSavePartReview(await deps.read(), position)) return;
    const review = await deps.review(job.text, job.language);
    if (!(await deps.save(review))) return;
    if (review.nonsense) deps.logger.warn("Nonsense part reported", { storyId, position });
  } catch (error) {
    if (shouldRetry(job.eventTime, deps.now())) {
      deps.logger.error("Part review failed, retrying", { storyId, position, error });
      throw error;
    }
    deps.logger.error("Part review gave up", { storyId, position, eventTime: job.eventTime, error });
    return;
  }
  try {
    await deps.notify();
  } catch (error) {
    deps.logger.error("Story continued notification failed", { storyId, error });
  }
}

/** What [reviewCompletion] reads, calls and writes, injected so tests can drive it. */
export interface CompletionReviewDeps {
  /** The story as it is now (undefined if deleted). */
  read(): Promise<FirebaseFirestore.DocumentData | undefined>;
  reviewStory(data: FirebaseFirestore.DocumentData): Promise<StoryReview>;
  reviewPart(text: string, language: string | undefined): Promise<PartReview>;
  /** Stores the review, see [saveCompletionReview]. */
  save(review: StoryReview, partReview: PartReview | undefined): Promise<boolean>;
  /** Sends the story_completed push. */
  notify(): Promise<void>;
  now(): Date;
  logger: ReviewLogger;
}

/**
 * The body of reviewCompletedStory for the story [storyId], from an event
 * fired at [eventTime]. A redelivered event finds `reviewedAt` already set
 * with a plain read and returns without calling Gemini. Otherwise it
 * reviews the whole story and, in parallel, its last part if that has no
 * verdict yet (see [lastPartToReview]), and stores both in one transaction
 * (see [completionFields]): if either call fails nothing is written and the
 * story stays unreadable. A last part that makes no sense is reported by
 * the save (see [saveCompletionReview]) and logged. Only the run that set `reviewedAt` notifies. Same
 * retry and give-up rules as [moderatePart], logging "Story review gave
 * up".
 */
export async function reviewCompletion(
  job: { storyId: string; eventTime: string },
  deps: CompletionReviewDeps,
): Promise<void> {
  const { storyId } = job;
  try {
    const data = await deps.read();
    if (data === undefined || isReviewed(data)) return;
    const last = lastPartToReview(data);
    const [review, partReview] = await Promise.all([
      deps.reviewStory(data),
      last ? deps.reviewPart(last.text, data.language) : Promise.resolve(undefined),
    ]);
    if (!review.title) deps.logger.warn("Model returned no usable title", { storyId });
    if (!(await deps.save(review, partReview))) return;
    if (last && partReview?.nonsense) deps.logger.warn("Nonsense part reported", { storyId, position: last.position });
  } catch (error) {
    if (shouldRetry(job.eventTime, deps.now())) {
      deps.logger.error("Story review failed, retrying", { storyId, error });
      throw error;
    }
    deps.logger.error("Story review gave up", { storyId, eventTime: job.eventTime, error });
    return;
  }
  try {
    await deps.notify();
  } catch (error) {
    deps.logger.error("Story completed notification failed", { storyId, error });
  }
}
