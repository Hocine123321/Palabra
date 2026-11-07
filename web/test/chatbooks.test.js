import test from "node:test";
import assert from "node:assert/strict";
import { renderChat, renderBooks, renderLesson, CHAT_MAX_TURNS } from "../src/ui/chatbooks.js";
import { makeT } from "../src/ui/strings.js";

const t = makeT("en");

test("no chat is a calm empty state, not an error", () => {
  assert.match(renderChat({ chat: null }, t), /No chats yet/);
  assert.match(renderChat(undefined, t), /No chats yet/);
  assert.match(renderChat("junk", t), /No chats yet/);
});

test("a chat is drawn as bubbles, tells who spoke, and never lets text become markup", () => {
  const html = renderChat({ chat: { title: "<img src=x onerror=alert(1)>", turns: [
    { role: "user", text: "<script>alert(1)</script>hola" },
    { role: "assistant", text: "¡Hola!", actions: 2, failed: true },
  ] } }, t);
  assert.ok(!/<script|<img/.test(html), "no raw markup");
  assert.match(html, /bubble me/);
  assert.match(html, /bubble them/);
  assert.match(html, /Ran 2 actions on the phone/);
  assert.match(html, /did not go through/);
});

test("a very long chat shows only the most recent turns, and junk turns do not throw", () => {
  const turns = Array.from({ length: CHAT_MAX_TURNS + 30 }, (_, i) => ({ role: "user", text: `m${i}` }));
  const html = renderChat({ chat: { title: "x", turns: [...turns, null, 5, "x", { role: 7 }] } }, t);
  assert.equal((html.match(/class="bubble/g) ?? []).length, CHAT_MAX_TURNS);
  assert.ok(!html.includes("m0<"), "oldest cut");
});

test("books list every lesson as a button carrying only its ids, escaped", () => {
  const html = renderBooks([{ id: 'b"1', title: "Historia", chapters: [{ title: "Uno", lessons: [{ id: "l1", title: "<b>Roma</b>" }] }] }], t);
  assert.match(html, /data-lesson="l1"/);
  assert.match(html, /data-book="b&quot;1"/);
  assert.ok(!html.includes("<b>Roma"), "escaped");
  assert.match(renderBooks([], t), /No books yet/);
  assert.doesNotThrow(() => renderBooks([null, { chapters: [null, { lessons: [null] }] }], t));
});

test("a lesson shows its text blocks, turns visual blocks into a note, and ignores unknown kinds", () => {
  const html = renderLesson({ title: "Roma", pages: [{ title: "P1", blocks: [
    { kind: "heading", text: "Titulo", level: 2 }, { kind: "text", text: "Hola <i>x</i>" },
    { kind: "list", text: "Cosas", items: ["a", "b"], ordered: true },
    { kind: "keyPoint", text: "Importante", items: ["Ojo"] }, { kind: "quote", text: "Dicho", items: ["Autor"] },
    { kind: "definitions", text: "", items: ["perro: dog", "sin dos puntos"] },
    { kind: "note" }, { kind: "future-thing", text: "SECRET" }, null,
  ] }] }, t);
  assert.match(html, /<h5>Titulo<\/h5>/);
  assert.match(html, /<ol><li>a<\/li><li>b<\/li><\/ol>/);
  assert.match(html, /<dt>perro<\/dt><dd>dog<\/dd>/);
  assert.match(html, /best read on the phone/);
  assert.ok(!html.includes("SECRET") && !html.includes("<i>x"));
  assert.match(renderLesson({ pages: "x" }, t), /could not be shown/);
});

test("everything the Chat and Books tabs say exists in Arabic", () => {
  const ar = makeT("ar");
  for (const key of ["Chat", "Books", "No chats yet", "Your latest chat from the phone appears here.", "Latest chat. To reply, open it on your phone.",
    "Ran {n} actions on the phone", "This message did not go through.", "No books yet", "Lessons are added to the app in updates.",
    "This part is best read on the phone.", "The phone must be connected to show this."]) {
    assert.notEqual(ar(key), key, `Arabic missing: ${key}`);
  }
});
