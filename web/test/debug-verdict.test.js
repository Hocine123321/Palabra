import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { verdict } from "../src/ui/debug-verdict.js";

test("each situation gets one plain sentence and one thing to do", () => {
  assert.equal(verdict({ link: "linked" }).tone, "ok");
  assert.equal(verdict({ link: "away", reason: "phone-away" }).title, "Waiting for your phone");
  assert.equal(verdict({ link: "empty", reason: "relay-timeout" }).title, "Cannot reach the relay");
  assert.equal(verdict({ link: "error" }).tone, "bad");
  assert.equal(verdict({ link: "connecting" }).title, "Connecting…");
  assert.equal(verdict({ link: "away", reason: "failed", failures: 5 }).title, "Your phone is not answering");
  assert.equal(verdict({ link: "away", reason: "failed", failures: 1 }).tone, "wait");
  assert.equal(verdict({ link: "linked", online: false }).title, "Your computer is offline", "offline beats everything");
  assert.equal(verdict().tone, "wait");
});

test("every sentence the verdict can show has an Arabic translation", () => {
  const strings = readFileSync(new URL("../src/ui/strings.js", import.meta.url), "utf8");
  const cases = [{ online: false }, { link: "linked" }, { link: "error" }, { reason: "relay" }, { reason: "phone-away" }, { link: "connecting" }, { failures: 9 }, { link: "away" }, {}];
  for (const c of cases) { const v = verdict(c); for (const key of [v.title, v.help]) assert.ok(strings.includes(`"${key}":`), `missing Arabic for: ${key}`); }
});
