import { FinishReason, GoogleGenAI } from "@google/genai";

// The Gemini pieces shared by the story review (index.ts) and the keywords
// of incomplete stories (keywords.ts).

// Gemini on Vertex AI authenticates with the function's service account, so
// there is no API key to manage. Gemini 3.x models are served from "global".
export const MODEL = "gemini-3.1-flash-lite";

// Must match kDefaultStoryLanguage in lib/domain/models/story_language.dart.
export const DEFAULT_LANGUAGE = "it";

// Must match kStoryLanguages in lib/domain/models/story_language.dart.
export const LANGUAGE_NAMES: Record<string, string> = {
  it: "Italian",
  en: "English",
  es: "Spanish",
  fr: "French",
  de: "German",
};

// Finish reasons meaning the model refused to process the text itself.
export const BLOCKED_FINISH_REASONS = new Set<FinishReason | undefined>([
  FinishReason.SAFETY,
  FinishReason.PROHIBITED_CONTENT,
  FinishReason.BLOCKLIST,
  FinishReason.SPII,
]);

let ai: GoogleGenAI | undefined;

export function client(): GoogleGenAI {
  ai ??= new GoogleGenAI({
    vertexai: true,
    project: process.env.GCLOUD_PROJECT,
    location: "global",
  });
  return ai;
}
