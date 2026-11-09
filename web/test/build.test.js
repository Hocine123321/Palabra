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

test("the built page has no inline script, no inline style and loads its own bundle", () => {
  execFileSync("node", [join(web, "scripts/build.mjs")], { stdio: "pipe" });
  const html = readFileSync(join(web, "dist/index.html"), "utf8");
  assert.ok(existsSync(join(web, "dist/app.js")), "dist/app.js exists");
  assert.ok(existsSync(join(web, "dist/app.css")), "dist/app.css exists");
  assert.ok(!/<script(?![^>]*\bsrc=)[^>]*>/i.test(html), "every script has a src");
  assert.ok(!/<script[^>]*>[^<]+<\/script>/i.test(html), "no inline script body");
  assert.ok(!/<style\b/i.test(html) && !/\sstyle=/i.test(html), "no inline style");
  assert.match(html, /<script type="module" src="\/app\.js">/);
  const bundle = readFileSync(join(web, "dist/app.js"), "utf8");
  assert.ok(!/\.innerHTML\s*=|document\.write|\beval\(/.test(bundle), "the bundle never writes markup or evals");
});
