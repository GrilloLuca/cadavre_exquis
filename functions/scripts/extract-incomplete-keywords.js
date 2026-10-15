// Extracts keywords for incomplete stories that have at least one part and
// no `keywords` field: those last continued before extractStoryKeywords
// existed, and those whose only extraction so far failed. Run it after
// deploying extractStoryKeywords, so stories continued meanwhile are
// already covered.
//
// Usage (from functions/, after `npm run build` and
// `gcloud auth application-default login`):
//   node scripts/extract-incomplete-keywords.js            # dry run, calls Gemini
//   node scripts/extract-incomplete-keywords.js --write
//
// It calls extractKeywords/saveKeywords directly. saveKeywords only writes if
// the story is still incomplete, has the same number of parts and has no
// keywords from as many parts, so a story continued while this runs keeps
// the trigger's fresher keywords, and re-running it changes nothing.
// lib/index.js initializes the default Admin app, which reads the project
// from this variable when run outside Cloud Functions.
process.env.GCLOUD_PROJECT ??= "flash-chat-7d17e";

const { getFirestore } = require("firebase-admin/firestore");
const { extractKeywords, saveKeywords } = require("../lib/index.js");

async function main() {
  const write = process.argv.includes("--write");

  const snapshot = await getFirestore()
    .collection("stories")
    .where("status", "==", "incomplete")
    .get();

  let candidates = 0;
  let extracted = 0;
  let skipped = 0;
  let failed = 0;
  for (const doc of snapshot.docs) {
    const parts = doc.get("parts") ?? [];
    if (parts.length === 0 || doc.get("keywords") !== undefined) continue;
    candidates++;
    try {
      const keywords = await extractKeywords(doc.data());
      console.log(doc.id, { parts: parts.length, keywords });
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
  console.log(
    `${extracted}/${candidates} incomplete stories without keywords ` +
      `${write ? "got keywords" : "would get keywords (dry run)"}` +
      (skipped ? `, ${skipped} changed meanwhile (not saved)` : "") +
      (failed ? `, ${failed} failed` : "") +
      ` (${snapshot.size} incomplete stories in total)`,
  );
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
