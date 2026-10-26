// Unit tests for the pure helpers in src/moderation.ts. Run with `npm test`
// (builds first).
const test = require("node:test");
const assert = require("node:assert/strict");
const { FinishReason, BlockedReason } = require("@google/genai");
const { FieldValue } = require("firebase-admin/firestore");
const fs = require("node:fs");
const path = require("node:path");
const {
  addedPartFor,
  canSavePartReview,
  completionFields,
  isLegacyReviewed,
  lastPartToReview,
  MATURE_CRITERION,
  moderatePart,
  needsBackfillReview,
  needsCompletionReview,
  partReviewFields,
  partsToReview,
  partToModerate,
  nonsenseReport,
  partReviewFrom,
  RETRY_CAP_MS,
  reviewCompletion,
  shouldRetry,
} = require("../lib/moderation.js");

const POSITIONS = ["introduzione", "sviluppo1", "sviluppo2", "epilogo"];
const part = (i, author = "ada@x.com") => ({ position: POSITIONS[i], text: `parte ${i}`, author });
const partsUpTo = (n) => POSITIONS.slice(0, n).map((_, i) => part(i));

// --- B1: partReviewFrom --------------------------------------------------

test("the shared criterion keeps the conservative bar", () => {
  assert.match(MATURE_CRITERION, /^unsuitable for a 10-year-old: /);
  assert.match(MATURE_CRITERION, /When unsure, answer true\.$/);
});

const SAFE = { verdict: "safe", nonsense: false };
const MATURE = { verdict: "mature", nonsense: false };
const NONSENSE = { verdict: "safe", nonsense: true };

test("partReviewFrom treats a blocked prompt as mature", () => {
  const response = { promptFeedback: { blockReason: BlockedReason.SAFETY }, text: undefined };
  assert.deepEqual(partReviewFrom(response), MATURE);
});

test("partReviewFrom treats a SAFETY finish as mature", () => {
  const response = { candidates: [{ finishReason: FinishReason.SAFETY }], text: undefined };
  assert.deepEqual(partReviewFrom(response), MATURE);
});

test("partReviewFrom maps the model's verdict and nonsense flag", () => {
  const ok = { candidates: [{ finishReason: FinishReason.STOP }] };
  assert.deepEqual(partReviewFrom({ ...ok, text: '{"mature":false,"nonsense":false}' }), SAFE);
  assert.deepEqual(partReviewFrom({ ...ok, text: '{"mature":true,"nonsense":false}' }), MATURE);
  assert.deepEqual(partReviewFrom({ ...ok, text: '{"mature":false,"nonsense":true}' }), NONSENSE);
});

test("partReviewFrom reads a missing or malformed nonsense as false", () => {
  assert.deepEqual(partReviewFrom({ text: '{"mature":false}' }), SAFE);
  assert.deepEqual(partReviewFrom({ text: '{"mature":false,"nonsense":"yes"}' }), SAFE);
});

test("partReviewFrom throws on a malformed response", () => {
  assert.throws(() => partReviewFrom({ text: "{}" }), /Unexpected part review response/);
  assert.throws(() => partReviewFrom({ text: undefined }), /Unexpected part review response/);
  assert.throws(() => partReviewFrom({ text: '{"mature":"yes"}' }), /Unexpected part review response/);
  assert.throws(() => partReviewFrom({ text: "not json" }));
});

// --- nonsenseReport ------------------------------------------------------

test("nonsenseReport files a reviewed report with the part's text and author", () => {
  const data = { parts: [{ position: "introduzione", text: "ijhodfaxòklo", author: "ada@x.com" }] };
  const report = nonsenseReport("s1", "introduzione", data);
  assert.equal(report.id, "nonsense_s1_introduzione");
  const { createdAt, review, ...fields } = report.fields;
  assert.deepEqual(fields, {
    storyId: "s1",
    position: "introduzione",
    reason: "nonsense",
    reporterKey: "ai",
    reportedText: "ijhodfaxòklo",
    reportedAuthor: "ada@x.com",
  });
  assert.ok(createdAt.isEqual(FieldValue.serverTimestamp()));
  assert.equal(review.outcome, "nonsense");
  assert.ok(review.reviewedAt.isEqual(FieldValue.serverTimestamp()));
});

test("nonsenseReport files nothing for a missing, empty or removed part", () => {
  assert.equal(nonsenseReport("s1", "introduzione", undefined), undefined);
  assert.equal(nonsenseReport("s1", "sviluppo1", { parts: partsUpTo(1) }), undefined);
  assert.equal(
    nonsenseReport("s1", "introduzione", { parts: [{ position: "introduzione", text: "", removed: true }] }),
    undefined,
  );
});

// --- B2: canSavePartReview / partReviewFields ----------------------------

test("partReviewFields sets the verdict of a part on a legacy doc without partReviews", () => {
  const data = { status: "incomplete", parts: partsUpTo(1) };
  assert.equal(canSavePartReview(data, "introduzione"), true);
  assert.deepEqual(partReviewFields(data, "introduzione", "safe"), { "partReviews.introduzione": "safe" });
});

test("partReviewFields adds a verdict next to the existing ones", () => {
  const data = { status: "incomplete", parts: partsUpTo(2), partReviews: { introduzione: "safe" } };
  assert.deepEqual(partReviewFields(data, "sviluppo1", "safe"), { "partReviews.sviluppo1": "safe" });
});

test("partReviewFields writes nothing for a part that already has a verdict", () => {
  const data = { status: "incomplete", parts: partsUpTo(1), partReviews: { introduzione: "safe" } };
  assert.equal(canSavePartReview(data, "introduzione"), false);
  assert.equal(partReviewFields(data, "introduzione", "mature"), undefined);
  assert.equal(partReviewFields({ ...data, partReviews: { introduzione: "mature" } }, "introduzione", "safe"), undefined);
});

test("partReviewFields writes nothing for an unknown position or a deleted story", () => {
  const data = { status: "incomplete", parts: partsUpTo(1) };
  assert.equal(partReviewFields(data, "sviluppo1", "safe"), undefined);
  assert.equal(partReviewFields({ status: "incomplete" }, "introduzione", "safe"), undefined);
  assert.equal(partReviewFields(undefined, "introduzione", "safe"), undefined);
});

test("partReviewFields: a mature verdict on an incomplete story sets mature true", () => {
  const data = { status: "incomplete", parts: partsUpTo(2), partReviews: { introduzione: "safe" } };
  assert.deepEqual(partReviewFields(data, "sviluppo1", "mature"), {
    "partReviews.sviluppo1": "mature",
    mature: true,
  });
});

test("partReviewFields: a mature verdict upgrades a complete story's mature false", () => {
  const data = { status: "complete", parts: partsUpTo(4), mature: false, title: "Il drago" };
  assert.deepEqual(partReviewFields(data, "epilogo", "mature"), { "partReviews.epilogo": "mature", mature: true });
});

test("partReviewFields: a safe verdict never writes mature", () => {
  for (const mature of [undefined, false, true]) {
    const data = { status: "complete", parts: partsUpTo(4), mature };
    assert.deepEqual(partReviewFields(data, "epilogo", "safe"), { "partReviews.epilogo": "safe" });
  }
});

test("partReviewFields never changes mature true", () => {
  const data = { status: "incomplete", parts: partsUpTo(2), mature: true, partReviews: { introduzione: "mature" } };
  assert.deepEqual(partReviewFields(data, "sviluppo1", "mature"), { "partReviews.sviluppo1": "mature" });
  assert.deepEqual(partReviewFields(data, "sviluppo1", "safe"), { "partReviews.sviluppo1": "safe" });
});

test("partsToReview lists the parts without a verdict, in order", () => {
  const data = { parts: partsUpTo(3), partReviews: { sviluppo1: "safe" } };
  assert.deepEqual(
    partsToReview(data).map((p) => p.position),
    ["introduzione", "sviluppo2"],
  );
  assert.deepEqual(partsToReview({ parts: partsUpTo(2), partReviews: { introduzione: "safe", sviluppo1: "mature" } }), []);
  assert.deepEqual(partsToReview({}), []);
  assert.deepEqual(partsToReview({ parts: [{ text: "senza posizione" }] }), []);
});

// --- B3: the moderateStoryPart trigger condition -------------------------

test("addedPartFor returns the new part for parts 1 to 4", () => {
  for (let n = 1; n <= 4; n++) {
    const before = { status: "incomplete", parts: partsUpTo(n - 1), currentPosition: POSITIONS[n - 1] };
    const after = { ...before, status: n === 4 ? "complete" : "incomplete", parts: partsUpTo(n), lockedBy: null };
    assert.deepEqual(addedPartFor(before, after), part(n - 1), `part ${n}`);
  }
});

test("addedPartFor ignores lock changes", () => {
  const before = { status: "incomplete", parts: partsUpTo(1), lockedBy: null, lockedAt: null };
  const after = { ...before, lockedBy: "bob@x.com", lockedAt: new Date() };
  assert.equal(addedPartFor(before, after), undefined);
  assert.equal(addedPartFor(after, before), undefined);
});

test("addedPartFor ignores the partReviews and mature writes", () => {
  const before = { status: "incomplete", parts: partsUpTo(2), partReviews: { introduzione: "safe" } };
  const after = { ...before, partReviews: { introduzione: "safe", sviluppo1: "mature" }, mature: true };
  assert.equal(addedPartFor(before, after), undefined);
});

test("addedPartFor ignores the keywords write", () => {
  const before = { status: "incomplete", parts: partsUpTo(2) };
  const after = { ...before, keywords: ["drago"], keywordsPartCount: 2 };
  assert.equal(addedPartFor(before, after), undefined);
});

test("addedPartFor ignores the title and reviewedAt write", () => {
  const before = { status: "complete", parts: partsUpTo(4) };
  const after = { ...before, title: "Il drago", mature: false, reviewedAt: new Date() };
  assert.equal(addedPartFor(before, after), undefined);
});

test("addedPartFor ignores author anonymization", () => {
  const before = { status: "incomplete", parts: partsUpTo(2) };
  const after = { ...before, parts: [part(0, ""), part(1)] };
  assert.equal(addedPartFor(before, after), undefined);
});

test("addedPartFor ignores legacy documents without parts", () => {
  assert.equal(addedPartFor({ status: "incomplete" }, { status: "incomplete" }), undefined);
});

// --- B4/B10: the reviewedAt completion marker and the last part ----------

test("completionFields: unreviewed, no flag, model false → mature false and reviewedAt", () => {
  const { fields, setsReviewedAt } = completionFields(
    { status: "complete", parts: partsUpTo(4), partReviews: { introduzione: "safe" } },
    { title: "Il drago", mature: false },
    "safe",
  );
  assert.equal(setsReviewedAt, true);
  assert.equal(fields["partReviews.epilogo"], "safe");
  assert.equal(fields.title, "Il drago");
  assert.equal(fields.mature, false);
  assert.ok(fields.reviewedAt.isEqual(FieldValue.serverTimestamp()));
});

test("completionFields: a story flagged by a part stays mature even if the model says false", () => {
  const { fields, setsReviewedAt } = completionFields(
    { status: "complete", parts: partsUpTo(4), mature: true, partReviews: { sviluppo1: "mature" } },
    { title: "Il drago", mature: false },
    "safe",
  );
  assert.equal(setsReviewedAt, true);
  assert.equal(fields.mature, true);
  assert.equal(fields.title, "Il drago");
  assert.ok("reviewedAt" in fields);
});

test("completionFields: a mature last part makes the story mature even if the model says false", () => {
  const { fields } = completionFields(
    { status: "complete", parts: partsUpTo(4), partReviews: { introduzione: "safe" } },
    { title: "Il drago", mature: false },
    "mature",
  );
  assert.equal(fields["partReviews.epilogo"], "mature");
  assert.equal(fields.mature, true);
});

test("completionFields: the model's mature true is kept", () => {
  const { fields } = completionFields({ status: "complete", parts: partsUpTo(4) }, { mature: true }, "safe");
  assert.equal(fields.mature, true);
  assert.equal("title" in fields, false);
});

test("completionFields never overwrites an existing part verdict", () => {
  const data = { status: "complete", parts: partsUpTo(4), partReviews: { epilogo: "safe" } };
  const { fields } = completionFields(data, { title: "Il drago", mature: false }, "mature");
  assert.equal("partReviews.epilogo" in fields, false);
  // The verdict that wasn't stored doesn't count either.
  assert.equal(fields.mature, false);
});

test("completionFields without a part verdict stores the story review only", () => {
  const { fields } = completionFields(
    { status: "complete", parts: partsUpTo(4), mature: false },
    { title: "Il drago", mature: false },
    undefined,
  );
  assert.deepEqual(Object.keys(fields).sort(), ["mature", "reviewedAt", "title"]);
});

test("completionFields keeps an existing title", () => {
  const { fields } = completionFields(
    { status: "complete", parts: partsUpTo(4), mature: false, title: "Vecchio" },
    { title: "Nuovo", mature: false },
    undefined,
  );
  assert.equal("title" in fields, false);
});

test("completionFields writes nothing and doesn't notify once reviewedAt is set", () => {
  const data = { status: "complete", parts: partsUpTo(4), mature: false, reviewedAt: new Date() };
  assert.deepEqual(completionFields(data, { title: "Il drago", mature: true }, "mature"), {
    fields: {},
    setsReviewedAt: false,
  });
  assert.deepEqual(completionFields(undefined, { mature: true }, "mature"), { fields: {}, setsReviewedAt: false });
});

test("lastPartToReview returns the last part only while it has no verdict", () => {
  assert.deepEqual(lastPartToReview({ parts: partsUpTo(4) }), part(3));
  assert.equal(lastPartToReview({ parts: partsUpTo(4), partReviews: { epilogo: "mature" } }), undefined);
  assert.equal(lastPartToReview({ parts: [] }), undefined);
  assert.equal(lastPartToReview({}), undefined);
  assert.equal(lastPartToReview({ parts: [{ text: "senza posizione" }] }), undefined);
});

test("needsCompletionReview fires on the transition to complete only", () => {
  const before = { status: "incomplete", parts: partsUpTo(3) };
  const after = { status: "complete", parts: partsUpTo(4) };
  assert.equal(needsCompletionReview(before, after), true);
  // A part flagged before completion doesn't skip the review.
  assert.equal(needsCompletionReview({ ...before, mature: true }, { ...after, mature: true }), true);
  assert.equal(needsCompletionReview(before, { ...after, reviewedAt: new Date() }), false);
  assert.equal(needsCompletionReview({ status: "incomplete" }, { status: "incomplete" }), false);
});

test("needsCompletionReview doesn't re-review legacy reviewed stories", () => {
  // Reviewed before reviewedAt existed: any later write (a part verdict,
  // keywords) happens on an already complete story.
  const legacy = { status: "complete", parts: partsUpTo(4), mature: false, title: "Il drago" };
  assert.equal(needsCompletionReview(legacy, { ...legacy, partReviews: { epilogo: "safe" } }), false);
  assert.equal(needsCompletionReview(legacy, { ...legacy, mature: true }), false);
});

// --- B5: review-complete-stories.js candidates ---------------------------

test("needsBackfillReview picks unreviewed stories and those flagged by a part without a title", () => {
  assert.equal(needsBackfillReview({ status: "complete" }), true);
  assert.equal(needsBackfillReview({ status: "complete", mature: true, partReviews: { sviluppo1: "mature" } }), true);
  assert.equal(needsBackfillReview({ status: "complete", mature: false }), true);
});

test("needsBackfillReview skips reviewed stories and legacy reviewed stories with a title", () => {
  assert.equal(needsBackfillReview({ status: "complete", mature: false, title: "Il drago" }), false);
  assert.equal(needsBackfillReview({ status: "complete", mature: true, title: "Il drago" }), false);
  assert.equal(needsBackfillReview({ status: "complete", mature: true, reviewedAt: new Date() }), false);
});

test("needsBackfillReview picks a part-era story with a title but no reviewedAt", () => {
  // Shouldn't happen (the title comes with reviewedAt), but it would be
  // unreadable forever if neither mode picked it.
  const data = { status: "complete", mature: true, title: "Il drago", partReviews: { sviluppo1: "mature" } };
  assert.equal(needsBackfillReview(data), true);
  assert.equal(isLegacyReviewed(data), false);
});

// --- B8: moderateStoryPart skips the completing part, retries ------------

test("partToModerate returns the new part for parts 1 to 3", () => {
  for (let n = 1; n <= 3; n++) {
    const before = { status: "incomplete", parts: partsUpTo(n - 1), currentPosition: POSITIONS[n - 1] };
    const after = { ...before, parts: partsUpTo(n), currentPosition: POSITIONS[n], lockedBy: null };
    assert.deepEqual(partToModerate(before, after), part(n - 1), `part ${n}`);
  }
});

test("partToModerate skips the part that completes the story", () => {
  const before = { status: "incomplete", parts: partsUpTo(3), currentPosition: "epilogo" };
  const after = { ...before, status: "complete", parts: partsUpTo(4) };
  assert.equal(partToModerate(before, after), undefined);
});

test("partToModerate ignores lock, server-field and anonymization writes", () => {
  const base = { status: "incomplete", parts: partsUpTo(2), lockedBy: null, lockedAt: null };
  const writes = [
    { ...base, lockedBy: "bob@x.com", lockedAt: new Date() },
    { ...base, partReviews: { introduzione: "safe", sviluppo1: "mature" }, mature: true },
    { ...base, keywords: ["drago"], keywordsPartCount: 2 },
    { ...base, parts: [part(0, ""), part(1)] },
  ];
  for (const after of writes) assert.equal(partToModerate(base, after), undefined);
  const complete = { status: "complete", parts: partsUpTo(4) };
  assert.equal(partToModerate(complete, { ...complete, title: "Il drago", reviewedAt: new Date() }), undefined);
});

test("shouldRetry retries until the event is RETRY_CAP_MS old", () => {
  assert.equal(RETRY_CAP_MS, 6 * 60 * 60 * 1000);
  const fired = "2026-10-22T10:00:00.000Z";
  const at = (ms) => new Date(Date.parse(fired) + ms);
  assert.equal(shouldRetry(fired, at(0)), true);
  assert.equal(shouldRetry(fired, at(RETRY_CAP_MS - 1)), true);
  assert.equal(shouldRetry(fired, at(RETRY_CAP_MS)), false);
  assert.equal(shouldRetry(fired, at(RETRY_CAP_MS + 1)), false);
  // A clock behind the event's is still retried.
  assert.equal(shouldRetry(fired, at(-1000)), true);
});

test("shouldRetry retries an unreadable event time", () => {
  assert.equal(shouldRetry("", new Date()), true);
  assert.equal(shouldRetry("not a date", new Date()), true);
});

// --- B8/B9: the moderatePart handler body --------------------------------

const FIRED = "2026-10-22T10:00:00.000Z";
const SOON = new Date(Date.parse(FIRED) + 60 * 1000);
const LATE = new Date(Date.parse(FIRED) + RETRY_CAP_MS);

/** Records the logger calls by message. */
function fakeLogger() {
  const lines = [];
  const log = (severity) => (message, details) => lines.push({ severity, message, details });
  return { lines, logger: { warn: log("warn"), error: log("error") } };
}

/** Fakes for moderatePart that record what it called; override any of them. */
function partDeps(overrides = {}) {
  const calls = { review: 0, save: [], notify: 0 };
  const { lines, logger } = fakeLogger();
  const deps = {
    read: async () => ({ status: "incomplete", parts: partsUpTo(2), partReviews: { introduzione: "safe" } }),
    review: async () => {
      calls.review++;
      return SAFE;
    },
    save: async (review) => {
      calls.save.push(review);
      return true;
    },
    notify: async () => {
      calls.notify++;
    },
    now: () => SOON,
    logger,
    ...overrides,
  };
  return { deps, calls, lines };
}

const partJob = { storyId: "s1", position: "sviluppo1", text: "parte 1", language: "it", eventTime: FIRED };

test("moderatePart stores the verdict and then notifies", async () => {
  const { deps, calls, lines } = partDeps();
  await moderatePart(partJob, deps);
  assert.deepEqual(calls, { review: 1, save: [SAFE], notify: 1 });
  assert.deepEqual(lines, []);
});

test("moderatePart logs a nonsense part the save reported, and still notifies", async () => {
  const { deps, calls, lines } = partDeps({ review: async () => NONSENSE });
  await moderatePart(partJob, deps);
  assert.deepEqual(calls.save, [NONSENSE]);
  assert.equal(calls.notify, 1);
  assert.deepEqual(lines.map((l) => [l.severity, l.message, l.details]), [
    ["warn", "Nonsense part reported", { storyId: "s1", position: "sviluppo1" }],
  ]);
});

test("moderatePart notifies for a mature verdict too", async () => {
  const { deps, calls } = partDeps({ review: async () => MATURE });
  await moderatePart(partJob, deps);
  assert.equal(calls.notify, 1);
});

test("moderatePart doesn't notify when another run stored the verdict first", async () => {
  const { deps, calls } = partDeps({ save: async () => false });
  await moderatePart(partJob, deps);
  assert.equal(calls.notify, 0);
});

test("moderatePart on a redelivered event doesn't call Gemini or notify", async () => {
  for (const read of [
    async () => ({ status: "incomplete", parts: partsUpTo(2), partReviews: { introduzione: "safe", sviluppo1: "mature" } }),
    async () => undefined,
  ]) {
    const { deps, calls } = partDeps({ read });
    await moderatePart(partJob, deps);
    assert.deepEqual(calls, { review: 0, save: [], notify: 0 });
  }
});

test("moderatePart throws on a Gemini or transaction error while the event is young", async () => {
  const failing = [
    { review: async () => Promise.reject(new Error("503")) },
    { save: async () => Promise.reject(new Error("aborted")) },
    { read: async () => Promise.reject(new Error("unavailable")) },
  ];
  for (const overrides of failing) {
    const { deps, calls, lines } = partDeps(overrides);
    await assert.rejects(moderatePart(partJob, deps));
    assert.equal(calls.notify, 0);
    assert.deepEqual(lines.map((l) => l.message), ["Part review failed, retrying"]);
  }
});

test("moderatePart gives up quietly once the event is past the cap", async () => {
  const { deps, calls, lines } = partDeps({ review: async () => Promise.reject(new Error("503")), now: () => LATE });
  await moderatePart(partJob, deps);
  assert.equal(calls.notify, 0);
  assert.deepEqual(lines.map((l) => [l.severity, l.message]), [["error", "Part review gave up"]]);
  assert.equal(lines[0].details.storyId, "s1");
  assert.equal(lines[0].details.position, "sviluppo1");
});

test("moderatePart logs a notification error instead of throwing", async () => {
  const { deps, calls, lines } = partDeps({ notify: async () => Promise.reject(new Error("fcm")) });
  await moderatePart(partJob, deps);
  assert.deepEqual(calls.save, [SAFE]);
  assert.deepEqual(lines.map((l) => l.message), ["Story continued notification failed"]);
});

// --- B10: the reviewCompletion handler body ------------------------------

/** Fakes for reviewCompletion that record what it called; override any of them. */
function completionDeps(overrides = {}) {
  const calls = { reviewStory: 0, reviewPart: [], save: [], notify: 0 };
  const { lines, logger } = fakeLogger();
  const deps = {
    read: async () => ({ status: "complete", parts: partsUpTo(4), language: "it", partReviews: { sviluppo2: "safe" } }),
    reviewStory: async () => {
      calls.reviewStory++;
      return { title: "Il drago", mature: false };
    },
    reviewPart: async (text) => {
      calls.reviewPart.push(text);
      return MATURE;
    },
    save: async (review, partReview) => {
      calls.save.push([review, partReview]);
      return true;
    },
    notify: async () => {
      calls.notify++;
    },
    now: () => SOON,
    logger,
    ...overrides,
  };
  return { deps, calls, lines };
}

const completionJob = { storyId: "s1", eventTime: FIRED };

test("reviewCompletion reviews the story and its last part, stores both, then notifies", async () => {
  const { deps, calls, lines } = completionDeps();
  await reviewCompletion(completionJob, deps);
  assert.equal(calls.reviewStory, 1);
  assert.deepEqual(calls.reviewPart, ["parte 3"]);
  assert.deepEqual(calls.save, [[{ title: "Il drago", mature: false }, MATURE]]);
  assert.equal(calls.notify, 1);
  assert.deepEqual(lines, []);
});

test("reviewCompletion logs a nonsense last part the save reported", async () => {
  const { deps, calls, lines } = completionDeps({ reviewPart: async () => NONSENSE });
  await reviewCompletion(completionJob, deps);
  assert.deepEqual(calls.save, [[{ title: "Il drago", mature: false }, NONSENSE]]);
  assert.equal(calls.notify, 1);
  assert.deepEqual(lines.map((l) => [l.severity, l.message, l.details]), [
    ["warn", "Nonsense part reported", { storyId: "s1", position: "epilogo" }],
  ]);
});

test("reviewCompletion skips the part call when the last part has a verdict", async () => {
  const { deps, calls } = completionDeps({
    read: async () => ({ status: "complete", parts: partsUpTo(4), partReviews: { epilogo: "safe" } }),
  });
  await reviewCompletion(completionJob, deps);
  assert.deepEqual(calls.reviewPart, []);
  assert.deepEqual(calls.save, [[{ title: "Il drago", mature: false }, undefined]]);
});

test("reviewCompletion on a reviewed or deleted story doesn't call Gemini or notify", async () => {
  for (const read of [
    async () => ({ status: "complete", parts: partsUpTo(4), mature: false, reviewedAt: new Date() }),
    async () => undefined,
  ]) {
    const { deps, calls } = completionDeps({ read });
    await reviewCompletion(completionJob, deps);
    assert.deepEqual(calls, { reviewStory: 0, reviewPart: [], save: [], notify: 0 });
  }
});

test("reviewCompletion doesn't notify when another run set reviewedAt first", async () => {
  const { deps, calls } = completionDeps({ save: async () => false });
  await reviewCompletion(completionJob, deps);
  assert.equal(calls.notify, 0);
});

test("reviewCompletion writes nothing and throws if either call fails while the event is young", async () => {
  for (const overrides of [
    { reviewStory: async () => Promise.reject(new Error("503")) },
    { reviewPart: async () => Promise.reject(new Error("503")) },
  ]) {
    const { deps, calls, lines } = completionDeps(overrides);
    await assert.rejects(reviewCompletion(completionJob, deps));
    assert.deepEqual(calls.save, []);
    assert.equal(calls.notify, 0);
    assert.deepEqual(lines.map((l) => l.message), ["Story review failed, retrying"]);
  }
});

test("reviewCompletion gives up quietly once the event is past the cap", async () => {
  const { deps, calls, lines } = completionDeps({
    reviewPart: async () => Promise.reject(new Error("503")),
    now: () => LATE,
  });
  await reviewCompletion(completionJob, deps);
  assert.deepEqual(calls.save, []);
  assert.deepEqual(lines.map((l) => [l.severity, l.message]), [["error", "Story review gave up"]]);
});

test("reviewCompletion logs a notification error instead of throwing", async () => {
  const { deps, lines } = completionDeps({ notify: async () => Promise.reject(new Error("fcm")) });
  await reviewCompletion(completionJob, deps);
  assert.deepEqual(lines.map((l) => l.message), ["Story completed notification failed"]);
});

test("reviewCompletion warns when the model gives no title", async () => {
  const { deps, lines } = completionDeps({ reviewStory: async () => ({ mature: false }) });
  await reviewCompletion(completionJob, deps);
  assert.deepEqual(lines.map((l) => [l.severity, l.message]), [["warn", "Model returned no usable title"]]);
});

// --- B12: review-complete-stories.js --mark-legacy -----------------------

test("isLegacyReviewed picks complete stories reviewed before reviewedAt", () => {
  assert.equal(isLegacyReviewed({ status: "complete", mature: false, title: "Il drago" }), true);
  assert.equal(isLegacyReviewed({ status: "complete", mature: true }), true);
});

test("isLegacyReviewed skips part-era, marked and unreviewed stories", () => {
  const legacy = { status: "complete", mature: false, title: "Il drago" };
  assert.equal(isLegacyReviewed({ ...legacy, partReviews: { epilogo: "safe" } }), false);
  assert.equal(isLegacyReviewed({ ...legacy, reviewedAt: new Date() }), false);
  assert.equal(isLegacyReviewed({ status: "complete", title: "Il drago" }), false);
  assert.equal(isLegacyReviewed({ status: "complete", mature: null }), false);
});

// --- B9/B11: the backfill scripts never notify ---------------------------

test("the backfill scripts send no push notifications", () => {
  for (const script of ["review-complete-stories.js", "review-incomplete-parts.js"]) {
    const source = fs.readFileSync(path.join(__dirname, "..", "scripts", script), "utf8");
    assert.doesNotMatch(source, /\b(notify\w*|sendToUsers)\s*\(/, script);
    assert.doesNotMatch(source, /notifications(\.js)?["']/, script);
  }
});
