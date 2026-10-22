// Backfills the part reviews of incomplete stories (see src/moderation.ts):
// every part with no verdict in `partReviews`, i.e. parts written before
// moderateStoryPart existed and those whose review failed or gave up
// retrying ("Part review gave up" in the logs). All the parts are reviewed,
// not only the last one, since any flagged part sets the story's
// `mature: true` and gates it in the app. Nobody can lock or continue a
// story whose last part has no verdict (firestore.rules), so run this after
// deploying moderateStoryPart and, until it reports 0 candidates, before
// deploying those rules and releasing the app version that reads
// `partReviews`. See docs/PART_MODERATION_PLAN.md.
//
// Usage (from functions/, after `npm run build` and
// `gcloud auth application-default login`):
//   node scripts/review-incomplete-parts.js            # dry run, calls Gemini
//   node scripts/review-incomplete-parts.js --write
//
// The dry run prints each candidate's id, part position and verdict and
// writes nothing. It calls reviewPart/savePartReview directly, never the
// moderateStoryPart trigger, so it sends no "story continued" push
// notifications.
// savePartReview only writes if the story still has the part and no verdict
// for it, and never downgrades `mature`, so a part the trigger reviewed
// while this runs keeps the trigger's verdict, and re-running it changes
// nothing (a re-run finds 0 candidates, except parts whose review failed or
// stories continued meanwhile).
// lib/index.js initializes the default Admin app, which reads the project
// from this variable when run outside Cloud Functions.
process.env.GCLOUD_PROJECT ??= "flash-chat-7d17e";

const { getFirestore } = require("firebase-admin/firestore");
const { partsToReview, reviewPart, savePartReview } = require("../lib/index.js");

async function main() {
  const write = process.argv.includes("--write");

  const snapshot = await getFirestore()
    .collection("stories")
    .where("status", "==", "incomplete")
    .get();

  let candidates = 0;
  let parts = 0;
  let reviewed = 0;
  let mature = 0;
  let skipped = 0;
  let failed = 0;
  for (const doc of snapshot.docs) {
    const pending = partsToReview(doc.data());
    if (pending.length === 0) continue;
    candidates++;
    for (const part of pending) {
      parts++;
      try {
        const verdict = await reviewPart(typeof part.text === "string" ? part.text : "", doc.get("language"));
        console.log(doc.id, { position: part.position, verdict });
        if (write && !(await savePartReview(doc.id, part.position, verdict))) {
          console.log(doc.id, part.position, "changed meanwhile, not saved");
          skipped++;
          continue;
        }
        reviewed++;
        if (verdict === "mature") mature++;
      } catch (error) {
        console.error(doc.id, part.position, "part review failed:", error.message);
        failed++;
      }
    }
  }
  console.log(
    `${reviewed}/${parts} parts without a verdict in ${candidates} incomplete stories ` +
      `${write ? "reviewed" : "would be reviewed (dry run)"}` +
      (mature ? `, ${mature} mature` : "") +
      (skipped ? `, ${skipped} changed meanwhile (not saved)` : "") +
      (failed ? `, ${failed} failed` : "") +
      ` (${snapshot.size} incomplete stories in total)`,
  );
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
