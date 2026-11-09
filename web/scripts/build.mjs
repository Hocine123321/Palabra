// Builds the web app into web/dist: public/ as is, the bundled script and the stylesheet.
import { build } from "esbuild";
import { cpSync, mkdirSync, rmSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

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
