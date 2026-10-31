import test from 'node:test';
import assert from 'node:assert/strict';
import { parseInline, plainText, scanInline } from '../src/markup.js';

test('plain text passes through', () => {
  assert.equal(plainText('hello'), 'hello');
});

test('terms, targets and bold keep their words', () => {
  assert.equal(plainText('The {{treaty|treaty}} of [[1815|e]] is **key**'), 'The treaty of 1815 is key');
});

test('recall targets carry their level, default key facts', () => {
  const segs = parseInline('[[1815|e]] [[Berlin|k]] [[x|i]] [[y]]');
  const levels = segs.filter((s) => s.type === 'recall').map((s) => s.level);
  assert.deepEqual(levels, [1, 2, 3, 2]);
});

test('an unclosed marker is reported and its text kept', () => {
  const { segments, problems } = scanInline('open [[never closed');
  assert.ok(problems.length > 0);
  assert.match(segments.map((s) => s.text || '').join(''), /never closed/);
});
