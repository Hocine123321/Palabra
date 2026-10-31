// Builds a standalone page you can open in any browser: the scene plus the bundled lessons, with its own controls
// (the app draws those in SwiftUI instead). Output: web/books3d/dist/palabra-desk.html
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const books = join(root, '..', '..', 'Palabra', 'Resources', 'Books');
const dist = join(root, 'dist');
mkdirSync(dist, { recursive: true });
const built = join(dist, 'books3d.html');
execFileSync('node', [join(root, 'build.mjs'), '--out', built], { stdio: 'inherit' });

const catalogue = JSON.parse(readFileSync(join(books, 'textbooks.json'), 'utf8'));
const lessons = {};
for (const b of catalogue.books) for (const c of b.chapters) for (const l of c.lessons) lessons[l.file] = JSON.parse(readFileSync(join(books, l.file + '.json'), 'utf8'));
const payload = JSON.stringify({ catalogue, lessons }).replace(/</g, '\\u003c');

const html = readFileSync(built, 'utf8').replace('</body>', `<script>
(function () {
  var payload = ${payload};
  var dark = !!(window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches);
  var reduced = !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
  window.palabra.load(payload, { reducedMotion: reduced }).then(function () { window.palabra.command({ name: 'setAppearance', dark: dark }); });
})();
</script></body>`).replace('<title>Palabra Books</title>', '<title>Palabra Desk</title>');
writeFileSync(join(dist, 'palabra-desk.html'), html);
console.log('wrote', join(dist, 'palabra-desk.html'));
