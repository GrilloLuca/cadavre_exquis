import { Type } from "@google/genai";
import { getFirestore, Transaction } from "firebase-admin/firestore";
import { BLOCKED_FINISH_REASONS, client, DEFAULT_LANGUAGE, LANGUAGE_NAMES, MODEL } from "./gemini";

// Story keywords: after every part, the last one included, Gemini
// summarizes the parts written so far in up to 4 keywords (Story.keywords in
// the app). On an incomplete story the chat screen shows them to the next
// player; on a completed story they describe the whole story and are used
// by the search of the complete stories list. Written to `keywords` and
// `keywordsPartCount` by the Admin SDK only; clients can't write them (see
// `isValidSubmit` in firestore.rules). See docs/STORY_KEYWORDS_PLAN.md and
// docs/STORY_SEARCH_PLAN.md.

const MAX_KEYWORDS = 4;
const MAX_KEYWORD_LENGTH = 24;

/**
 * The number of parts to extract keywords for, or undefined if [before] →
 * [after] isn't "a part was added". That includes the part that completes
 * the story, so completed stories get keywords from all their parts. Lock
 * changes, the review write (title/mature) and the keywords write itself
 * don't change the part count, so they're all ignored.
 */
export function keywordsPartCountFor(
  before: FirebaseFirestore.DocumentData,
  after: FirebaseFirestore.DocumentData,
): number | undefined {
  const n = (after.parts ?? []).length;
  if (n !== (before.parts ?? []).length + 1) return undefined;
  return n;
}

/**
 * Whether keywords computed from the first [partCount] parts may be stored
 * on a story whose current document is [data] (undefined if it doesn't
 * exist): it must exist, be incomplete or complete, still have exactly
 * [partCount] parts (otherwise a newer event computes fresher keywords),
 * and not already have keywords from as many parts or more (a duplicate or
 * out-of-order event, or a re-run of the backfill).
 */
export function canSaveKeywords(
  data: FirebaseFirestore.DocumentData | undefined,
  partCount: number,
): boolean {
  if (data === undefined) return false;
  if (data.status !== "incomplete" && data.status !== "complete") return false;
  if ((data.parts ?? []).length !== partCount) return false;
  const stored = data.keywordsPartCount;
  if (typeof stored === "number" && stored >= partCount) return false;
  return true;
}

/**
 * The usable keywords in [raw]: strings only, trimmed, without quotes,
 * hashes or punctuation at the ends, at most [MAX_KEYWORD_LENGTH]
 * characters each, de-duplicated case-insensitively, at most
 * [MAX_KEYWORDS]. Anything that isn't an array gives none.
 */
export function cleanKeywords(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  const keywords: string[] = [];
  const seen = new Set<string>();
  for (const item of raw) {
    if (keywords.length === MAX_KEYWORDS) break;
    if (typeof item !== "string") continue;
    // Cut by code points, so an emoji or accented letter isn't split, then
    // trim again in case the cut left a space or punctuation at the end.
    const chars = [...trimEnds(item.replace(/\s+/g, " "))];
    const keyword = trimEnds(chars.slice(0, MAX_KEYWORD_LENGTH).join(""));
    const key = keyword.toLowerCase();
    if (keyword === "" || seen.has(key)) continue;
    seen.add(key);
    keywords.push(keyword);
  }
  return keywords;
}

/** [text] without anything but letters and digits at either end. */
function trimEnds(text: string): string {
  return text.replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, "");
}

// Everyone sees the keywords, even on a locked mature story (they're
// searchable) and before the latest part has a moderation verdict
// (moderateStoryPart runs alongside), and players are mostly children and
// teenagers: same bar as the titles in REVIEW_INSTRUCTION (index.ts).
const KEYWORDS_INSTRUCTION = (language: string) =>
  "You read a short story, possibly unfinished, written collaboratively by " +
  "several players, mostly children and teenagers. Give at most 4 keywords " +
  `in ${language} that capture its characters, setting and situation, so ` +
  "readers know what the story is about. Each keyword is one or two " +
  "words, lowercase unless it's a proper name, no punctuation, no quotes. " +
  "Prefer singular nouns in their base form. Everyone sees the keywords, so they must always be suitable for " +
  "a 10-year-old: no sexual or suggestive words, graphic violence, gore, " +
  "profanity, slurs, drugs, alcohol, self-harm or suicide. If the story " +
  "contains such content, use neutral words about its plot, characters or " +
  "setting instead, or give fewer keywords.";

const KEYWORDS_SCHEMA = {
  type: Type.OBJECT,
  properties: {
    keywords: { type: Type.ARRAY, items: { type: Type.STRING } },
  },
  required: ["keywords"],
};

/**
 * Asks Gemini for up to 4 keywords describing the parts of the story written
 * so far. A story the model refuses to read gets none. Throws on network or
 * API errors and on malformed responses, leaving the previous keywords in
 * place.
 */
export async function extractKeywords(data: FirebaseFirestore.DocumentData): Promise<string[]> {
  const parts = (data.parts ?? []) as { text: string }[];
  const story = parts.map((p) => p.text).join("\n\n");
  const language = LANGUAGE_NAMES[data.language ?? DEFAULT_LANGUAGE] ?? "Italian";

  const response = await client().models.generateContent({
    model: MODEL,
    contents: story,
    config: {
      systemInstruction: KEYWORDS_INSTRUCTION(language),
      responseMimeType: "application/json",
      responseSchema: KEYWORDS_SCHEMA,
      temperature: 0.4,
    },
  });

  if (
    response.promptFeedback?.blockReason ||
    BLOCKED_FINISH_REASONS.has(response.candidates?.[0]?.finishReason)
  ) {
    return [];
  }
  const parsed = JSON.parse(response.text ?? "{}") as { keywords?: unknown };
  if (!Array.isArray(parsed.keywords)) {
    throw new Error(`Unexpected keywords response: ${response.text}`);
  }
  return cleanKeywords(parsed.keywords);
}

/**
 * Stores [keywords], computed from the first [partCount] parts, on the
 * story (incomplete or complete), unless they're already stale: see
 * [canSaveKeywords]. Transactional, so a part added meanwhile is never
 * overwritten with older keywords, and idempotent. Returns whether they
 * were stored.
 */
export async function saveKeywords(storyId: string, partCount: number, keywords: string[]): Promise<boolean> {
  const db = getFirestore();
  const ref = db.doc(`stories/${storyId}`);
  return db.runTransaction(async (tx: Transaction) => {
    const snapshot = await tx.get(ref);
    if (!canSaveKeywords(snapshot.exists ? snapshot.data() : undefined, partCount)) return false;
    tx.update(ref, { keywords, keywordsPartCount: partCount });
    return true;
  });
}
