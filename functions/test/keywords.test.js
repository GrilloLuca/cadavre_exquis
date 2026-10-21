// Unit tests for the pure helpers in src/keywords.ts. Run with `npm test`
// (builds first).
const test = require("node:test");
const assert = require("node:assert/strict");
const { canSaveKeywords, cleanKeywords, keywordsPartCountFor } = require("../lib/keywords.js");

const part = (text) => ({ position: "x", text, author: "ada@x.com" });

test("keywordsPartCountFor returns the new part count when a part is added", () => {
  const before = { status: "incomplete", parts: [part("a")] };
  const after = { status: "incomplete", parts: [part("a"), part("b")] };
  assert.equal(keywordsPartCountFor(before, after), 2);
});

test("keywordsPartCountFor counts the first part of a story", () => {
  assert.equal(keywordsPartCountFor({ status: "incomplete", parts: [] }, { status: "incomplete", parts: [part("a")] }), 1);
});

test("keywordsPartCountFor ignores lock changes", () => {
  const before = { status: "incomplete", parts: [part("a")], lockedBy: null };
  const after = { status: "incomplete", parts: [part("a")], lockedBy: "bob@x.com" };
  assert.equal(keywordsPartCountFor(before, after), undefined);
});

test("keywordsPartCountFor counts the last part, which completes the story", () => {
  const parts = [part("a"), part("b"), part("c")];
  const before = { status: "incomplete", parts, keywords: ["drago"], keywordsPartCount: 3 };
  const after = { ...before, status: "complete", parts: [...parts, part("d")] };
  assert.equal(keywordsPartCountFor(before, after), 4);
});

test("keywordsPartCountFor ignores the review write on a complete story", () => {
  const parts = [part("a"), part("b"), part("c"), part("d")];
  const before = { status: "complete", parts };
  const after = { ...before, title: "Il drago", mature: false };
  assert.equal(keywordsPartCountFor(before, after), undefined);
});

test("keywordsPartCountFor ignores the keywords write on a complete story", () => {
  const parts = [part("a"), part("b"), part("c"), part("d")];
  const before = { status: "complete", parts, keywords: ["drago"], keywordsPartCount: 3 };
  const after = { ...before, keywords: ["drago", "faro"], keywordsPartCount: 4 };
  assert.equal(keywordsPartCountFor(before, after), undefined);
});

test("keywordsPartCountFor ignores the keywords write itself", () => {
  const before = { status: "incomplete", parts: [part("a"), part("b")] };
  const after = { ...before, keywords: ["drago"], keywordsPartCount: 2 };
  assert.equal(keywordsPartCountFor(before, after), undefined);
});

test("keywordsPartCountFor ignores legacy documents without parts", () => {
  assert.equal(keywordsPartCountFor({ status: "incomplete" }, { status: "incomplete" }), undefined);
});

const parts4 = [part("a"), part("b"), part("c"), part("d")];

test("canSaveKeywords accepts an incomplete story with the same parts and no keywords", () => {
  assert.equal(canSaveKeywords({ status: "incomplete", parts: [part("a"), part("b")] }, 2), true);
});

test("canSaveKeywords accepts a complete story without keywords", () => {
  assert.equal(canSaveKeywords({ status: "complete", parts: parts4 }, 4), true);
});

test("canSaveKeywords accepts a complete story with keywords from fewer parts", () => {
  assert.equal(canSaveKeywords({ status: "complete", parts: parts4, keywords: ["drago"], keywordsPartCount: 3 }, 4), true);
});

test("canSaveKeywords refuses a deleted story", () => {
  assert.equal(canSaveKeywords(undefined, 4), false);
});

test("canSaveKeywords refuses unknown or missing statuses", () => {
  assert.equal(canSaveKeywords({ status: "deleted", parts: parts4 }, 4), false);
  assert.equal(canSaveKeywords({ parts: parts4 }, 4), false);
});

test("canSaveKeywords refuses a mismatched part count", () => {
  assert.equal(canSaveKeywords({ status: "incomplete", parts: [part("a"), part("b"), part("c")] }, 2), false);
  assert.equal(canSaveKeywords({ status: "complete", parts: parts4 }, 3), false);
  assert.equal(canSaveKeywords({ status: "incomplete" }, 1), false);
});

test("canSaveKeywords refuses when keywords from as many parts or more are stored", () => {
  assert.equal(canSaveKeywords({ status: "complete", parts: parts4, keywordsPartCount: 4 }, 4), false);
  assert.equal(canSaveKeywords({ status: "complete", parts: parts4, keywordsPartCount: 5 }, 4), false);
});

test("cleanKeywords keeps at most 4 keywords", () => {
  assert.deepEqual(cleanKeywords(["a", "b", "c", "d", "e"]), ["a", "b", "c", "d"]);
});

test("cleanKeywords drops duplicates case-insensitively, keeping the first", () => {
  assert.deepEqual(cleanKeywords(["Drago", "faro", "drago", "FARO", "tempesta"]), ["Drago", "faro", "tempesta"]);
});

test("cleanKeywords strips quotes, hashes and punctuation at the ends", () => {
  assert.deepEqual(cleanKeywords(['"drago"', "#faro", "«tempesta».", " segreto! "]), [
    "drago",
    "faro",
    "tempesta",
    "segreto",
  ]);
  assert.deepEqual(cleanKeywords(["l'isola", "vecchio  faro"]), ["l'isola", "vecchio faro"]);
});

test("cleanKeywords caps the length of each keyword", () => {
  const [keyword] = cleanKeywords(["a".repeat(30)]);
  assert.equal(keyword, "a".repeat(24));
  assert.deepEqual(cleanKeywords([`${"a".repeat(23)} bcd`]), ["a".repeat(23)]);
});

test("cleanKeywords drops empty strings and does not count them", () => {
  assert.deepEqual(cleanKeywords(["", "  ", '""', "...", "a", "b", "c", "d"]), ["a", "b", "c", "d"]);
});

test("cleanKeywords drops non-strings", () => {
  assert.deepEqual(cleanKeywords([1, null, { k: "x" }, ["y"], "drago", true]), ["drago"]);
});

test("cleanKeywords gives none for anything that isn't an array", () => {
  assert.deepEqual(cleanKeywords(undefined), []);
  assert.deepEqual(cleanKeywords(null), []);
  assert.deepEqual(cleanKeywords("drago, faro"), []);
  assert.deepEqual(cleanKeywords({ keywords: ["drago"] }), []);
});
