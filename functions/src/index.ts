import { GoogleGenAI } from "@google/genai";
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

/**
 * Gives a story a title once its last part is written. The title is fixed:
 * it is generated only if the story has none, and clients can't write it
 * (see `isValidSubmit` in firestore.rules).
 */
export const generateStoryTitle = onDocumentUpdated(
  { document: "stories/{storyId}", region: "us-central1" },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status === "complete" || after.status !== "complete") return;
    if (after.title) return;

    const parts = (after.parts ?? []) as { text: string }[];
    const story = parts.map((p) => p.text).join("\n\n");
    const language = LANGUAGE_NAMES[after.language ?? DEFAULT_LANGUAGE] ?? "Italian";

    let title: string | undefined;
    try {
      const response = await client().models.generateContent({
        model: MODEL,
        contents: story,
        config: {
          systemInstruction:
            "You title short stories written collaboratively by several " +
            "players, each continuing the previous part without seeing the " +
            "whole text. Reply with only the title: at most 8 words, in " +
            `${language}, no quotes, no trailing punctuation.`,
          temperature: 0.9,
        },
      });
      title = cleanTitle(response.text);
    } catch (error) {
      logger.error("Title generation failed", { storyId: event.params.storyId, error });
      return;
    }
    if (!title) {
      logger.warn("Model returned no usable title", { storyId: event.params.storyId });
      return;
    }

    // A transaction keeps the title fixed even if the event is delivered twice.
    const db = getFirestore();
    const ref = db.doc(`stories/${event.params.storyId}`);
    await db.runTransaction(async (tx: Transaction) => {
      const snapshot = await tx.get(ref);
      if (snapshot.get("title")) return;
      tx.update(ref, { title });
    });
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
