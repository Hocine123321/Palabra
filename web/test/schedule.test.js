import { test } from "node:test";
import assert from "node:assert/strict";
import { refreshDelay } from "../src/schedule.js";

test("an incomplete copy is rechecked soon, six times, then back to the normal pace", () => {
  assert.equal(refreshDelay({ state: "incomplete", incompleteRuns: 0 }), 10_000);
  assert.equal(refreshDelay({ state: "incomplete", incompleteRuns: 5 }), 10_000);
  assert.equal(refreshDelay({ state: "incomplete", incompleteRuns: 6 }), 60_000);
});

test("everything else uses the normal pace", () => {
  for (const state of ["verified", "unverified", null, undefined]) assert.equal(refreshDelay({ state, incompleteRuns: 0 }), 60_000);
});
