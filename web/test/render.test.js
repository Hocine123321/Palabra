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

import { renderAddWords, renderChanges, describeChange } from "../src/ui/render.js";
import { makeT } from "../src/ui/strings.js";
import { reasonText } from "../src/link-rpc.js";

test("nothing is shown when there are no changes", () => {
  assert.equal(renderChanges({ queue: [], review: [] }), "");
});

test("waiting changes can be cancelled and refused ones can be retried or dropped, with the reason in plain words", () => {
  const html = renderChanges({
    queue: [{ id: "q1", capability: "words.add", args: { words: ["a", "b"] } }],
    review: [{ id: "r1", capability: "words.place", args: { words: ["x"] }, reason: "conflict" }],
  }, makeT("en"), reasonText);
  assert.match(html, /Add 2 words/); assert.match(html, /data-cancel="q1"/);
  assert.match(html, /Organise 1 words/); assert.match(html, /data-retry="r1"/); assert.match(html, /data-drop="r1"/);
  assert.match(html, /changed on the phone/);
});

test("changes render in Arabic, and text from the phone or the person is escaped", () => {
  const html = renderChanges({ queue: [{ id: '"><img src=x onerror=alert(1)>', capability: "words.add", args: { words: [] } }], review: [] }, makeT("ar"));
  assert.match(html, /بانتظار الهاتف/);
  assert.doesNotMatch(html, /<img/);
  assert.match(renderAddWords(makeT("ar")), /أضف/);
  assert.equal(describeChange({ capability: "zzz" }, makeT("en")), "A change");
});
