import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { build } from "../scripts/build.js";

const html = build();

test("the file is one self-contained page: no external loads, no leftover module syntax", () => {
  assert.ok(!/<link\b[^>]*href/i.test(html), "no linked stylesheets");
  assert.ok(!/<script\b[^>]*\bsrc=/i.test(html), "no external scripts");
  assert.ok(!/@import|url\(\s*["']?https?:/i.test(html), "no CSS imports");
  assert.ok(!/\b(?:src|href)=["']https?:/i.test(html), "no remote attributes");
  assert.ok(!/^(import|export)\b/m.test(html), "modules are inlined");
  assert.ok(!html.includes("/*CSS*/") && !html.includes("/*JS*/"), "placeholders replaced");
});

test("the only script is one inline module, and it parses and starts", () => {
  const scripts = [...html.matchAll(/<script type="module">([\s\S]*?)<\/script>/g)];
  assert.equal(scripts.length, 1);
  // Parse as a function body (the bundle has no import/export left) and run it against a minimal page stub.
  const listeners = {};
  const el = () => ({ addEventListener: (e, f) => { listeners[e] = f; }, hidden: false, toggleAttribute: () => false, removeAttribute() {}, setAttribute() {}, dataset: {}, style: {} });
  const sandbox = {
    document: { querySelector: () => el(), querySelectorAll: () => [], documentElement: {} }, navigator: { languages: ["ar"], language: "ar" },
    location: { protocol: "file:" }, crypto: globalThis.crypto, TextEncoder, TextDecoder, atob, btoa, fetch: () => { throw new Error("no network at start"); },
    WebSocket: class { constructor() { throw new Error("no socket at start"); } }, console,
  };
  vm.createContext(sandbox);
  assert.doesNotThrow(() => vm.runInContext(scripts[0][1], sandbox), "starting the page must not touch the network");
});

test("every visible string the page ships is in the bundle (guards against a broken build)", () => {
  for (const text of ["Palabra on your computer", "Library", "Study", "No words yet", "Needs review", "Linked to your phone"]) {
    assert.ok(html.includes(text), text);
  }
});

test("the page stays small: far below any size that would matter", () => {
  assert.ok(Buffer.byteLength(html) < 400 * 1024, `${Buffer.byteLength(html)} bytes`);
});

test("the colours in the bundled CSS are the app's tokens", () => {
  assert.ok(html.includes("--accent: #D97757"));
});
