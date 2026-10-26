// Unit tests for src/reports.ts. Run with `npm test` (builds first).
const test = require("node:test");
const assert = require("node:assert/strict");
const { FinishReason, BlockedReason } = require("@google/genai");
const { FieldValue } = require("firebase-admin/firestore");
const {
  describeFields,
  reportedPart,
  reportReviewFrom,
  reportStoryFields,
  reviewReport,
} = require("../lib/reports.js");
const { RETRY_CAP_MS } = require("../lib/moderation.js");

const story = (extra = {}) => ({
  language: "en",
  keywords: ["drago", "luna"],
  parts: [
    { position: "introduzione", text: "once upon a time", author: "ada@x.com" },
    { position: "sviluppo1", text: "something awful", author: "troll@x.com" },
  ],
  ...extra,
});

// --- reportReviewFrom ------------------------------------------------------

test("reportReviewFrom reads the verdict and the category", () => {
  const review = reportReviewFrom({ text: '{"verdict":"violation","category":"slur"}' });
  assert.deepEqual(review, { verdict: "violation", category: "slur" });
});

test("reportReviewFrom treats a refusal as a violation", () => {
  assert.equal(reportReviewFrom({ promptFeedback: { blockReason: BlockedReason.SAFETY } }).verdict, "violation");
  assert.equal(
    reportReviewFrom({ candidates: [{ finishReason: FinishReason.PROHIBITED_CONTENT }] }).verdict,
    "violation",
  );
});

test("reportReviewFrom throws on an unknown verdict", () => {
  assert.throws(() => reportReviewFrom({ text: '{"verdict":"maybe","category":""}' }));
  assert.throws(() => reportReviewFrom({ text: "not json" }));
});

// --- reportedPart / reportStoryFields ----------------------------------------

test("reportedPart skips missing, removed and empty parts", () => {
  assert.equal(reportedPart(undefined, "sviluppo1"), undefined);
  assert.equal(reportedPart(story(), "epilogo"), undefined);
  assert.equal(reportedPart(story(), "sviluppo1").text, "something awful");
  const removed = story();
  removed.parts[1] = { ...removed.parts[1], text: "", removed: true };
  assert.equal(reportedPart(removed, "sviluppo1"), undefined);
});

test("a violation removes only that part and clears the keywords", () => {
  const fields = reportStoryFields(story(), "sviluppo1", "violation");
  assert.deepEqual(fields.parts, [
    { position: "introduzione", text: "once upon a time", author: "ada@x.com" },
    { position: "sviluppo1", text: "", author: "troll@x.com", removed: true },
  ]);
  assert.deepEqual(fields.keywords, []);
  // An extraction still running on the old text can't store its keywords.
  assert.equal(fields.keywordsPartCount, 2);
  assert.equal("title" in fields, false);
});

test("a violation also clears the title", () => {
  const fields = reportStoryFields(story({ title: "The awful thing" }), "sviluppo1", "violation");
  assert.ok(fields.title.isEqual(FieldValue.delete()));
});

// --- describeFields --------------------------------------------------------

test("describeFields stores the keywords and a missing title", () => {
  const data = story({ keywords: [], keywordsPartCount: 2 });
  assert.deepEqual(describeFields(data, 2, { keywords: ["drago"], title: "Il drago" }), {
    keywords: ["drago"],
    title: "Il drago",
  });
  assert.deepEqual(describeFields(data, 2, { keywords: ["drago"] }), { keywords: ["drago"] });
  assert.deepEqual(describeFields({ ...data, title: "Newer" }, 2, { keywords: [], title: "Il drago" }), {
    keywords: [],
  });
});

test("describeFields skips a story that changed meanwhile", () => {
  assert.equal(describeFields(undefined, 2, { keywords: [] }), undefined);
  const data = story({ keywords: [], keywordsPartCount: 2 });
  assert.equal(describeFields(data, 1, { keywords: [] }), undefined);
  assert.equal(describeFields({ ...data, keywordsPartCount: 3 }, 2, { keywords: [] }), undefined);
});

test("a mature verdict age-gates the story once", () => {
  assert.deepEqual(reportStoryFields(story(), "sviluppo1", "mature"), { mature: true });
  assert.equal(reportStoryFields(story({ mature: true }), "sviluppo1", "mature"), undefined);
});

test("a safe verdict changes nothing", () => {
  assert.equal(reportStoryFields(story(), "sviluppo1", "safe"), undefined);
});

// --- reviewReport --------------------------------------------------------

const NOW = new Date("2026-10-23T10:00:00Z");

function deps(overrides = {}) {
  const calls = { reviews: [], saves: [], describes: [], descriptions: [], logs: [] };
  const log = (level) => (message, data) => calls.logs.push({ level, message, data });
  return {
    calls,
    deps: {
      readReport: async () => ({ storyId: "s1", position: "sviluppo1", reason: "harassment" }),
      readStory: async () => story(),
      review: async (text, language, reason) => {
        calls.reviews.push({ text, language, reason });
        return { verdict: "violation", category: "harassment" };
      },
      save: async (storyId, position, review, reported) => {
        calls.saves.push({ storyId, position, review, reported });
        return review ? review.verdict : "gone";
      },
      describe: async (data, withTitle) => {
        calls.describes.push({ data, withTitle });
        return { keywords: ["luna"], title: withTitle ? "La luna" : undefined };
      },
      saveDescription: async (storyId, partCount, description) => {
        calls.descriptions.push({ storyId, partCount, description });
      },
      now: () => NOW,
      logger: { info: log("info"), warn: log("warn"), error: log("error") },
      ...overrides,
    },
  };
}

const job = { reportId: "r1", eventTime: NOW.toISOString() };

test("reviews the reported part and warns when it's removed", async () => {
  const { calls, deps: d } = deps();
  await reviewReport(job, d);
  assert.deepEqual(calls.reviews, [{ text: "something awful", language: "en", reason: "harassment" }]);
  assert.deepEqual(calls.saves[0].reported, { text: "something awful", author: "troll@x.com" });
  assert.equal(calls.logs[0].level, "warn");
  assert.equal(calls.logs[0].message, "Reported part removed");
  assert.deepEqual(calls.descriptions, [
    { storyId: "s1", partCount: 2, description: { keywords: ["luna"], title: undefined } },
  ]);
});

test("a removal asks for a new title only on a completed story that had one", async () => {
  const titled = story({ status: "complete", title: "The awful thing" });
  const { calls, deps: d } = deps({ readStory: async () => titled });
  await reviewReport(job, d);
  assert.equal(calls.describes[0].withTitle, true);

  const untitled = deps({ readStory: async () => story({ status: "complete" }) });
  await reviewReport(job, untitled.deps);
  assert.equal(untitled.calls.describes[0].withTitle, false);
});

test("a failed refresh is logged, not retried", async () => {
  const { calls, deps: d } = deps({ describe: async () => Promise.reject(new Error("503")) });
  await reviewReport(job, d);
  assert.equal(calls.descriptions.length, 0);
  assert.equal(calls.logs.at(-1).message, "Story refresh after removal failed");
});

test("only a violation refreshes the story", async () => {
  const { calls, deps: d } = deps({ review: async () => ({ verdict: "mature", category: "gore" }) });
  await reviewReport(job, d);
  assert.equal(calls.describes.length, 0);
});

test("a report already reviewed isn't reviewed again", async () => {
  const { calls, deps: d } = deps({
    readReport: async () => ({ storyId: "s1", position: "sviluppo1", review: { outcome: "safe" } }),
  });
  await reviewReport(job, d);
  assert.equal(calls.reviews.length, 0);
  assert.equal(calls.saves.length, 0);
});

test("a part already gone is closed without calling Gemini", async () => {
  const { calls, deps: d } = deps({ readStory: async () => undefined });
  await reviewReport(job, d);
  assert.equal(calls.reviews.length, 0);
  assert.equal(calls.saves[0].review, undefined);
  assert.equal(calls.logs[0].message, "Report reviewed");
});

test("a failed review is retried, then given up past the cap", async () => {
  const failing = { review: async () => Promise.reject(new Error("503")) };
  const { deps: d } = deps(failing);
  await assert.rejects(reviewReport(job, d));

  const late = deps({ ...failing, now: () => new Date(NOW.getTime() + RETRY_CAP_MS + 1) });
  await reviewReport(job, late.deps);
  assert.equal(late.calls.logs.at(-1).message, "Report review gave up");
});
