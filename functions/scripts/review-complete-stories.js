// Reviews completed stories that have no `mature` verdict yet: those
// completed before reviews existed, and any whose review failed. The
// complete stories lists only show reviewed stories, so run this before
// releasing the app version that filters on `mature`.
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
//   node scripts/review-complete-stories.js            # dry run, calls Gemini
//   node scripts/review-complete-stories.js --write
//   node scripts/review-complete-stories.js --mature-titles           # dry run
//   node scripts/review-complete-stories.js --mature-titles --write
//
// It calls reviewStory/saveReview directly, never the reviewCompletedStory
// trigger, so it sends no "story completed" push notifications.
// lib/index.js initializes the default Admin app, which reads the project
// from this variable when run outside Cloud Functions.
process.env.GCLOUD_PROJECT ??= "flash-chat-7d17e";

const { FieldValue, getFirestore } = require("firebase-admin/firestore");
const { reviewStory, saveReview } = require("../lib/index.js");

async function main() {
  const write = process.argv.includes("--write");
  if (process.argv.includes("--mature-titles")) return retitleMatureStories(write);

  const snapshot = await getFirestore()
    .collection("stories")
    .where("status", "==", "complete")
    .get();

  let reviewed = 0;
  let failed = 0;
  for (const doc of snapshot.docs) {
    if (typeof doc.get("mature") === "boolean") continue;
    try {
      const review = await reviewStory(doc.data());
      console.log(doc.id, review);
      if (write) await saveReview(doc.id, review);
      reviewed++;
    } catch (error) {
      console.error(doc.id, "review failed:", error.message);
      failed++;
    }
  }
  console.log(
    `${reviewed}/${snapshot.size} complete stories ${write ? "reviewed" : "would be reviewed (dry run)"}` +
      (failed ? `, ${failed} failed` : ""),
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
