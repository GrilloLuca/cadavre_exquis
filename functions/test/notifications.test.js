// Unit tests for the pure helpers in src/notifications.ts. Run with
// `npm test` (builds first).
const test = require("node:test");
const assert = require("node:assert/strict");
const { continuedRecipients, messageFor, recipientsFor } = require("../lib/notifications.js");

test("recipientsFor dedupes authors case-insensitively", () => {
  const parts = [{ author: "Ada@x.com" }, { author: "bob@x.com" }, { author: "ada@x.com " }];
  assert.deepEqual(recipientsFor(parts, "carl@x.com"), ["ada@x.com", "bob@x.com"]);
});

test("recipientsFor leaves out the new author and anonymized authors", () => {
  const parts = [{ author: "ada@x.com" }, { author: "" }, { author: "Bob@x.com" }, {}];
  assert.deepEqual(recipientsFor(parts, "bob@X.com"), ["ada@x.com"]);
});

test("recipientsFor handles missing parts", () => {
  assert.deepEqual(recipientsFor(undefined, "ada@x.com"), []);
});

test("continuedRecipients notifies the earlier authors, not the new one, once each", () => {
  const after = {
    status: "incomplete",
    parts: [{ author: "Ada@x.com" }, { author: "bob@x.com" }, { author: "ada@x.com" }, { author: "BOB@x.com" }],
  };
  // Bob wrote the new part; Ada wrote two earlier parts.
  assert.deepEqual(continuedRecipients(after), ["ada@x.com"]);
  assert.deepEqual(
    continuedRecipients({ status: "incomplete", parts: [{ author: "ada@x.com" }, { author: "" }, { author: "carl@x.com" }] }),
    ["ada@x.com"],
  );
});

test("continuedRecipients sends nothing for the first or the completing part", () => {
  assert.deepEqual(continuedRecipients({ status: "incomplete", parts: [{ author: "ada@x.com" }] }), []);
  assert.deepEqual(continuedRecipients({ status: "incomplete", parts: [] }), []);
  assert.deepEqual(continuedRecipients({ status: "incomplete" }), []);
  const complete = { status: "complete", parts: [{ author: "ada@x.com" }, { author: "bob@x.com" }] };
  assert.deepEqual(continuedRecipients(complete), []);
});

test("messageFor localizes and falls back to English", () => {
  assert.match(messageFor("story_continued", "it", { nickname: "Marta" }).title, /^Marta ha continuato/);
  assert.match(messageFor("story_continued", "fr", { nickname: "Marta" }).title, /^Marta continued/);
  assert.match(messageFor("story_continued", undefined, {}).title, /^Someone continued/);
  assert.match(messageFor("story_continued", "it", { nickname: "  " }).title, /^Qualcuno/);
});

test("messageFor names the story title only when there is one", () => {
  assert.equal(messageFor("story_completed", "en", { title: "The dragon" }).title, "“The dragon” is complete! 📖");
  assert.equal(messageFor("story_completed", "it", {}).title, "Una tua storia è completa! 📖");
});
