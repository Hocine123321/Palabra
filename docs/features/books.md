# Books (History and Geography textbooks)

A **Books** tab with two virtual textbooks, History and Geography. The app is only the reader and the memorization
tool: **there is no AI, no lesson generator and no photo upload in the app.** Lessons are written outside the app (by
Claude, from photos of the school lesson) and added to the repository as JSON files. Rebuild, install, and the lesson is
in the book.

Everything works offline: lessons are bundled with the app, reading position and preferences are saved on the device.

## What the reader does

- **Bookshelf** (`BooksRootView`): one cover per book (its own paper, ornament and type), with reading progress.
- **Book page** (`BookDetailView`): Continue / Start reading, chapters, lessons with pages-read counts, and the lesson's
  *transcription notes* (what the author could not read or had to decide).
- **Reader** (`BookReaderView`): numbered pages you swipe through (previous / next buttons, "3 / 7" indicator, contents
  sheet to jump to any page). The book's language sets the reading direction (an Arabic book is right-to-left, so the
  next page is a swipe to the left). Reduced Motion is respected (all animation goes through `Motion`).
- **Focus Mode**: hides the navigation bar, tab bar, status bar and home indicator and gives text one step more size. The
  page controls and the exit button stay.
- **Highlighted terms**: `{{text|id}}` in lesson text is underlined; tapping opens a compact definition card above the
  controls (also reachable from VoiceOver's Links rotor). Not hover-dependent.
- **Magnifying Glass** (active recall): the toolbar magnifier turns it on. Recall targets (`[[text|level]]`) are replaced
  by a same-sized placeholder; tap to reveal, tap again to hide, **Reveal all / Hide all** for the page. Levels:
  *Essential* (dates, figures), *Key facts* (also names and terms), *Intensive* (everything the author marked). A hidden
  answer is not in the text at all (nothing to copy or read aloud), and turning the mode off shows the original text.
  Reveals are never saved; turning the mode on or changing the level starts hidden again.
- **Text size**: smaller / default / larger / largest, relative to the system size.

The app target is iPhone-only and portrait-only (`project.yml`), so there is no two-page spread and no hover reveal. The
reader does have left / right arrow-key shortcuts for the page buttons (direction follows the book).

## Where things live

```
Palabra/Resources/Books/
  textbooks.json                 the catalogue: books -> chapters -> lessons (registration)
  lesson-<book>-<name>.json      one file per lesson
Palabra/Features/Books/
  Domain/    InlineMarkup, LessonModels (Lesson, Block...), LessonValidator, BookModels, BookLibrary (loader), RecallState
  Storage/   TextbookState (+ store), BookShelf (observable, on AppEnvironment as `books`)
  Views/     BooksRootView (shelf, cover), BookDetailView, BookReaderView, ReaderChrome, BookPageView, BlockViews, RichText
scripts/validate-lessons.py      the same validation rules, run by CI before the build
```

Lesson content (JSON) is separate from the reusable views and from the saved reading state, so adding a lesson never
touches the reader or the user's progress.

**File names must be unique across the whole app.** Xcode copies resources into the bundle root, so two files called
`lesson.json` would collide. Always name lessons `lesson-<book>-<name>.json`.

## Adding a lesson (the workflow)

1. Write `Palabra/Resources/Books/lesson-<book>-<name>.json` (format below).
2. Register it in `textbooks.json` under the right book and chapter (`{ "id": "<lesson-id>", "file": "lesson-<book>-<name>" }`;
   add the chapter first if it is new). The `id` in the file must equal the `id` in the catalogue.
3. Run `python3 scripts/validate-lessons.py`. It must print `Lessons OK`.
4. Commit and push; CI builds the IPA.

Nothing else changes. No Swift edits, no project file edits (XcodeGen picks the file up).

### Rules for the author

- Copy dates, names, numbers, definitions and terminology exactly. Do not invent facts, statistics, borders or events to
  fill a page. Everything in a diagram must come from the lesson.
- Anything illegible, ambiguous, crossed out or decided by the author goes in `transcriptionNotes`, in plain words. Do not guess silently.
- Choose the block that fits the content: chronology -> `timeline`; measurements -> `stats`; differences -> `comparison`;
  reasons and consequences -> `causeEffect`; stages -> `process`; vocabulary -> `definitions`.
- Pick recall targets deliberately: dates and figures `e`; names and key terms `k`; anything else worth testing `i`.
  Do not repeat a hidden answer elsewhere on the same page (it would give the answer away).
- Highlight (`{{ }}`) only terms that benefit from a definition, and only where the definition exists in the lesson.
- Page ids are stable. **Never rename a page id or a lesson id** once the lesson has shipped: reading progress is saved under
  `<lesson id>/<page id>`. A page that is removed makes the reader resume at the start of its lesson; new pages and lessons never lose progress.
- Bump `version` when rewriting a lesson (informational).

## Catalogue (`textbooks.json`)

```json
{
  "version": 1,
  "books": [
    { "id": "history", "subject": "history", "title": "التاريخ", "language": "ar",
      "chapters": [
        { "id": "unit-1", "title": "…", "lessons": [ { "id": "colonial-movement", "file": "lesson-history-colonial-movement" } ] }
      ] }
  ]
}
```

`subject` is `history` or `geography` (it picks the look). `language` is a language code; right-to-left languages make
the whole book right-to-left. A book with no lessons shows an empty state.

## Lesson file

```json
{
  "id": "colonial-movement",          // = the catalogue id, no "/"
  "version": 1,
  "title": "…",
  "summary": "…",                      // optional
  "terms": { "id": { "term": "…", "definition": "…" } },   // optional glossary for {{text|id}}
  "pages": [ { "id": "intro", "title": "…", "dateLabel": "…", "blocks": [ … ] } ],
  "transcriptionNotes": [ "…" ]        // optional
}
```

Page: `id` (unique in the lesson, no "/"), `title`, optional `dateLabel`, and `blocks`.

### Inline markup (in every text field)

| Markup | Meaning |
|---|---|
| `{{text\|term-id}}` | highlighted term; `term-id` is in `terms` or on a `definitions` item with that `id` |
| `[[text\|e]]` `[[text\|k]]` `[[text\|i]]` | recall target: Essential / Key facts / Intensive (no tag = `k`) |
| `**text**` | bold |

### Blocks (`"type": …`)

| type | fields |
|---|---|
| `heading` | `text`, `level` (1-3, default 2) |
| `paragraph` | `text` |
| `list` | `items` [strings], `ordered` (default false), `title`? |
| `keyPoint` | `text`, `label`? |
| `quote` | `text`, `source`? |
| `timeline` | `events` [{ `date`, `title`, `detail`? }], `title`? |
| `stats` | `stats` [{ `label`, `value`, `unit`?, `note`? }], `title`? |
| `comparison` | `columns` [headers], `corner`? (header of the label column), `rows` [{ `label`, `cells` [one per column] }], `title`? A `\n` in a cell becomes bullet points. One column = a card per row; two or more = a table. |
| `causeEffect` | `stages` [{ `label`?, `nodes` [strings] }] (at least two; drawn top to bottom with arrows, the last stage is highlighted), `title`? |
| `process` | `steps` [{ `title`, `detail`? }], `title`? |
| `definitions` | `definitions` [{ `id`?, `term`, `definition` }], `title`? An `id` also makes the term available to `{{ }}`. |
| `image` | `image` (asset name), `alt` (required), `caption`?, `style`? (`map` or `illustration`) |

An unknown `type` shows a "needs a newer version" notice instead of breaking the lesson (and fails validation, so authors notice).

### Images and maps

Add the picture to the asset catalog as `Palabra/Assets.xcassets/Books/<name>.imageset` (an image set with a `Contents.json`)
and refer to it by `<name>` in an `image` block. Use a name that cannot clash with another asset. A missing image shows a
labelled placeholder rather than failing. Only use maps and pictures that are in the lesson or are supplied for it.

## Saved state

One UserDefaults key, `textbookState` (JSON, tolerant decoding): per book the last page id and the set of visited page ids,
plus the reader preferences (recall level, text size). Lessons are never stored there. Progress counts only pages that still exist.

## Tests

`PalabraTests/Books/`: markup parsing, block decoding, validation, library loading (missing / broken lessons), resuming
and progress across lesson updates, recall state, saved-state decoding, and `BundledBooksTests` (the shipped lessons load
with no problems). `PalabraUITests/BooksUITests` covers the shelf, page turning, Focus Mode, Magnifying Glass and contents.
