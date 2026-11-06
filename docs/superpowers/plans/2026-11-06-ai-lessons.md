# AI Lessons (Lesson Studio) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add lessons to the Books from photos or text with AI that only polishes presentation, revise them by asking, edit them live on the 2D pages, and have the 3D desk always read the same data.

**Architecture:** A file-backed `LessonStore` is the single source (a `BookContentSource`), seeded once from the bundle; `BookLibrary`, `LessonValidator` and the 3D desk stay as they are. A two-step AI pipeline (transcribe, then format) is gated by `LessonValidator` and a pure `LessonFaithfulness` check. Editing is pure value operations (`LessonEditor`) saved through `BookShelf`.

**Tech Stack:** Swift, SwiftUI, XCTest, existing `AIClient.generateJSON` (one image per call). CI is the compiler.

**Spec:** `docs/superpowers/specs/2026-11-06-ai-lessons-design.md`

## Global Constraints

- No `AIClient` protocol change (no new `MockAIClient` stubs). One photo per `generateJSON(image:)` call; photos via `PhotoPreparer.prepare(_, maxPixelSize:)`.
- Lesson id and page ids never empty and never contain "/". Page ids survive edits and revisions (reading progress is keyed by them).
- AI never adds facts: no new numbers/dates; doubts go to `transcriptionNotes`. App assigns ids, not the AI.
- Every new UI string has an Arabic key (`LocalizationTests`). `AGENTS.md` and `docs/features/books.md` stop saying "no AI in Books".
- Commit to `main` after each task with the two attribution lines from the session reminder.

## Review Focus

- Arabic-Indic digits in the source vs Western digits in the output (and the reverse) must not trigger false "new number" failures (Task 3).
- A lesson saved with a duplicate page id from the AI, or an id containing "/" (Task 4: ids are re-assigned).
- Store write interrupted / corrupt file: the library still loads the other lessons and reports a problem (Task 2).
- Revising must keep existing page ids by position, or saved reading progress is lost (Task 4).
- Editing the last block/page of a lesson must not produce an invalid lesson (Task 6).

## File Structure

- Modify `Features/Books/Domain/LessonModels.swift`: `Encodable` conformances.
- Create `Features/Books/Storage/LessonStore.swift`, `Features/Books/Storage/StoreBookSource.swift` (if the store is not itself the source), modify `Features/Books/Storage/BookShelf.swift`.
- Create `Features/Books/AI/LessonFaithfulness.swift`, `LessonPrompts.swift`, `LessonAuthor.swift`, `LessonIDs.swift`.
- Create `Features/Books/Studio/LessonStudioSession.swift`, `LessonStudioView.swift`.
- Create `Features/Books/Editing/LessonEditor.swift`, `BlockEditorView.swift`; modify `BookReaderView.swift`, `BookDetailView.swift`, `BooksRootView.swift`.
- Tests under `PalabraTests/Books/`.

---

### Task 1: Encodable lesson models

**Files:** modify `LessonModels.swift`; test `PalabraTests/Books/LessonCodingTests.swift`.
**Interfaces:** Produces `Lesson: Codable`, `LessonPage: Codable`, `Block: Codable`, and `Codable` for `TermDefinition`, `TimelineEvent`, `StatItem`, `ComparisonRow`, `FlowStage`, `ProcessStep`, `DefinitionItem`, `ImagePanel`; `LessonCoding.encode(_ lesson: Lesson) throws -> Data` (pretty, sorted keys).

- [ ] **Step 1: Write failing tests.** `testEveryBlockTypeRoundTrips` builds a lesson with one block of each of the 12 types (use the bundled `lesson-history-colonial-movement.json` too) and asserts `decode(encode(lesson)) == lesson`. `testEncodedBlockKeysMatchTheDocumentedFormat` asserts a timeline encodes `"type":"timeline"` with `events`, a stats block with `stats`, a definitions block with `definitions`, an image block with key `image` (not `name`). `testUnsupportedBlockEncodesItsType`.
- [ ] **Step 2: Run** `-only-testing:PalabraTests/LessonCodingTests`. Expected: FAIL (does not compile).
- [ ] **Step 3: Implement** `encode(to:)` for `Block` writing the same keys `init(from:)` reads (`Keys` enum already lists them), omit nil optionals and default `level`/`ordered` only when equal to defaults; `Lesson.encode` writes `terms` and `transcriptionNotes` only when non-empty. Add `LessonCoding.encode`.
- [ ] **Step 4: Run** the tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat(books): lessons can be encoded`.

### Task 2: LessonStore and shelf wiring

**Files:** create `LessonStore.swift`; modify `BookShelf.swift`, `AppEnvironment.swift` (where `BookShelf` is created); test `PalabraTests/Books/LessonStoreTests.swift`.
**Interfaces:** Consumes `LessonCoding.encode`, `BookContentSource`, `BookCatalogue`. Produces `final class LessonStore: BookContentSource` with `init(directory: URL, seed: BookContentSource?)`, `func save(_ lesson: Lesson, bookID: String, chapterID: String) throws`, `func delete(lessonID: String) throws`, `func addChapter(bookID: String, title: String) throws -> String`, `func renameChapter(bookID: String, chapterID: String, title: String) throws`, `func lesson(id: String) -> Lesson?`; `BookShelf.libraryVersion: Int`, `BookShelf.store: LessonStore`, `BookShelf.saveLesson(_:bookID:chapterID:) throws`, `deleteLesson(id:)`, `addChapter(...)`.

- [ ] **Step 1: Write failing tests** (temp directory per test): `testSeedCopiesBundledCatalogueAndLessonsOnce` (seed from `BundleBookSource()`; second init does not re-add a deleted lesson); `testSaveNewLessonAppearsInLibrary` (`BookLibrary.load(from: store)` has it under the chosen chapter, pages numbered after existing); `testSaveExistingLessonReplacesFileAndKeepsCatalogueOrder`; `testDeleteRemovesFileAndCatalogueEntry`; `testAddChapterReturnsUniqueID`; `testCorruptLessonFileIsReportedAndOthersStillLoad` (write garbage to one file; `library.problems` non-empty, other lesson present); `testWritesAreAtomic` (no `.tmp` file left); `testShelfSaveBumpsLibraryVersionAndReloads`.
- [ ] **Step 2: Run** `-only-testing:PalabraTests/LessonStoreTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** Catalogue stored as `catalogue.json` in the existing `BookCatalogue` shape (make `BookCatalogue`/`BookEntry`/`ChapterEntry`/`LessonRef` `Codable`); lesson files `lessons/<id>.json`, `LessonRef.file` = `lessons/<id>` handled by the store's `lessonData(file:)`; `seeded.json` lists seeded lesson ids; write with `Data.write(to:options:.atomic)`. `BookShelf.init` takes the store as `source` (default: a store in Application Support seeded from `BundleBookSource()`); `inMemory()` uses a temp-dir store.
- [ ] **Step 4: Run** the tests plus `BookLibraryTests`/`BundledBooksTests`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(books): writable lesson store, seeded from the bundle`.

### Task 3: Faithfulness check

**Files:** create `AI/LessonFaithfulness.swift`; test `PalabraTests/Books/LessonFaithfulnessTests.swift`.
**Interfaces:** Produces `enum LessonFaithfulness { struct Report: Equatable { var blockedNumbers: [String]; var newWords: [String]; var isClean: Bool { blockedNumbers.isEmpty } }; static func check(_ lesson: Lesson, source: String) -> Report }`.

- [ ] **Step 1: Write failing tests:** `testNumbersFromSourceAreAllowed`; `testNewNumberIsBlocked` (lesson says 1954, source says 1945 → `["1954"]`); `testArabicIndicDigitsInSourceMatchWesternInOutput` (`١٩٥٤` vs `1954`) and the reverse; `testTranscriptionNotesAreNotChecked`; `testNewWordsAreWarningsOnly` (isClean stays true); `testDiacriticsAndLeadingArticleDoNotCreateNewWords` (`الاستعمار` vs `استعمار`); `testTermIDsAndBlockTypesAreIgnored`; `testListNumberingIsNotChecked` (ordered list markers are not text).
- [ ] **Step 2: Run** `-only-testing:PalabraTests/LessonFaithfulnessTests`. Expected: FAIL.
- [ ] **Step 3: Implement** using `Block.texts` plus page titles/dateLabels/lesson title/summary; strip inline markup with `InlineMarkup.plainText`; normalize digits (U+0660–0669, U+06F0–06F9 → 0–9); tokens = maximal digit runs; words = letter runs of ≥ 3 characters, lowercased, Arabic diacritics (U+064B–065F, U+0670) removed, leading "ال"/"و"/"ب"/"ل" tolerated by also testing the stripped form against the source vocabulary.
- [ ] **Step 4: Run** the tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat(books): faithfulness check for AI-formatted lessons`.

### Task 4: Lesson author (AI pipeline)

**Files:** create `AI/LessonPrompts.swift`, `AI/LessonIDs.swift`, `AI/LessonAuthor.swift`; test `PalabraTests/Books/LessonAuthorTests.swift`.
**Interfaces:** Consumes Tasks 1 and 3, `AIClient.generateJSON` (text and image variants), `CodeFence.extractJSON`, `LessonValidator`. Produces `struct LessonAuthor { let ai: AIClient; func transcribe(photo: AIImage, apiKey: String, model: AIModel, language: String) async -> Result<Transcription, LessonAuthorError>; func format(rawText: String, bookTitle: String, language: String, instruction: String?, apiKey: String, model: AIModel) async -> Result<LessonDraft, LessonAuthorError>; func revise(current: Lesson, rawText: String, instruction: String, apiKey: String, model: AIModel) async -> Result<LessonDraft, LessonAuthorError> }`; `struct Transcription { text: String; uncertain: [String] }`; `struct LessonDraft { lesson: Lesson; report: LessonFaithfulness.Report; problems: [String] }`; `enum LessonIDs { static func assign(_ lesson: Lesson, previous: Lesson?, takenLessonIDs: Set<String>) -> Lesson }`.

- [ ] **Step 1: Write failing tests** (`MockAIClient`, assert the real request): `testTranscribeSendsTheImageBytesAndAFaithfulTranscriptionPrompt` (image data and mime equal what was passed; system text contains "do not correct", "mark" doubtful text); `testFormatPromptContainsRawTextAndBlockCatalogueAndNoAddRule` (prompt contains the raw text verbatim; system text contains every block type name and "only the source"); `testFormatDecodesAndValidates`; `testNewNumberTriggersOneRetryWithTheOffendingNumber` (first reply has 1954 not in source; second request's prompt contains "1954"; second reply clean → success, 2 calls); `testStillFailingAfterRetryReturnsDraftWithBlockedNumbers`; `testInvalidLessonRetriesOnceWithValidatorProblems`; `testIDsAreAssignedByTheApp` (AI ids with "/" and duplicates are replaced; lesson id is a unique slug); `testReviseKeepsPageIDsByPosition` (3 pages in, 3 out → same ids; 4 out → 3 old + a new id); `testMalformedJSONIsAnError`; `testBackendFailurePropagates`.
- [ ] **Step 2: Run** `-only-testing:PalabraTests/LessonAuthorTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** `LessonPrompts` builds the system texts from the block catalogue and the "Rules for the author" in `docs/features/books.md` plus: use only the source text, do not explain/summarize/translate/complete, keep the source language, put doubts in `transcriptionNotes`, never output ids (the app assigns them), never output `image` blocks. `schema: nil`, temperature 0.2. Reply parsing: `CodeFence.extractJSON`, decode `Lesson` (with placeholder ids if missing: make `id` optional in the AI wire struct `AILessonWire` and map into `Lesson`), `LessonIDs.assign`, `LessonValidator.problems`, `LessonFaithfulness.check(_, source: rawText)`. One retry when `problems` non-empty or `blockedNumbers` non-empty, appending the concrete list.
- [ ] **Step 4: Run** the tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat(books): AI lesson author (transcribe, format, revise)`.

### Task 5: Lesson Studio

**Files:** create `Studio/LessonStudioSession.swift`, `Studio/LessonStudioView.swift`; modify `BookDetailView.swift` (toolbar "Add lesson"), `ar.lproj/Localizable.strings`, `LocalizationTests.swift`; test `PalabraTests/Books/LessonStudioSessionTests.swift`.
**Interfaces:** Consumes Tasks 2 and 4. Produces `@MainActor @Observable final class LessonStudioSession { init(environment: AppEnvironment, bookID: String); var chapterChoice: ChapterChoice; var rawText: String; private(set) var attachments: [PhotoAttachment]; private(set) var phase: Phase; private(set) var draft: LessonDraft?; func attachPhoto(_ data: Data) async; func removeAttachment(at: Int); func transcribe() async; func formatDraft(instruction: String?) async; func revise(_ instruction: String) async; func save() throws -> String /* lesson id */ }`.

- [ ] **Step 1: Write failing tests** with a scripted `MockAIClient`: photos are transcribed in order and appended to `rawText`; `formatDraft` needs non-empty `rawText`; `revise` replaces the draft only on success and keeps the old draft on failure; `save` writes the lesson into the chosen/new chapter and `environment.books.libraryVersion` increases; no API key → `phase == .failed(.missingKey)` with no AI call; typed text skips transcription (zero image calls).
- [ ] **Step 2: Run** `-only-testing:PalabraTests/LessonStudioSessionTests`. Expected: FAIL.
- [ ] **Step 3: Implement** the session and the chat-styled view (message bubbles reusing the chat's design components; photo/camera picker the way `ChatView` does; "What I read" bubble with an editable text field; draft previews with `BookPageView`; warnings list for `blockedNumbers`/`newWords`/`problems`/`transcriptionNotes`; Save to book). Arabic keys for every new string.
- [ ] **Step 4: Run** the session tests and `LocalizationTests`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(books): Lesson Studio`.

### Task 6: Live editing on the 2D pages

**Files:** create `Editing/LessonEditor.swift`, `Editing/BlockEditorView.swift`; modify `BookReaderView.swift`, `BookDetailView.swift`; test `PalabraTests/Books/LessonEditorTests.swift`.
**Interfaces:** Produces `enum LessonEditor { static func replaceBlock(_ lesson: Lesson, pageID: String, index: Int, with: Block) -> Lesson; insertBlock(…, at:); deleteBlock(…); moveBlock(…, from:, to:); addPage(_, after pageID: String?, title: String) -> Lesson; deletePage; movePage; setPageTitle; setDateLabel; renameLesson }` — every result passes `LessonValidator` (deleting the last block of a page inserts nothing but is refused by returning the input unchanged; deleting the last page is refused). `BookShelf.lesson(id:) -> Lesson?`.

- [ ] **Step 1: Write failing tests:** each operation, page ids unchanged by block edits, `deleteBlock` on a one-block page returns the lesson unchanged, `deletePage` on a one-page lesson unchanged, `addPage` gets a fresh unique id without "/", move operations keep the other blocks' order, results validate.
- [ ] **Step 2: Run** `-only-testing:PalabraTests/LessonEditorTests`. Expected: FAIL.
- [ ] **Step 3: Implement** `LessonEditor` and the UI: Edit toggle in `BookReaderView` (toolbar); in edit mode each block shows an edit/move/delete menu; `BlockEditorView` is a form per block type (text fields, add/remove rows for lists, events, stats, rows, stages, steps, definitions); page header editable; changes go through `environment.books.saveLesson`, then the reader reselects the same page id.
- [ ] **Step 4: Run** the tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat(books): edit lessons live in the 2D reader`.

### Task 7: Desk refresh, delete lesson, docs

**Files:** modify `BooksRootView.swift`, `BookDetailView.swift`, `AGENTS.md`, `docs/features/books.md`, `docs/REVIEW.md`; test `PalabraTests/Books/BookShelfVersionTests.swift`.

- [ ] **Step 1: Write failing tests:** `testLibraryVersionIncreasesOnSaveDeleteAndChapterChange`; `testDeletingTheLessonTheReaderIsOnLeavesTheShelfConsistent` (`lastPageID` of a removed lesson resumes at the book start via `Book.resumeIndex`).
- [ ] **Step 2: Run** `-only-testing:PalabraTests/BookShelfVersionTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** `BooksRootView` keeps `@State sceneVersion` set from `libraryVersion` in `.onAppear` of the desk screen and uses it in the `.id` of `BooksSceneScreen` so the desk rebuilds when it reappears after changes. Swipe/menu "Delete lesson" with confirmation in `BookDetailView`. Docs: replace "no AI, no generator, no upload" with the Lesson Studio description, the store layout, the faithfulness rules, and the editing workflow; keep "Rules for the author" as the AI's rules; note backup follow-up in `docs/REVIEW.md` if `Core/Backup` does not include the store.
- [ ] **Step 4: Run** the tests, then full `PalabraTests` on CI. Expected: PASS. State plainly: compiled by eye, needs a CI run.
- [ ] **Step 5: Commit** `feat(books): desk refresh, delete lesson, docs`.

---

## Self-review

- Spec coverage: store + seed (2), faithfulness (3), transcribe/format/revise with retry and ids (4), Studio with editable transcription and change-by-asking (5), live 2D editing (6), desk refresh, delete, docs (7). Backup is conditional per the spec.
- Types consistent across tasks: `LessonDraft`, `Transcription`, `LessonFaithfulness.Report`, `BookShelf.libraryVersion`, `LessonEditor` signatures.
- Wire detail added beyond the spec: `AILessonWire` (ids optional) so the AI is never trusted for ids.
