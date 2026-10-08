// One-off: adds the `roomId`/`language` fields the story lists now filter on
// to stories created before they were always written. New stories created by
// older app versions are handled by the `normalizeStory` function instead.
//
// Usage (from functions/, after `npm run build` and
// `gcloud auth application-default login`):
//   node scripts/backfill-story-room-fields.js            # dry run
//   node scripts/backfill-story-room-fields.js --write
// lib/index.js initializes the default Admin app, which reads the project
// from this variable when run outside Cloud Functions.
process.env.GCLOUD_PROJECT ??= "flash-chat-7d17e";

const { getFirestore } = require("firebase-admin/firestore");
const { missingRoomFields } = require("../lib/index.js");

async function main() {
  const write = process.argv.includes("--write");
  const db = getFirestore();
  const snapshot = await db.collection("stories").get();

  const writer = write ? db.bulkWriter() : null;
  let count = 0;
  for (const doc of snapshot.docs) {
    const fields = missingRoomFields(doc.data());
    if (Object.keys(fields).length === 0) continue;
    count++;
    console.log(doc.id, fields);
    writer?.update(doc.ref, fields);
  }
  await writer?.close();
  console.log(`${count}/${snapshot.size} stories ${write ? "updated" : "need updating (dry run)"}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
