import test from "node:test";
import assert from "node:assert/strict";
import { esc, renderLibrary, renderStudy, renderStatus } from "../src/ui/render.js";

const evil = '<img src=x onerror="alert(1)">';
const snap = {
  words: [{ id: "1", key: evil, spanish: evil, translation: '"><script>x</script>', partOfSpeech: "n", category: "<b>Sec</b>", tags: ["t'ag"], createdAt: "" }],
  decks: [{ id: "d", name: evil, kind: "user", total: 3, due: 1, new: 1 }],
  review: [{ wordID: "w", headword: evil, translation: evil, score: 0.4 }],
  wordsPerDay: [{ day: "2026-11-07", count: 1 }],
};

test("esc handles every dangerous character and null", () => {
  assert.equal(esc(`<>&"'`), "&lt;&gt;&amp;&quot;&#39;");
  assert.equal(esc(null), ""); assert.equal(esc(5), "5");
});

test("nothing from the phone can become markup, anywhere", () => {
  for (const html of [renderLibrary(snap), renderStudy(snap), renderStatus({ state: "error", message: evil })]) {
    assert.ok(!html.includes("<img"), html);
    assert.ok(!html.includes("<script"), html);
    assert.ok(!html.includes("<b>Sec"), html);
    assert.ok(!/onerror="/.test(html), html);
  }
  assert.ok(renderLibrary(snap).includes("&lt;img src=x onerror=&quot;alert(1)&quot;&gt;"));
});

test("library shows its states", () => {
  assert.match(renderLibrary({ words: [] }), /No words yet/);
  assert.match(renderLibrary(snap, { query: "zzzz" }), /No matches/);
  const html = renderLibrary({ words: [{ id: "1", key: "hola", spanish: "hola", translation: "hello", partOfSpeech: "interj", category: null, tags: [] }] });
  assert.match(html, /No section/); assert.match(html, /1 of 1/); assert.match(html, /var\(--tint-5\)/);
});

test("study shows decks, review and the empty states", () => {
  const html = renderStudy(snap);
  assert.match(html, /<b>1<\/b> due/); assert.match(html, /Needs review/); assert.match(html, /Words added per day/);
  assert.match(renderStudy({}), /No decks yet/); assert.match(renderStudy({}), /Nothing is flagged/);
});

test("the status line names the state", () => {
  assert.match(renderStatus({ state: "linked", takenAt: null }), /Linked to your phone/);
  assert.match(renderStatus({ state: "away", takenAt: "2026-11-07T11:00:00Z", now: new Date("2026-11-07T12:00:00Z") }), /Phone away[^]*Synced 1 h ago/);
});
