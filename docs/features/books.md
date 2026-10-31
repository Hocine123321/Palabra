# Books (History and Geography textbooks)

A **Books** tab with two virtual textbooks, History and Geography. The app is only the reader and the memorization
tool: **there is no AI, no lesson generator and no photo upload in the app.** Lessons are written outside the app (by
Claude, from photos of the school lesson) and added to the repository as JSON files. Rebuild, install, and the lesson is
in the book.

Everything works offline: lessons are bundled with the app, reading position and preferences are saved on the device.

## The 3D desk (what the person sees)

The Books tab is a real 3D scene (Three.js / WebGL), not flat artwork: a desk, a lamp, two physical books (History in
oxblood leather, Geography as a teal atlas) with covers, spine, a page block you can see the thickness of, and individually
animated leaves. The scene runs in a `WKWebView` (`BooksSceneView`) from one offline file, `Resources/Books3D/books3d.html`;
SwiftUI draws the 2D layer over it (`SceneHUD`). Lessons are laid out onto the 3D pages as crisp canvas textures at runtime
from the same JSON the app validates.

- **Menu**: both books lie on the desk under a perspective camera with lighting and shadows. Tap a book (or its button, which
  is what VoiceOver and the UI tests use) and the camera flies in while the cover swings open. Geography has no lessons yet,
  and says so.
- **Page turning**: real leaf deformation around the binding (lift, curl, front/back faces, settle). Drag a page edge or
  swipe to turn it; release past halfway (or with speed) to complete. The arrows turn pages too. Right-to-left books
  (Arabic) are the same model mirrored, so the next page turns toward the left.
- **Tools on the desk**: a **magnifying glass** (wood handle, brass rim, glass lens), a **bookmark** (card with a cord) and a
  **ruler**. Picking one flies it from the desk to the page; putting it back flies it home.
  - *Magnifying glass*: the lens shader samples the actual page along the real view ray and magnifies it. With
    **Memorize** on, the lens shows the concealed answers that are under it, and every other target stays hidden.
  - *Ruler*: dims the page outside a band, so one line at a time is lit.
  - *Bookmark*: tap the page to place it; it is saved and put back on the right page next time.
- **Focus Mode**: the desk and tools fade away, the camera frames the page, and only a way out and the Magnifying Glass remain.
- **Memorize** (active recall): recall targets (`[[text|level]]`) are blotted out on the page itself (the answer is not drawn
  at all). Tap a target to reveal it, or use the eye button to reveal the whole page. Levels: *Essential* (dates, figures),
  *Key facts* (also names and terms), *Intensive* (everything the author marked). Reveals are never saved.
- **Highlighted terms**: `{{text|id}}` is underlined; tap it and a definition card opens above the controls.
- **Text size**: smaller / default / larger / largest. The pages are re-laid-out (a long page continues on the next leaf; no
  content is ever dropped).
- **Appearance and motion**: light is daylight, dark is a lamp-lit desk. Reduce Motion turns the flights and page turns into
  jumps.
- **Read as text**: a plain SwiftUI reader (`BookDetailView`, `BookReaderView`) is one tap away (the button at the top of the
  desk) and is what shows if the 3D view can't start (no WebGL, web content process killed).

The app target is iPhone-only and rotates (portrait and both landscapes, `project.yml`). In landscape the camera fills about
half the width with the current page (the neighbouring page stays visible beside it) and a vertical drag (or the mouse wheel)
scrolls down the page, so text stays as large as in portrait.

## Settings (Settings > Books > Books Settings)

- **View**: *3D desk* (default) or *Classic pages* (the original flat shelf, detail page and reader; `BookshelfView`). The
  choice is saved in `TextbookState.preferences.viewStyle`.
- **3D desk quality**: *Standard* or *Battery saver* (lower pixel density, no shadows). Sent to the scene as `setQuality`.
- **Reading**: text size and Memorize level (the same values the reader's own controls change).
- **Reading progress**: reset a book's read pages and bookmark. Lessons are never touched.

## The bridge (Swift <-> scene)

`Features/Books/Scene/BooksBridge.swift` defines both directions as plain data:

- scene -> Swift (`SceneMessage`): `ready`, `state`, `visit`, `term`, `termClose`, `bookmark`, `preference`, `empty`, `error`.
  `BooksSceneModel` saves `visit` / `bookmark` / `preference` into `BookShelf` (`TextbookState`).
- Swift -> scene (`SceneCommand`): `openBook`, `closeBook`, `next`, `prev`, `goto`, `setRecall`, `setLevel`,
  `togglePageReveal`, `setTool`, `setFocus`, `setTextSize`, `setInsets`, `setAppearance`, `closeTerm`. The names are matched in
  `web/books3d/src/app.js`; a unit test checks that the scene still knows each one.
- `BooksScenePayload` hands the scene the raw catalogue, the lesson files, the saved progress, bookmarks and preferences.

Nothing here talks to the network. The hard rule still stands: **no AI, no OCR, no upload, no chat, no lesson generator.**

## Building the scene

The scene's sources are in `web/books3d/` (Three.js, plain JS, esbuild). The result is committed as
`Palabra/Resources/Books3D/books3d.html`, because the iOS build has no Node step. After changing anything in `web/books3d`:

```
cd web/books3d
npm ci          # once
npm test        # page layout never drops a block, recall rules, resume rules, bundled lessons load
npm run build   # rewrites Palabra/Resources/Books3D/books3d.html (single file, fonts inlined)
```

CI (`scene` job) runs the tests, rebuilds, and fails when the committed bundle differs from what the sources produce.
`web/books3d/dev/` has a standalone harness for looking at a rendered page without the app. `npm run preview` writes
`web/books3d/dist/palabra-desk.html`: the scene plus the bundled lessons and a browser version of the controls, one file you can open
in any browser (then run `npm run build` again so the app bundle is the one committed).

## Where things live

```
Palabra/Resources/Books/
  textbooks.json                 the catalogue: books -> chapters -> lessons (registration)
  lesson-<book>-<name>.json      one file per lesson
Palabra/Features/Books/
  Domain/    InlineMarkup, LessonModels (Lesson, Block...), LessonValidator, BookModels, BookLibrary (loader), RecallState
  Storage/   TextbookState (+ store), BookShelf (observable, on AppEnvironment as `books`)
  Scene/     BooksBridge (messages, commands, payload), BooksSceneModel, BooksSceneView (WKWebView)
  Views/     BooksRootView, BooksSceneScreen, SceneHUD (the 2D layer), then the text reader: BookshelfView, BookDetailView,
             BookReaderView, ReaderChrome, BookPageView, BlockViews, RichText
Palabra/Resources/Books3D/books3d.html   the built 3D scene (do not edit by hand)
web/books3d/                             the scene's sources, tests and build
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
