import test from "node:test";
import assert from "node:assert/strict";
import { placementToken } from "../src/ui/model.js";

// The same vectors are asserted in PalabraTests/WebLink/PlacementTokenTests.swift. Change one side, change both.
export const VECTORS = [
  [null, [], "|"],
  ["Food", [], "Food|"],
  ["Food", ["b", "a"], "Food|a,b"],
  [null, ["z", "a", "m"], "|a,m,z"],
  ["a|b", ["c,d"], "a\\|b|c\\,d"],
  ["back\\slash", [], "back\\\\slash|"],
  ["Café", ["niño", "año"], "Café|año,niño"],
  [null, ["\u{1F600}", "\uFF5E"], "|\uFF5E,\u{1F600}"],   // UTF-8 puts U+FF5E first; UTF-16 code units would put the emoji first
];

test("the placement token matches the agreed vectors", () => {
  for (const [category, tags, expected] of VECTORS) assert.equal(placementToken(category, tags), expected, JSON.stringify([category, tags]));
});

test("different placements never share a token, and tag order does not matter", () => {
  assert.notEqual(placementToken("a|b", []), placementToken("a", ["b"]));
  assert.notEqual(placementToken("a", ["b,c"]), placementToken("a", ["b", "c"]));
  assert.equal(placementToken("x", ["b", "a"]), placementToken("x", ["a", "b"]));
});
