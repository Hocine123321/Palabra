# Library organization, tags and the "..." menu (1.1)

## Word Forms stretching bug
Long AI output in "Word Forms" made the whole word screen wider than the display, so every section card looked stretched.
Causes and fixes:
- `FlowLayout.sizeThatFits` returned the width of its longest row even when that exceeded the proposed width, and `Chip` could not wrap. The layout now proposes the available width to its children and never reports more than it was given; chips wrap their text.
- `ForEach(..., id: \.label)` / `id: \.self` on AI strings misbehaved with duplicate labels or forms. Identity is now the offset.
- `ContentValidator` caps the section (12 groups, 12 forms per group, 60 characters per form, 90 per note) and the prompt asks for a compact section.
Words saved before this fix are re-clamped on the next regenerate; the layout fix applies to them immediately.

## Organizing the library
- **Re-organize Library** (main screen "..." menu): AI groups words into sections and gives each 1 to 6 tags. Scope: all words, or only the ones not organized yet.
- **New words** are placed automatically (one small extra request) if "Organize New Words Automatically" is on.
- **Library view**: collapsible sections (grid or list inside each), tag filter strip, `Search words or #tags`.
- **Settings** (Library > Organization, or "..." > Organization Settings): group into sections on/off, tags in list on/off, section order, auto-organize, number of sections (broad/balanced/detailed), tags per word, your own instructions, remove all sections and tags.

## App icon
`AppIcon.appiconset` now has light, dark and tinted 1024 px variants (iOS 18+). Older iOS shows the light icon.
