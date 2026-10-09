import { FinishReason, GoogleGenAI, Type } from "@google/genai";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, Transaction } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";

initializeApp();

// Gemini on Vertex AI authenticates with the function's service account, so
// there is no API key to manage. Gemini 3.x models are served from "global".
const MODEL = "gemini-3.1-flash-lite";
const MAX_TITLE_LENGTH = 80;

// Must match kDefaultStoryLanguage in lib/models/story_language.dart.
const DEFAULT_LANGUAGE = "it";

// Must match kStoryLanguages in lib/models/story_language.dart.
const LANGUAGE_NAMES: Record<string, string> = {
  it: "Italian",
  en: "English",
  es: "Spanish",
  fr: "French",
  de: "German",
};

/**
 * Fields the story lists filter on in Firestore (see `_roomQuery` in
 * lib/services/story_service.dart) that are missing from [data]: older app
 * versions omit `roomId` for public stories, and the oldest stories have no
 * `language`. Firestore can't match a missing field, so these are filled in.
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

let ai: GoogleGenAI | undefined;

function client(): GoogleGenAI {
  ai ??= new GoogleGenAI({
    vertexai: true,
    project: process.env.GCLOUD_PROJECT,
    location: "global",
  });
  return ai;
}

/** What [reviewStory] decided about a completed story. */
export interface StoryReview {
  /** Absent when the model gave no usable title. */
  title?: string;
  /** Whether the story is unsuitable for children and teenagers. */
  mature: boolean;
}

// Players are mostly children and teenagers, so the bar is deliberately low:
// anything a parent wouldn't want a 10-year-old to read counts as mature.
const REVIEW_INSTRUCTION = (language: string) =>
  "You review short stories written collaboratively by several players, " +
  "each continuing the previous part without seeing the whole text. Most " +
  "players are children and teenagers.\n\n" +
  "1. title: a title for the story, at most 8 words, in " +
  `${language}, no quotes, no trailing punctuation.\n` +
  "2. mature: true if the story is unsuitable for a 10-year-old: sexual " +
  "or sexually suggestive content, graphic violence or gore, strong " +
  "profanity or slurs, drug or alcohol abuse, self-harm or suicide, hate " +
  "or harassment towards real people or groups. Cartoonish peril, mild " +
  "scares and slapstick are fine. When unsure, answer true.";

const REVIEW_SCHEMA = {
  type: Type.OBJECT,
  properties: {
    title: { type: Type.STRING },
    mature: { type: Type.BOOLEAN },
  },
  required: ["title", "mature"],
  propertyOrdering: ["title", "mature"],
};

// Finish reasons meaning the model refused to process the text itself.
const BLOCKED_FINISH_REASONS = new Set<FinishReason | undefined>([
  FinishReason.SAFETY,
  FinishReason.PROHIBITED_CONTENT,
  FinishReason.BLOCKLIST,
  FinishReason.SPII,
]);

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
 * Stores [review] on the story. Both fields are fixed once set (clients
 * can't write them either, see `isValidSubmit` in firestore.rules), so a
 * duplicate event or a re-run of the backfill script changes nothing.
 */
export async function saveReview(storyId: string, review: StoryReview): Promise<void> {
  const db = getFirestore();
  const ref = db.doc(`stories/${storyId}`);
  await db.runTransaction(async (tx: Transaction) => {
    const snapshot = await tx.get(ref);
    const fields: Record<string, unknown> = {};
    if (review.title && !snapshot.get("title")) fields.title = review.title;
    if (typeof snapshot.get("mature") !== "boolean") fields.mature = review.mature;
    if (Object.keys(fields).length > 0) tx.update(ref, fields);
  });
}

/**
 * Reviews a story once its last part is written: the complete stories list
 * only shows stories with `mature == false`, and the age-gated mature
 * section those with `mature == true`.
 */
export const reviewCompletedStory = onDocumentUpdated(
  { document: "stories/{storyId}", region: "us-central1" },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status === "complete" || after.status !== "complete") return;
    if (typeof after.mature === "boolean") return;

    const storyId = event.params.storyId;
    let review: StoryReview;
    try {
      review = await reviewStory(after);
    } catch (error) {
      logger.error("Story review failed", { storyId, error });
      return;
    }
    if (!review.title) logger.warn("Model returned no usable title", { storyId });
    await saveReview(storyId, review);
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
