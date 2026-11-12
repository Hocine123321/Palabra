import { test } from "node:test";
import assert from "node:assert/strict";
import { hrefFor, parseRoute } from "../src/router.js";

test("every route string parses to its screen", () => {
  assert.deepEqual(parseRoute("#/words"), { name: "words", id: null });
  assert.deepEqual(parseRoute("#/words/abc_-9"), { name: "word", id: "abc_-9" });
  assert.deepEqual(parseRoute("#/study"), { name: "study", id: null });
  assert.deepEqual(parseRoute("#/review"), { name: "review", id: null });
  assert.deepEqual(parseRoute("#/artifacts"), { name: "artifacts", id: null });
  assert.deepEqual(parseRoute("#/artifacts/Zz09"), { name: "artifact", id: "Zz09" });
  assert.deepEqual(parseRoute("#/chat"), { name: "chat", id: null });
  assert.deepEqual(parseRoute("#/books"), { name: "books", id: null });
  assert.deepEqual(parseRoute("#/books/Qq-_"), { name: "book", id: "Qq-_" });
});

test("nothing, unknown and half-written routes go to the words list", () => {
  for (const hash of ["", "#", "#/", "#/nope", "#/words/", "#nonsense", undefined, null, 42]) {
    assert.deepEqual(parseRoute(hash), { name: "words", id: null }, String(hash));
  }
});

test("ids are kept exactly as written", () => {
  assert.equal(parseRoute("#/words/A%20b").id, "A%20b");
  assert.equal(parseRoute("#/books/<img src=x>").id, "<img src=x>");
});

test("a link is built from the section and the id", () => {
  assert.equal(hrefFor("words"), "#/words");
  assert.equal(hrefFor("books", "abc"), "#/books/abc");
});
