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
//   story's `keywords` are cleared, since they may quote it (the next part
//   extracts new ones). The original text stays in the report, which only
//   the Admin SDK reads.
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
  return { parts, keywords: [] };
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
 * moderators. Every outcome is logged, a violation as a warning.
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
