// Bundles src/main.js (Three.js + the scene) and the Amiri fonts into ONE html file the app loads offline.
//   node build.mjs            -> ../../Palabra/Resources/Books3D/books3d.html
//   node build.mjs --entry test/pageview.js --out /tmp/x.html   (dev pages)
import { build } from 'esbuild';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const args = process.argv.slice(2);
const arg = (name, fallback) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : fallback; };
const entry = arg('--entry', 'src/main.js');
const out = resolve(arg('--out', '../../Palabra/Resources/Books3D/books3d.html'));

const face = (file, weight, range) => {
  const b64 = readFileSync(`node_modules/@fontsource/amiri/files/${file}`).toString('base64');
  return `@font-face{font-family:Amiri;font-style:normal;font-weight:${weight};font-display:block;src:url(data:font/woff2;base64,${b64}) format('woff2');unicode-range:${range}}`;
};
const ARABIC = 'U+0600-06FF,U+0750-077F,U+0870-088E,U+0890-0891,U+0898-08E1,U+08E3-08FF,U+200C-200E,U+2010-2011,U+204F,U+2E41,U+FB50-FDFF,U+FE70-FE74,U+FE76-FEFC';
const LATIN = 'U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308,U+0329,U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD';
const fonts = [
  face('amiri-arabic-400-normal.woff2', 400, ARABIC), face('amiri-arabic-700-normal.woff2', 700, ARABIC),
  face('amiri-latin-400-normal.woff2', 400, LATIN), face('amiri-latin-700-normal.woff2', 700, LATIN),
].join('\n');

const result = await build({
  entryPoints: [entry], bundle: true, format: 'iife', minify: true, write: false, target: 'safari16', legalComments: 'none',
});
const js = result.outputFiles[0].text.replace(/<\/script/gi, '<\\/script');
const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,viewport-fit=cover,user-scalable=no">
<title>Palabra Books</title>
<style>${fonts}
html,body{margin:0;height:100%;overflow:hidden;background:#1b1a18;-webkit-user-select:none;user-select:none;-webkit-touch-callout:none;-webkit-tap-highlight-color:transparent}
#stage{position:fixed;inset:0;width:100%;height:100%;display:block;touch-action:none;outline:none}
</style></head>
<body><canvas id="stage" aria-hidden="true"></canvas><script>${js}</script></body></html>`;
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, html);
console.log(`built ${out} (${(html.length / 1024).toFixed(0)} KB)`);
