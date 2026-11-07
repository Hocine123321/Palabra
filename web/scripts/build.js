// Bundles web/src into one self-contained palabra-web.html: styles inlined, every module inlined, no external URLs.
// No dependencies on purpose. Usage: node scripts/build.js [outfile]   (default: dist/palabra-web.html)
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, resolve, relative } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const src = (p) => resolve(root, "src", p);

/** Inlines ES modules: strips import lines and export keywords, in dependency order. Names must be unique across modules. */
export function bundle(entry) {
  const order = [], seen = new Set();
  const visit = (file) => {
    if (seen.has(file)) return;
    seen.add(file);
    const code = readFileSync(file, "utf8");
    for (const m of code.matchAll(/^import\s+[^;]*?from\s+"(\.[^"]+)";?\s*$/gm)) visit(resolve(dirname(file), m[1]));
    order.push(file);
  };
  visit(entry);
  const declared = new Map();
  const parts = order.map((file) => {
    const code = readFileSync(file, "utf8")
      .replace(/^import\s+[^;]*?from\s+"[^"]+";?\s*$/gm, "")
      .replace(/^export\s+(async\s+function|function|class|const|let)\b/gm, "$1")
      .replace(/^export\s*\{[^}]*\};?\s*$/gm, "");
    for (const m of code.matchAll(/^(?:async\s+function|function|class|const|let)\s+([A-Za-z_$][\w$]*)/gm)) {
      if (declared.has(m[1])) throw new Error(`name "${m[1]}" is declared in both ${relative(root, declared.get(m[1]))} and ${relative(root, file)}`);
      declared.set(m[1], file);
    }
    return `// ---- ${relative(root, file)}\n${code}`;
  });
  return parts.join("\n");
}

export function build() {
  const html = readFileSync(src("ui/index.html"), "utf8");
  const css = readFileSync(src("ui/tokens.css"), "utf8") + "\n" + readFileSync(src("ui/app.css"), "utf8");
  const js = bundle(src("ui/main.js"));
  if (/<\/script/i.test(js)) throw new Error("a script contains </script>");
  return html.replace("/*CSS*/", () => css).replace("/*JS*/", () => js);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const out = resolve(root, process.argv[2] ?? "dist/palabra-web.html");
  mkdirSync(dirname(out), { recursive: true });
  const html = build();
  writeFileSync(out, html);
  console.log(`${relative(process.cwd(), out)}  ${(Buffer.byteLength(html) / 1024).toFixed(1)} KB`);
}
