import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const theme = readFileSync(new URL("../../Palabra/Core/DesignSystem/Theme.swift", import.meta.url), "utf8");
const css = readFileSync(new URL("../src/app.css", import.meta.url), "utf8");
const kebab = (s) => s.replace(/[A-Z]/g, (c) => "-" + c.toLowerCase());
const hex = (n) => n.toLowerCase().replace(/^0x/, "");

/** The `:root` block, and the one inside `@media (prefers-color-scheme: dark)`. */
const dark = css.slice(css.indexOf("prefers-color-scheme: dark"));
const light = css.slice(0, css.indexOf("prefers-color-scheme: dark"));
const has = (block, name, value) => new RegExp(`--${name}:\\s*#${value}\\b`, "i").test(block);

test("paired colours match Theme.swift in light and dark", () => {
  for (const name of ["surface", "ink", "inkSecondary", "fill", "accentDeep", "accentSoft"]) {
    const m = theme.match(new RegExp(`static let ${name} = Color\\(lightHex: (0x[0-9A-Fa-f]+), darkHex: (0x[0-9A-Fa-f]+)\\)`));
    assert.ok(m, `${name} found in Theme.swift`);
    assert.ok(has(light, kebab(name), hex(m[1])), `--${kebab(name)} light #${hex(m[1])}`);
    assert.ok(has(dark, kebab(name), hex(m[2])), `--${kebab(name)} dark #${hex(m[2])}`);
  }
});

test("the single accent matches Theme.swift", () => {
  const m = theme.match(/static let accent = Color\(hex: (0x[0-9A-Fa-f]+)\)/);
  assert.ok(m);
  assert.ok(has(light, "accent", hex(m[1])));
});
