// Builds the web app into web/dist: public/ as is, the bundled script and the stylesheet.
import { build } from "esbuild";
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { SHELL, versionFor } from "./shell.mjs";

const web = join(dirname(fileURLToPath(import.meta.url)), "..");
const dist = join(web, "dist");

rmSync(dist, { recursive: true, force: true });
mkdirSync(dist, { recursive: true });
cpSync(join(web, "public"), dist, { recursive: true });
cpSync(join(web, "src/app.css"), join(dist, "app.css"));
await build({
  entryPoints: [join(web, "src/main.js")],
  outfile: join(dist, "app.js"),
  bundle: true,
  format: "iife",
  minify: true,
  target: "es2022",
  legalComments: "none",
  logLevel: "silent",
});

// The service worker: the template with the shell list and a version taken from the shell files' content.
const files = new Map(SHELL.map((path) => [path, readFileSync(join(dist, path === "/" ? "index.html" : path))]));
const template = readFileSync(join(web, "src/sw.js"), "utf8");
writeFileSync(join(dist, "sw.js"), template.replace("__VERSION__", versionFor(files)).replace("__SHELL__", JSON.stringify(SHELL)));
