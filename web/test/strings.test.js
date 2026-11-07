import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { AR, makeT, pickLanguage, dirFor } from "../src/ui/strings.js";
import { renderLibrary, renderStudy, renderStatus } from "../src/ui/render.js";

const ui = (f) => readFileSync(new URL(`../src/ui/${f}`, import.meta.url), "utf8");

test("every t(\"...\") key used in the code has an Arabic string", () => {
  const keys = new Set();
  for (const f of ["render.js", "shell.js"]) for (const m of ui(f).matchAll(/\bt\(\s*[`"]([^`"$]+)[`"]\s*\)/g)) keys.add(m[1]);
  for (const unit of ["min", "h", "d"]) keys.add(`Synced {n} ${unit} ago`);
  assert.ok(keys.size > 20, `only found ${keys.size} keys: the scan is broken`);
  for (const k of keys) assert.ok(AR[k], `missing Arabic for: ${k}`);
});

test("every data-i18n text in the page template has an Arabic string", () => {
  const html = ui("index.html");
  const found = [...html.matchAll(/data-i18n(?:-[a-z]+)?="([^"]+)"/g)].map((m) => m[1]);
  assert.ok(found.length >= 8, `only ${found.length} marked texts`);
  for (const k of found) assert.ok(AR[k], `missing Arabic for: ${k}`);
});

test("no Arabic string is empty, and placeholders match the English key", () => {
  for (const [k, v] of Object.entries(AR)) {
    assert.ok(v.trim().length > 0, k);
    assert.deepEqual((v.match(/\{\w+\}/g) ?? []).sort(), (k.match(/\{\w+\}/g) ?? []).sort(), `placeholders differ: ${k}`);
  }
});

test("language choice and direction", () => {
  assert.equal(pickLanguage(["ar-DZ", "en"]), "ar"); assert.equal(pickLanguage(["fr", "en-US"]), "en"); assert.equal(pickLanguage(), "en");
  assert.equal(dirFor("ar"), "rtl"); assert.equal(dirFor("en"), "ltr");
  assert.equal(makeT("en")("Library"), "Library"); assert.equal(makeT("ar")("Library"), "المكتبة"); assert.equal(makeT("ar")("unknown key"), "unknown key");
});

test("the screens really come out in Arabic, with the phone's own data untouched", () => {
  const t = makeT("ar");
  const snap = { words: [{ id: "1", key: "hola", spanish: "hola", translation: "hello", partOfSpeech: "n", category: null, tags: [] }],
    decks: [{ id: "d", name: "Vocabulary", kind: "vocabulary", total: 4, due: 2, new: 1 }], review: [], wordsPerDay: [{ day: "2026-11-07", count: 3 }] };
  const lib = renderLibrary(snap, {}, t), study = renderStudy(snap, t);
  assert.match(lib, /بدون قسم/); assert.match(lib, /ابحث في الكلمات/); assert.match(lib, /hola/);
  assert.match(study, /مستحقة اليوم/); assert.match(study, /Vocabulary/); assert.match(study, /أُضيفت 3 كلمة خلال آخر 1 أيام/);
  assert.match(renderLibrary({ words: [] }, {}, t), /لا توجد كلمات بعد/);
  assert.match(renderStatus({ state: "away", takenAt: "2026-11-07T09:00:00Z", now: new Date("2026-11-07T12:00:00Z") }, t), /آخر مزامنة منذ 3 س/);
});

import { errorText } from "../src/ui/strings.js";
import { explainFetchFailure } from "../src/link-client.js";
import { reasonText } from "../src/link-rpc.js";

test("every error message the link can show has an Arabic version", () => {
  const ar = makeT("ar"), en = makeT("en");
  const fixed = [
    "Type the phone's address like 192.168.1.20", "The code is at least 6 digits.",
    "The phone is not accepting a pairing. Open Pair a Browser on the phone.", "The phone refused. Open Pair a Browser on the phone and try again.",
    "The phone's answer could not be opened.", "Could not reach the relay. Check its address.",
    explainFetchFailure(new Error("x"), { isFileOrigin: true }).message, explainFetchFailure(new Error("x"), { isFileOrigin: false }).message,
    ...["no-answer", "link-lost", "forbidden", "bad-args", "rate-limited", "failed"].map(reasonText),
  ];
  for (const message of fixed) {
    assert.notEqual(errorText({ message }, ar), message, `no Arabic for: ${message}`);
    assert.equal(errorText({ message }, en), message);
  }
});

test("errors with numbers are translated with the number in place", () => {
  const ar = makeT("ar"), en = makeT("en");
  assert.equal(errorText({ kind: "locked", seconds: 30, message: "x" }, en), "Too many wrong codes. Try again in 30 seconds.");
  assert.equal(errorText({ kind: "locked", seconds: 30, message: "x" }, ar), "رموز خاطئة كثيرة. حاول مجدداً بعد 30 ثانية.");
  assert.equal(errorText({ kind: "wrong", triesLeft: 4, message: "x" }, ar), "رمز خاطئ. تبقّت 4 محاولات.");
  assert.equal(errorText({ kind: "wrong", triesLeft: 4, message: "x" }, en), "Wrong code. 4 tries left.");
  assert.equal(errorText(new Error("something odd"), ar), "something odd");   // unknown errors still show what they say
});
