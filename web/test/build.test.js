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

// MARK: Installable app and service worker

import { SHELL, versionFor } from "../scripts/shell.mjs";

function pngSize(file) {
  const bytes = readFileSync(file);
  assert.equal(bytes.subarray(1, 4).toString("latin1"), "PNG", `${file} is a PNG`);
  return [bytes.readUInt32BE(16), bytes.readUInt32BE(20)];
}

test("dist/sw.js is filled in: no placeholders, every shell path exists, same input gives the same version", () => {
  execFileSync("node", [join(web, "scripts/build.mjs")], { stdio: "pipe" });
  const first = readFileSync(join(web, "dist/sw.js"), "utf8");
  assert.ok(!first.includes("__VERSION__") && !first.includes("__SHELL__"), "placeholders replaced");
  for (const path of SHELL) assert.ok(existsSync(join(web, "dist", path === "/" ? "index.html" : path)), `${path} is in dist`);
  const version = first.match(/const VERSION = "([0-9a-f]{12})"/)?.[1];
  assert.ok(version, "a 12-hex version");
  execFileSync("node", [join(web, "scripts/build.mjs")], { stdio: "pipe" });
  assert.equal(readFileSync(join(web, "dist/sw.js"), "utf8"), first, "deterministic");
  assert.ok(first.includes(JSON.stringify(SHELL)), "the shell list is embedded");
});

test("the version follows the content of the shell files", () => {
  const a = new Map([["/", Buffer.from("x")], ["/app.js", Buffer.from("y")]]);
  const b = new Map([["/", Buffer.from("x")], ["/app.js", Buffer.from("z")]]);
  assert.equal(versionFor(a), versionFor(new Map(a)));
  assert.notEqual(versionFor(a), versionFor(b));
  assert.match(versionFor(a), /^[0-9a-f]{12}$/);
});

test("the web manifest has what installing needs and its icons are real PNGs of the declared size", () => {
  execFileSync("node", [join(web, "scripts/build.mjs")], { stdio: "pipe" });
  const manifest = JSON.parse(readFileSync(join(web, "dist/manifest.webmanifest"), "utf8"));
  assert.deepEqual(
    { name: manifest.name, short_name: manifest.short_name, start_url: manifest.start_url, scope: manifest.scope, display: manifest.display, background_color: manifest.background_color, theme_color: manifest.theme_color },
    { name: "Palabra", short_name: "Palabra", start_url: "/", scope: "/", display: "standalone", background_color: "#fcfbf8", theme_color: "#d97757" },
  );
  assert.deepEqual(manifest.icons.map((i) => [i.sizes, i.purpose]), [["192x192", "any"], ["512x512", "any"], ["512x512", "maskable"]]);
  for (const icon of manifest.icons) {
    const [w, h] = icon.sizes.split("x").map(Number);
    assert.deepEqual(pngSize(join(web, "dist", icon.src)), [w, h], icon.src);
  }
});

test("index.html links the manifest, theme colour and apple icon; headers keep sw.js fresh and the CSP allows workers and manifests", () => {
  execFileSync("node", [join(web, "scripts/build.mjs")], { stdio: "pipe" });
  const html = readFileSync(join(web, "dist/index.html"), "utf8");
  assert.match(html, /<link rel="manifest" href="\/manifest\.webmanifest">/);
  assert.match(html, /<meta name="theme-color" content="#d97757">/);
  assert.match(html, /<link rel="apple-touch-icon" href="\/icons\/icon-192\.png">/);
  const headers = readFileSync(join(web, "dist/_headers"), "utf8");
  assert.match(headers, /\/sw\.js\n\s+Cache-Control: no-cache/);
  assert.match(headers, /worker-src 'self'/);
  assert.match(headers, /manifest-src 'self'/);
  assert.ok(!/<script(?![^>]*\bsrc=)[^>]*>/i.test(html), "still no inline script");
});

test("the page registers the worker only when supported and ignores a failed registration", () => {
  const main = readFileSync(join(web, "src/main.js"), "utf8");
  assert.match(main, /"serviceWorker" in navigator/);
  assert.match(main, /register\("\/sw\.js"\)\.catch\(\(\) => \{\}\)/);
});
