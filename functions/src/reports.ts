import { GenerateContentResponse, Type } from "@google/genai";
import { FieldValue, getFirestore, Transaction } from "firebase-admin/firestore";
import type { logger as functionsLogger } from "firebase-functions";
import { BLOCKED_FINISH_REASONS, client, DEFAULT_LANGUAGE, LANGUAGE_NAMES, MODEL } from "./gemini";
import { shouldRetry, StoryPart } from "./moderation";

// Review of reported parts. A player reports a part from the app
// (`reports/{id}`, see SafetyRepository), and reviewReport asks Gemini
// whether it breaks the terms of use, a different question from the
// children's-suitability review in moderation.ts: a mature story is
// allowed (adults read it behind the age check), a violation isn't.
// * violation: the part is removed. Its `text` becomes "" and it gets
//   `removed: true`, which the app shows as "removed by moderation". The
//   story's `keywords` and AI `title` are cleared in the same write, since
//   they may quote it, and `keywordsPartCount` is set to the part count, so
//   a keyword extraction still running on the old text can't store its
//   result (see canSaveKeywords in keywords.ts). Then the keywords, and the
//   title of a story that had one, are computed again on the text without
//   the part (see [describeFields]): a completed story gets no more parts,
//   so nothing else would, and without them the search can't find it. If
//   that fails it's logged, not retried: the story just stays without them.
//   The original text stays in the report, which only the Admin SDK reads.
// * mature: the story gets `mature: true` (never downgraded, as in
//   moderation.ts), so it's age-gated.
// * safe: nothing changes.
// The verdict goes to the report's `review`, which also makes the trigger
// idempotent. Clients keep working on stories with a removed part: they
// send the earlier parts back as read (see isValidSubmit in
// firestore.rules), extra fields included.

/** What the review decided about a reported part. */
export type ReportVerdict = "violation" | "mature" | "safe";

const REPORT_VERDICTS: readonly unknown[] = ["violation", "mature", "safe"];

/**
 * What the reported part was found to be, stored in `review.outcome`.
 * "nonsense" only on the reports the part review files by itself
 * (`nonsenseReport` in moderation.ts), which are created reviewed, so
 * [reviewReport] never sees them.
 */
export type ReportOutcome = ReportVerdict | "gone" | "nonsense";

const REPORT_REVIEW_INSTRUCTION = (language: string, reason: string) =>
  "You moderate a game where players, mostly children and teenagers, write " +
  "short stories together, each continuing the previous part. Another " +
  `player reported the part below as "${reason}". The part is in ` +
  `${language} and may start or end mid-sentence.\n\n` +
  "verdict:\n" +
  '- "violation" if it breaks the terms of use: hate speech or slurs; ' +
  "harassment, bullying or threats aimed at real people or other players; " +
  "explicit sexual content, or any sexual content involving minors; " +
  "encouraging self-harm, suicide or violence in real life; personal " +
  "information (full names with contact details, addresses, phone " +
  "numbers, social media handles); spam, ads or links. Fiction is allowed " +
  "to be dark, so violence, scares, crime or rude words inside the story " +
  "are not violations by themselves.\n" +
  '- "mature" if it is not a violation but is unsuitable for a 10-year-old ' +
  "(suggestive content, graphic violence or gore, strong profanity, drugs " +
  "or alcohol abuse).\n" +
  '- "safe" otherwise.\n' +
  "category: a few words naming the problem, or an empty string if safe.";

const REPORT_REVIEW_SCHEMA = {
  type: Type.OBJECT,
  properties: {
    verdict: { type: Type.STRING, enum: ["violation", "mature", "safe"] },
    category: { type: Type.STRING },
  },
  required: ["verdict", "category"],
  propertyOrdering: ["verdict", "category"],
};

/** The verdict on a reported part and why. */
export interface ReportReview {
  verdict: ReportVerdict;
  category: string;
}

/**
 * The review in a report review [response]. A part the model refuses to
 * read is a violation: the report already says it's objectionable, and a
 * refusal means it is. Throws on a malformed response, so the report is
 * retried.
 */
export function reportReviewFrom(
  response: Pick<GenerateContentResponse, "promptFeedback" | "candidates" | "text">,
): ReportReview {
  if (
    response.promptFeedback?.blockReason ||
    BLOCKED_FINISH_REASONS.has(response.candidates?.[0]?.finishReason)
  ) {
    return { verdict: "violation", category: "refused by the model" };
  }
  const parsed = JSON.parse(response.text ?? "{}") as { verdict?: unknown; category?: unknown };
  if (!REPORT_VERDICTS.includes(parsed.verdict)) {
    throw new Error(`Unexpected report review response: ${response.text}`);
  }
  return {
    verdict: parsed.verdict as ReportVerdict,
    category: typeof parsed.category === "string" ? parsed.category.slice(0, 100) : "",
  };
}

/** Asks Gemini about the reported [text]. Throws on network or API errors. */
export async function reviewReportedText(
  text: string,
  languageCode: string | undefined,
  reason: string,
): Promise<ReportReview> {
  const language = LANGUAGE_NAMES[languageCode ?? DEFAULT_LANGUAGE] ?? "Italian";
  const response = await client().models.generateContent({
    model: MODEL,
    contents: text,
    config: {
      systemInstruction: REPORT_REVIEW_INSTRUCTION(language, reason),
      responseMimeType: "application/json",
      responseSchema: REPORT_REVIEW_SCHEMA,
      temperature: 0.2,
    },
  });
  return reportReviewFrom(response);
}

/**
 * The part at [position] of the story [data] that a report can act on, or
 * undefined if the story or the part is gone, or the part was already
 * removed (by an earlier report).
 */
export function reportedPart(
  data: FirebaseFirestore.DocumentData | undefined,
  position: string,
): (StoryPart & { text: string }) | undefined {
  if (data === undefined) return undefined;
  const part = ((data.parts ?? []) as StoryPart[]).find((p) => p.position === position);
  if (!part || part.removed === true || typeof part.text !== "string" || part.text === "") return undefined;
  return part as StoryPart & { text: string };
}

/**
 * The story fields that apply [verdict] to the part at [position] of
 * [data], or undefined if there's nothing to change (a safe verdict, a
 * story already mature, or a part already gone).
 */
export function reportStoryFields(
  data: FirebaseFirestore.DocumentData | undefined,
  position: string,
  verdict: ReportVerdict,
): Record<string, unknown> | undefined {
  if (!reportedPart(data, position)) return undefined;
  if (verdict === "mature") return data!.mature === true ? undefined : { mature: true };
  if (verdict !== "violation") return undefined;
  const parts = (data!.parts as StoryPart[]).map((p) =>
    p.position === position ? { ...p, text: "", removed: true } : p,
  );
  return {
    parts,
    keywords: [],
    keywordsPartCount: parts.length,
    ...(data!.title !== undefined ? { title: FieldValue.delete() } : {}),
  };
}

/** The keywords and title computed again after a part was removed. */
export interface StoryDescription {
  keywords: string[];
  /** Absent when not asked for, or when the model gave no usable title. */
  title?: string;
}

/**
 * The story fields that store [description], computed on the story [data]
 * when it had [partCount] parts, or undefined if it's stale: the story is
 * gone, has another part by now (whose extraction gives fresher keywords),
 * or has keywords from a newer extraction. The title is stored only if the
 * story has none (a completion review may have set one meanwhile).
 */
export function describeFields(
  data: FirebaseFirestore.DocumentData | undefined,
  partCount: number,
  description: StoryDescription,
): Record<string, unknown> | undefined {
  if (data === undefined || (data.parts ?? []).length !== partCount) return undefined;
  if (data.keywordsPartCount !== partCount) return undefined;
  const fields: Record<string, unknown> = { keywords: description.keywords };
  if (description.title && !data.title) fields.title = description.title;
  return fields;
}

/** Stores [description] on the story, see [describeFields]. Transactional. */
export async function saveDescription(
  storyId: string,
  partCount: number,
  description: StoryDescription,
): Promise<void> {
  const db = getFirestore();
  const ref = db.doc(`stories/${storyId}`);
  await db.runTransaction(async (tx: Transaction) => {
    const snapshot = await tx.get(ref);
    const fields = describeFields(snapshot.exists ? snapshot.data() : undefined, partCount, description);
    if (fields) tx.update(ref, fields);
  });
}

/** What [reviewReport] reads, calls and writes, injected so tests can drive it. */
export interface ReportReviewDeps {
  /** The report as it is now (undefined if deleted). */
  readReport(): Promise<FirebaseFirestore.DocumentData | undefined>;
  /** The reported story as it is now (undefined if deleted). */
  readStory(storyId: string): Promise<FirebaseFirestore.DocumentData | undefined>;
  review(text: string, language: string | undefined, reason: string): Promise<ReportReview>;
  /** Applies the review to the story and the report, see [saveReportReview]. */
  save(
    storyId: string,
    position: string,
    review: ReportReview | undefined,
    reported: { text: string; author: unknown } | undefined,
  ): Promise<ReportOutcome | undefined>;
  /**
   * The keywords of the story [data] and, if [withTitle], a new title, see
   * [describeFields].
   */
  describe(data: FirebaseFirestore.DocumentData, withTitle: boolean): Promise<StoryDescription>;
  /** Stores them, see [saveDescription]. */
  saveDescription(storyId: string, partCount: number, description: StoryDescription): Promise<void>;
  now(): Date;
  logger: Pick<typeof functionsLogger, "info" | "warn" | "error">;
}

/**
 * The body of reviewReport for the report [reportId], from an event fired
 * at [eventTime]. A redelivered event finds the report's `review` set and
 * returns without calling Gemini. A report on a part that is already gone
 * (removed by an earlier report, or the story deleted) is closed as
 * "gone" without a review. Same retry and give-up rules as moderatePart:
 * on a read, Gemini or transaction error it throws until the event is past
 * the cap, then logs "Report review gave up", leaving the report for the
 * moderators. Every outcome is logged, a violation as a warning. After a
 * violation the story's keywords and title are computed again (see
 * [refreshDescription]).
 */
export async function reviewReport(
  job: { reportId: string; eventTime: string },
  deps: ReportReviewDeps,
): Promise<void> {
  const { reportId } = job;
  let report: FirebaseFirestore.DocumentData | undefined;
  try {
    report = await deps.readReport();
    if (report === undefined || report.review !== undefined) return;
    const { storyId, position, reason } = report;
    if (typeof storyId !== "string" || typeof position !== "string") {
      deps.logger.warn("Report has no story or position", { reportId });
      return;
    }
    const story = await deps.readStory(storyId);
    const part = reportedPart(story, position);
    const review = part ? await deps.review(part.text, story!.language, String(reason)) : undefined;
    const outcome = await deps.save(
      storyId,
      position,
      review,
      part ? { text: part.text, author: part.author } : undefined,
    );
    if (outcome === undefined) return;
    const details = { reportId, storyId, position, reason, outcome, category: review?.category ?? null };
    if (outcome === "violation") {
      deps.logger.warn("Reported part removed", { ...details, author: part?.author ?? null, text: part?.text ?? null });
      await refreshDescription(reportId, storyId, typeof story?.title === "string", deps);
    } else {
      deps.logger.info("Report reviewed", details);
    }
  } catch (error) {
    if (shouldRetry(job.eventTime, deps.now())) {
      deps.logger.error("Report review failed, retrying", { reportId, error });
      throw error;
    }
    deps.logger.error("Report review gave up", {
      reportId,
      storyId: report?.storyId ?? null,
      position: report?.position ?? null,
      eventTime: job.eventTime,
      error,
    });
  }
}

/**
 * Computes the keywords of the story [storyId] again, and its title if it
 * [hadTitle], now that a part is removed, and stores them (see
 * [describeFields]). Never throws: the report is already closed, so a retry
 * wouldn't get here again; a failure is logged and leaves the story
 * without keywords (and title).
 */
async function refreshDescription(
  reportId: string,
  storyId: string,
  hadTitle: boolean,
  deps: ReportReviewDeps,
): Promise<void> {
  try {
    const story = await deps.readStory(storyId);
    if (story === undefined) return;
    const partCount = (story.parts ?? []).length;
    const description = await deps.describe(story, hadTitle && story.status === "complete");
    await deps.saveDescription(storyId, partCount, description);
  } catch (error) {
    deps.logger.error("Story refresh after removal failed", { reportId, storyId, error });
  }
}

/**
 * In one transaction: applies [review] to the story (see
 * [reportStoryFields]) and stores it in the report's `review`, with the
 * [reported] text and author. Re-reads both, so a part removed meanwhile
 * by another report closes this one as "gone". Returns the outcome, or
 * undefined if the report was already reviewed.
 */
export async function saveReportReview(
  reportId: string,
  storyId: string,
  position: string,
  review: ReportReview | undefined,
  reported: { text: string; author: unknown } | undefined,
): Promise<ReportOutcome | undefined> {
  const db = getFirestore();
  const reportRef = db.doc(`reports/${reportId}`);
  const storyRef = db.doc(`stories/${storyId}`);
  return db.runTransaction(async (tx: Transaction) => {
    const [reportSnap, storySnap] = await Promise.all([tx.get(reportRef), tx.get(storyRef)]);
    if (!reportSnap.exists || reportSnap.get("review") !== undefined) return undefined;
    const story = storySnap.exists ? storySnap.data() : undefined;
    const outcome: ReportOutcome = review && reportedPart(story, position) ? review.verdict : "gone";
    if (review && outcome !== "gone") {
      const fields = reportStoryFields(story, position, review.verdict);
      if (fields) tx.update(storyRef, fields);
    }
    tx.update(reportRef, {
      review: {
        outcome,
        category: outcome === "gone" ? null : review!.category,
        model: MODEL,
        reviewedAt: FieldValue.serverTimestamp(),
      },
      ...(reported ? { reportedText: reported.text, reportedAuthor: reported.author ?? null } : {}),
    });
    return outcome;
  });
}
