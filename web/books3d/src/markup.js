// Inline markup of lesson strings. Mirrors Palabra/Features/Books/Domain/InlineMarkup.swift.
//   {{text|term-id}}   highlighted term
//   [[text|e|k|i]]     recall target (default level k)
//   **text**           bold
const RULES = [
  { open: '{{', close: '}}' },
  { open: '[[', close: ']]' },
  { open: '**', close: '**' },
];
export const LEVEL_TAGS = { e: 1, k: 2, i: 3 };

/** @returns {{segments: Array, problems: string[]}} */
export function scanInline(source) {
  const segments = [];
  const problems = [];
  let buffer = '';
  let recallIndex = 0;
  let i = 0;
  const s = String(source ?? '');
  outer: while (i < s.length) {
    for (const rule of RULES) {
      if (!s.startsWith(rule.open, i)) continue;
      const innerStart = i + rule.open.length;
      const close = s.indexOf(rule.close, innerStart);
      if (close < 0) { problems.push('unclosed ' + rule.open); continue; }
      const inner = s.slice(innerStart, close);
      const seg = makeSegment(rule.open, inner, recallIndex, problems);
      if (seg) {
        if (seg.type === 'recall') recallIndex += 1;
        if (buffer) { segments.push({ type: 'text', text: buffer }); buffer = ''; }
        segments.push(seg);
        i = close + rule.close.length;
        continue outer;
      }
    }
    buffer += s[i];
    i += 1;
  }
  if (buffer) segments.push({ type: 'text', text: buffer });
  return { segments, problems };
}

function makeSegment(open, inner, recallIndex, problems) {
  if (open === '{{') {
    const bar = inner.lastIndexOf('|');
    if (bar < 0) { problems.push('term without an id: ' + inner); return null; }
    const text = inner.slice(0, bar);
    const id = inner.slice(bar + 1).trim();
    if (!text || !id) { problems.push('term with an empty text or id: ' + inner); return null; }
    return { type: 'term', text, id };
  }
  if (open === '[[') {
    let text = inner;
    let level = 2;
    const bar = inner.lastIndexOf('|');
    if (bar >= 0) {
      const tag = inner.slice(bar + 1).trim();
      if (tag in LEVEL_TAGS) { level = LEVEL_TAGS[tag]; text = inner.slice(0, bar); }
      else problems.push(`unknown recall level "${tag}" (use e, k or i)`);
    }
    if (!text) return null;
    return { type: 'recall', text, level, index: recallIndex };
  }
  if (open === '**') return inner ? { type: 'bold', text: inner } : null;
  return null;
}

export function parseInline(source) { return scanInline(source).segments; }

export function plainText(source) {
  return parseInline(source).map((s) => s.text).join('');
}
