import assert from "node:assert/strict";

export const MARKUP = "<img src=x onerror=alert(1)>";

export function walk(node, fn) {
  fn(node);
  for (const c of node.children ?? []) if (typeof c !== "string") walk(c, fn);
}
export const texts = (tree) => { const out = []; walk(tree, (n) => n.children?.forEach((c) => typeof c === "string" && out.push(c))); return out; };
export const tags = (tree) => { const out = []; walk(tree, (n) => out.push(n.tag)); return out; };
/** Text nodes only: no element named img/script/iframe/svg-script anywhere, no handler or style anywhere, no attribute carrying the markup. */
export function assertTextOnly(tree, where) {
  walk(tree, (n) => {
    assert.ok(!["img", "script", "iframe", "object", "embed"].includes(n.tag), `${where}: <${n.tag}>`);
    for (const [name, value] of Object.entries(n.attrs ?? {})) {
      assert.ok(!/^on/i.test(name) && name !== "style" && name !== "innerHTML", `${where}: attribute ${name}`);
      assert.ok(!String(value).includes("onerror"), `${where}: attribute ${name} carries data`);
    }
    assert.deepEqual(Object.keys(n.handlers ?? {}).filter((k) => k !== "click"), [], `${where}: handlers`);
  });
}

