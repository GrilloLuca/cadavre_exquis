// Backfills story keywords (see src/keywords.ts). Two modes:
//
// - Default: incomplete stories that have at least one part and no
//   `keywords` field: those last continued before extractStoryKeywords
//   existed, and those whose only extraction so far failed. Run it after
//   deploying extractStoryKeywords, so stories continued meanwhile are
//   already covered.
// - --complete: complete stories whose keywords don't cover all their parts
//   (`keywordsPartCount !== parts.length`): those completed before
//   extractStoryKeywords ran on the completing part (no keywords at all, or
//   the keywords of their first 3 parts), and those whose extraction on
//   completion failed. Run it after deploying the extractStoryKeywords that
//   also fires on completion. See docs/STORY_SEARCH_PLAN.md.
//
// Usage (from functions/, after `npm run build` and
// `gcloud auth application-default login`):
//   node scripts/extract-incomplete-keywords.js                       # dry run, calls Gemini
//   node scripts/extract-incomplete-keywords.js --write
//   node scripts/extract-incomplete-keywords.js --complete            # dry run, calls Gemini
//   node scripts/extract-incomplete-keywords.js --complete --write
//
// The dry run prints each candidate's id and keywords and writes nothing.
// It calls extractKeywords/saveKeywords directly. saveKeywords only writes if
// the story is still incomplete or complete, has the same number of parts
// and has no keywords from as many parts, so a story continued while this
// runs keeps the trigger's fresher keywords, and re-running it changes
// nothing (a re-run finds 0 candidates, except stories whose extraction
// failed or which changed meanwhile).
// lib/index.js initializes the default Admin app, which reads the project
// from this variable when run outside Cloud Functions.
process.env.GCLOUD_PROJECT ??= "flash-chat-7d17e";

const { getFirestore } = require("firebase-admin/firestore");
const { extractKeywords, saveKeywords } = require("../lib/index.js");

async function main() {
  const write = process.argv.includes("--write");
  const complete = process.argv.includes("--complete");
  const status = complete ? "complete" : "incomplete";

  const snapshot = await getFirestore()
    .collection("stories")
    .where("status", "==", status)
    .get();

  let candidates = 0;
  let extracted = 0;
  let skipped = 0;
  let failed = 0;
  for (const doc of snapshot.docs) {
    const parts = doc.get("parts") ?? [];
    if (!isCandidate(complete, parts, doc)) continue;
    candidates++;
    try {
      const keywords = await extractKeywords(doc.data());
      console.log(doc.id, { parts: parts.length, keywordsPartCount: doc.get("keywordsPartCount"), keywords });
      if (write && !(await saveKeywords(doc.id, parts.length, keywords))) {
        console.log(doc.id, "changed meanwhile, not saved");
        skipped++;
        continue;
      }
      extracted++;
    } catch (error) {
      console.error(doc.id, "keyword extraction failed:", error.message);
      failed++;
    }
  }
  const what = complete
    ? "complete stories without keywords from all their parts"
    : "incomplete stories without keywords";
  console.log(
    `${extracted}/${candidates} ${what} ` +
      `${write ? "got keywords" : "would get keywords (dry run)"}` +
      (skipped ? `, ${skipped} changed meanwhile (not saved)` : "") +
      (failed ? `, ${failed} failed` : "") +
      ` (${snapshot.size} ${status} stories in total)`,
  );
}

/**
 * Whether [doc], with [parts], needs keywords: in the default mode, an
 * incomplete story with parts and no `keywords` field; with --complete, a
 * complete story with parts whose `keywordsPartCount` isn't its number of
 * parts (missing, or from fewer parts).
 */
function isCandidate(complete, parts, doc) {
  if (parts.length === 0) return false;
  if (complete) return doc.get("keywordsPartCount") !== parts.length;
  return doc.get("keywords") === undefined;
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
