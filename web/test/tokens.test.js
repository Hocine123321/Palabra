import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";

const css = readFileSync(new URL("../src/ui/tokens.css", import.meta.url), "utf8");
const themePath = new URL("../../Palabra/Core/DesignSystem/Theme.swift", import.meta.url);
const hex = (n) => "#" + n.toString(16).toUpperCase().padStart(6, "0");

test("every colour token matches Theme.swift (light, then dark)", { skip: !existsSync(themePath) }, () => {
  const swift = readFileSync(themePath, "utf8");
  const light = css.split("@media")[0], dark = css.split("@media")[1];
  const pairs = {
    "--bg-top": "backgroundTop", "--bg-bottom": "backgroundBottom", "--surface": "surface", "--ink": "ink",
    "--ink-2": "inkSecondary", "--fill": "fill", "--accent-deep": "accentDeep", "--accent-soft": "accentSoft",
    "--error": "error", "--success": "success",
  };
  for (const [token, name] of Object.entries(pairs)) {
    const m = new RegExp(`static let ${name} = Color\\(lightHex: 0x([0-9A-Fa-f]{6}), darkHex: 0x([0-9A-Fa-f]{6})\\)`).exec(swift);
    assert.ok(m, `${name} not found in Theme.swift`);
    const get = (block) => new RegExp(`${token}:\\s*(#[0-9A-Fa-f]{6})`).exec(block)?.[1]?.toUpperCase();
    assert.equal(get(light), hex(parseInt(m[1], 16)), `${token} light`);
    assert.equal(get(dark) ?? get(light), hex(parseInt(m[2], 16)), `${token} dark`);
  }
  assert.equal(/--accent:\s*(#[0-9A-Fa-f]{6})/.exec(light)[1].toUpperCase(), "#D97757");
});

test("radii and spacing match Theme.swift", { skip: !existsSync(themePath) }, () => {
  const swift = readFileSync(themePath, "utf8");
  const num = (name) => Number(new RegExp(`static let ${name}: CGFloat = (\\d+)`).exec(swift)[1]);
  const px = (token) => Number(new RegExp(`${token}:\\s*(\\d+)px`).exec(css)[1]);
  for (const [t, n] of [["--sp-xs", "xs"], ["--sp-sm", "sm"], ["--sp-md", "md"], ["--sp-lg", "lg"], ["--sp-xl", "xl"],
    ["--r-small", "small"], ["--r-medium", "medium"], ["--r-card", "card"], ["--r-sheet", "sheet"], ["--r-pill", "pill"]]) {
    assert.equal(px(t), num(n), t);
  }
});

test("the tile tints are the app's six", { skip: !existsSync(themePath) }, () => {
  const swift = readFileSync(themePath, "utf8");
  const tints = [...css.matchAll(/--tint-\d:\s*(#[0-9A-Fa-f]{6})/g)].map((m) => m[1].toUpperCase());
  assert.equal(tints.length, 6);
  for (const t of tints) assert.ok(new RegExp(t.slice(1), "i").test(swift), `${t} missing from Theme.swift`);
});
