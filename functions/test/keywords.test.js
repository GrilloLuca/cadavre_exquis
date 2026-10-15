// Unit tests for the pure helpers in src/keywords.ts. Run with `npm test`
// (builds first).
const test = require("node:test");
const assert = require("node:assert/strict");
const { cleanKeywords, keywordsPartCountFor } = require("../lib/keywords.js");

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

test("keywordsPartCountFor ignores the last part, which completes the story", () => {
  const parts = [part("a"), part("b"), part("c")];
  const before = { status: "incomplete", parts };
  const after = { status: "complete", parts: [...parts, part("d")] };
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
