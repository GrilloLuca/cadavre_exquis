// Reviews completed stories that the completion review hasn't marked
// (`reviewedAt`), except legacy reviewed stories with a title (see
// --mark-legacy): those completed before reviews existed, and any whose
// review failed or gave up retrying ("Story review gave up" in the logs),
// including stories a part review flagged `mature: true` (moderateStoryPart)
// whose completion review then failed, so they have no title. The app only
// shows a complete story once `reviewedAt` is set. Like the
// reviewCompletedStory trigger, it reviews the whole story and, in
// parallel, its last part if that has no verdict yet, and stores both with
// `reviewedAt` in one transaction (saveCompletionReview), which never
// downgrades `mature` and never overwrites a part verdict, so backfilled
// stories look the same as reviewed ones. A re-run after --write finds 0
// candidates, except stories whose review failed. See needsBackfillReview
// and completionFields in src/moderation.ts and docs/PART_MODERATION_PLAN.md.
//
// With --mark-legacy it instead sets `reviewedAt` on complete stories
// reviewed before `reviewedAt` existed (a boolean `mature`, no `reviewedAt`
// and no `partReviews`, see isLegacyReviewed), without calling Gemini, so
// the app version that requires `reviewedAt` keeps listing them. Run it
// before the normal mode; a re-run marks 0.
//
// With --mature-titles it instead re-titles every story already flagged
// `mature == true`, overwriting its existing title with one from the current
// (child-safe) prompt. The `mature` verdict is never changed. If the model
// gives no title (e.g. it refuses the text), the old title is deleted so the
// app falls back to its generic label instead of showing a possibly explicit
// title.
//
// Usage (from functions/, after `npm run build` and
// `gcloud auth application-default login`):
//   node scripts/review-complete-stories.js --mark-legacy             # dry run, no Gemini
//   node scripts/review-complete-stories.js --mark-legacy --write
//   node scripts/review-complete-stories.js            # dry run, calls Gemini
//   node scripts/review-complete-stories.js --write
//   node scripts/review-complete-stories.js --mature-titles           # dry run
//   node scripts/review-complete-stories.js --mature-titles --write
//
// It calls reviewStory/reviewPart/saveCompletionReview directly, never the
// reviewCompletedStory trigger, so it sends no "story completed" push
// notifications.
// lib/index.js initializes the default Admin app, which reads the project
// from this variable when run outside Cloud Functions.
process.env.GCLOUD_PROJECT ??= "flash-chat-7d17e";

const { FieldValue, getFirestore } = require("firebase-admin/firestore");
const {
  isLegacyReviewed,
  lastPartToReview,
  markLegacyReviewed,
  needsBackfillReview,
  reviewPart,
  reviewStory,
  saveCompletionReview,
} = require("../lib/index.js");

async function main() {
  const write = process.argv.includes("--write");
  if (process.argv.includes("--mature-titles")) return retitleMatureStories(write);
  if (process.argv.includes("--mark-legacy")) return markLegacyStories(write);

  const snapshot = await getFirestore()
    .collection("stories")
    .where("status", "==", "complete")
    .get();

  let candidates = 0;
  let reviewed = 0;
  let skipped = 0;
  let failed = 0;
  for (const doc of snapshot.docs) {
    const data = doc.data();
    if (!needsBackfillReview(data)) continue;
    candidates++;
    try {
      const last = lastPartToReview(data);
      const [review, partReview] = await Promise.all([
        reviewStory(data),
        last ? reviewPart(last.text, data.language) : Promise.resolve(undefined),
      ]);
      console.log(
        doc.id,
        { mature: data.mature ?? null, title: data.title ?? null },
        "→",
        review,
        last ? { position: last.position, ...partReview } : "last part already reviewed",
      );
      if (write && !(await saveCompletionReview(doc.id, review, partReview))) {
        console.log(doc.id, "reviewed meanwhile, not saved");
        skipped++;
        continue;
      }
      reviewed++;
    } catch (error) {
      console.error(doc.id, "review failed:", error.message);
      failed++;
    }
  }
  console.log(
    `${reviewed}/${candidates} unreviewed complete stories ${write ? "reviewed" : "would be reviewed (dry run)"}` +
      (skipped ? `, ${skipped} reviewed meanwhile (not saved)` : "") +
      (failed ? `, ${failed} failed` : "") +
      ` (${snapshot.size} complete stories in total)`,
  );
}

async function markLegacyStories(write) {
  const snapshot = await getFirestore()
    .collection("stories")
    .where("status", "==", "complete")
    .get();

  let candidates = 0;
  let marked = 0;
  let skipped = 0;
  for (const doc of snapshot.docs) {
    const data = doc.data();
    if (!isLegacyReviewed(data)) continue;
    candidates++;
    console.log(doc.id, { mature: data.mature, title: data.title ?? null });
    if (write && !(await markLegacyReviewed(doc.id))) {
      console.log(doc.id, "changed meanwhile, not marked");
      skipped++;
      continue;
    }
    marked++;
  }
  console.log(
    `${marked}/${candidates} legacy reviewed complete stories ${write ? "marked reviewed" : "would be marked reviewed (dry run)"}` +
      (skipped ? `, ${skipped} changed meanwhile (not marked)` : "") +
      ` (${snapshot.size} complete stories in total)`,
  );
}

async function retitleMatureStories(write) {
  const snapshot = await getFirestore()
    .collection("stories")
    .where("status", "==", "complete")
    .where("mature", "==", true)
    .get();

  let retitled = 0;
  let cleared = 0;
  let failed = 0;
  for (const doc of snapshot.docs) {
    try {
      const { title } = await reviewStory(doc.data());
      console.log(doc.id, { old: doc.get("title") ?? null, new: title ?? null });
      if (write) await doc.ref.update({ title: title ?? FieldValue.delete() });
      if (title) retitled++;
      else cleared++;
    } catch (error) {
      console.error(doc.id, "review failed:", error.message);
      failed++;
    }
  }
  console.log(
    `${retitled}/${snapshot.size} mature stories ${write ? "re-titled" : "would be re-titled (dry run)"}` +
      (cleared ? `, ${cleared} ${write ? "had their title removed" : "would have their title removed"}` : "") +
      (failed ? `, ${failed} failed (title left unchanged)` : ""),
  );
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
