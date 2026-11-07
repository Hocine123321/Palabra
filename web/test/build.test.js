import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const web = join(dirname(fileURLToPath(import.meta.url)), "..");

test("build copies the page and the security headers into dist", () => {
  execFileSync("node", [join(web, "scripts/build.mjs")], { stdio: "pipe" });
  const index = join(web, "dist/index.html");
  const headers = join(web, "dist/_headers");
  assert.ok(existsSync(index), "dist/index.html exists");
  assert.match(readFileSync(index, "utf8"), /Palabra/);
  assert.ok(existsSync(headers), "dist/_headers exists");
  const text = readFileSync(headers, "utf8");
  assert.match(text, /frame-ancestors 'none'/);
  assert.match(text, /script-src 'self'/);
});
