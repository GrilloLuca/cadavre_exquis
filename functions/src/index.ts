import { GoogleGenAI } from "@google/genai";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, Transaction } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import * as functionsV1 from "firebase-functions/v1";
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

// Shown as "Anonymous" in the app: authorDisplayName() in
// lib/models/author_name.dart returns null for an empty author.
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
 * Removes a deleted account's email from Firestore: its profile is deleted,
 * its story parts stay (they belong to stories other people wrote too) but
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
      }
      if (Object.keys(fields).length === 0) continue;
      storyCount++;
      writer.update(doc.ref, fields);
    }

    const rooms = await db.collection("privateRooms").where("createdBy", "==", email).get();
    for (const doc of rooms.docs) writer.update(doc.ref, { createdBy: null });

    await writer.close();
    logger.info("Anonymized deleted user", { uid: user.uid, stories: storyCount, rooms: rooms.size });
  });
