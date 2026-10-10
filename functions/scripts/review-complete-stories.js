// Reviews completed stories that have no `mature` verdict yet: those
// completed before reviews existed, and any whose review failed. The
// complete stories lists only show reviewed stories, so run this before
// releasing the app version that filters on `mature`.
//
// Usage (from functions/, after `npm run build` and
// `gcloud auth application-default login`):
//   node scripts/review-complete-stories.js            # dry run, calls Gemini
//   node scripts/review-complete-stories.js --write
// lib/index.js initializes the default Admin app, which reads the project
// from this variable when run outside Cloud Functions.
process.env.GCLOUD_PROJECT ??= "flash-chat-7d17e";

const { getFirestore } = require("firebase-admin/firestore");
const { reviewStory, saveReview } = require("../lib/index.js");

async function main() {
  const write = process.argv.includes("--write");
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

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
