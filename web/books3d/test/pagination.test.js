import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { buildLibrary, resumeIndex, isRightToLeft } from '../src/data.js';
import { paginate, RecallState } from '../src/pagetex.js';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', 'Palabra', 'Resources', 'Books');
const catalogue = JSON.parse(readFileSync(join(root, 'textbooks.json'), 'utf8'));
const lessons = {};
for (const b of catalogue.books) for (const c of b.chapters) for (const l of c.lessons) lessons[l.file] = JSON.parse(readFileSync(join(root, l.file + '.json'), 'utf8'));
const library = buildLibrary({ catalogue, lessons });

// Text measured as 14px per character: crude, but it exercises wrapping and splitting without a canvas.
const measure = (text) => String(text).length * 14;
const env = (subject, rtl, scale = 1) => ({ measure, subject, rtl, scale });

test('the bundled catalogue loads into numbered pages', () => {
  assert.deepEqual(library.problems, []);
  const history = library.books.find((b) => b.id === 'history');
  assert.ok(history.pages.length >= 1);
  assert.ok(history.rtl);
  history.pages.forEach((p, i) => assert.equal(p.number, i + 1));
  assert.ok(history.pages.every((p) => p.id.includes('/')));
});

test('an empty book stays on the shelf with no pages', () => {
  const geography = library.books.find((b) => b.id === 'geography');
  assert.ok(geography);
  assert.equal(geography.pages.length, 0);
});

test('pagination never drops or reorders a block', () => {
  const history = library.books.find((b) => b.id === 'history');
  for (const scale of [0.88, 1, 1.28]) {
    for (const page of history.pages) {
      const phys = paginate(page, env('history', true, scale));
      const indexes = phys.flatMap((p) => p.blocks.map((b) => b.index));
      assert.deepEqual(indexes, page.page.blocks.map((_, i) => i), `${page.id} at ${scale}`);
      phys.forEach((p) => assert.equal(p.baseId, page.id));
      assert.equal(new Set(phys.map((p) => p.id)).size, phys.length);
    }
  }
});

test('resume falls back to the lesson start, then the first page', () => {
  const history = library.books.find((b) => b.id === 'history');
  const first = history.pages[0];
  assert.equal(resumeIndex(history, null), 0);
  assert.equal(resumeIndex(history, first.id), 0);
  assert.equal(resumeIndex(history, `${first.lessonId}/gone`), history.pages.findIndex((p) => p.lessonId === first.lessonId));
  assert.equal(resumeIndex(history, 'nope/none'), 0);
});

test('reading direction follows the language', () => {
  assert.ok(isRightToLeft('ar'));
  assert.ok(isRightToLeft('ar-DZ'));
  assert.ok(!isRightToLeft('en'));
});

test('Magnifying Glass: levels conceal their own and lower targets', () => {
  const r = new RecallState(1);
  r.setEnabled(true);
  assert.ok(r.isConcealed(1, 'p#a', 'p'));
  assert.ok(!r.isConcealed(2, 'p#b', 'p'));
  r.setLevel(3);
  assert.ok(r.isConcealed(2, 'p#b', 'p'));
  assert.ok(r.isConcealed(3, 'p#c', 'p'));
});

test('Magnifying Glass: a tap wins over the page-wide choice and changing level hides everything again', () => {
  const r = new RecallState(2);
  r.setEnabled(true);
  r.revealPage('p');
  assert.ok(!r.isConcealed(1, 'p#a', 'p'));
  r.toggle('p#a', 'p');
  assert.ok(r.isConcealed(1, 'p#a', 'p'));
  r.setLevel(1);
  assert.ok(r.isConcealed(1, 'p#a', 'p'));
  assert.ok(!r.isPageRevealed('p'));
});

test('Magnifying Glass off conceals nothing', () => {
  const r = new RecallState(3);
  assert.ok(!r.isConcealed(1, 'p#a', 'p'));
});
