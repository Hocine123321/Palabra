# Artifacts

The Spanish tab's **Artifacts** page. The person asks the AI for a table, chart, roadmap or checklist; it is previewed (live), saved as a versioned artifact, reopened later, updated, and rolled back. Tables and charts can bind live to library data.

Plans B1 (spec artifacts), B2 (`app` artifacts in a sandboxed web view) and C (Need Review) are shipped. Design: `docs/archive/superpowers/specs/2026-10-06-artifacts-design.md`.

## Architecture

```
Features/Artifacts/
  Domain/    ArtifactKind, GrantPolicy, AIUsageLimiter   (JSONValue, Capability, CapabilityRegistry, CodeFence live in Core/Capabilities)
  Storage/   Artifact, ArtifactVersion, ArtifactStateEntry (SwiftData), ArtifactRepository
  Spec/      SpecBlock (model), SpecValidator (sanitizer), SpecBindLoader, SpecStateStore, SpecRenderer + views
  AI/        ArtifactEnvelope (parser), ArtifactPrompts, ArtifactGenerator
  Library/   ArtifactsListView, ArtifactDraftModel/View, ArtifactDetailView, ArtifactApprovalCard
  App/       BridgeDispatcher, PalabraBridge, ArtifactSandbox, AppRendererView, ArtifactErrorLog, ArtifactTheme
App/CapabilityProviders.swift   the only file that sees both Word and artifacts
```

- **The registry is the only door** between an artifact and the app. `CapabilityRegistry.call` checks, in order: unknown → not granted (`.local` is exempt) → args > 64 KB → dry-run write → handler.
- **The AI's manual is generated from the registry** (`registry.manual(including:)`). A new capability is learnable with no prompt edits.
- **Dry run:** the draft preview runs with `ArtifactSession(artifactID: nil, dryRun: true)`. Writes return their `dryRunValue`; storage is in-memory scratch. Reads are real, so a preview shows live library data.
- **Grants:** spec artifacts only bind `.read` capabilities, which are auto-granted. App artifacts need approval for read/write/ai (see "App artifacts"); `.local` is always granted.

## Wire format (AI → app)

One schema-less `generateJSON` call (`schema: nil`, temperature 0.4):

```
{"kind":"spec","title":"…","requests":["library.words"]}
---PAYLOAD---
{"blocks":[ … ]}
---END---
```

- Missing `---PAYLOAD---` → malformed; missing `---END---` → truncated.
- The Gemini client reports a hit output cap as `AIError.truncated` and drops the partial text; the generator treats it the same as a missing `---END---`.
- One automatic retry per generation (truncated, invalid spec, malformed envelope), with the concrete problem appended to the same prompt. A truncated *update* after the retry becomes "too large to extend".
- `update` sends the whole current payload (`CURRENT PAYLOAD:`) plus the change and expects the complete new payload back. The title is kept.
- Block shapes: `SpecBlock.catalog` (what the AI sees). Keep it in sync with the cases in `SpecBlock`.

## App artifacts (plan B2)

An `app` artifact is one self-contained HTML document (no external `src`/`href`, no `localStorage`; lint in `ArtifactHTMLLint`, ≤ the size set in Settings → Artifacts for Gemini, up to 2 MB for a page from another AI) run in a sandboxed `WKWebView`. Kind cannot change on update.

- **Sandbox:** non-persistent data store; CSP meta injected after the doctype; two content-blocking rules (`^https?://`, `^wss?://`; WebKit rules have no groups/alternation); `NavigationGate` allows exactly one navigation; no new windows.
- **Shim** (document start) defines `window.palabra`: `call(name, args)`, `granted`, `theme`, `locale`, `dir`, and forwards `error`/`unhandledrejection` to the error log.
- **Bridge:** `PalabraBridge` → pure `BridgeDispatcher.handle` → `CapabilityRegistry.call`. Message ≤ 256 KB; timeout 30 s (120 s for `ai.generate`). Reply error codes: `unknown`, `notGranted`, `badArgs`, `failed`, `rateLimited`, `badMessage`, `timeout`.
- **`ai.generate`** `{prompt ≤ 8000, schema?, temperature? 0–2 (default 0.7)}` → `{text}`; 10 calls per rolling minute and 100 per session (`AIUsageLimiter`; invalid args cost nothing). Goes through `AIGateway` → `AIClient.generateJSON`.
- **Approval:** `ArtifactApprovalCard` lists the requested capabilities with their class; Allow stores them in `Artifact.grantedNames` (`ArtifactRepository.setGranted`); "Not now" keeps the app unrun. Effective grant = requested ∩ granted + `.local`. An update prompts only for newly requested capabilities. A denied call returns `notGranted`.
- **Fix with AI:** the detail screen lists recent script errors (newest 20, 300 chars each) and opens the update sheet pre-filled with them.
- **Not covered by CI:** JavaScript running inside the web view. The Swift side (lint, dispatcher, limiter, sandbox config, approval flow with the stub app) is.

## The create page

`ArtifactDraftView` is one sheet with four phases (request, generating, preview, failed).

- **Request (create):** a header, the editor (placeholder, counter near the cap), a **Format** picker (Auto / Page / Interactive app) and an **Ideas** grid (`ArtifactIdea.all`: tapping one fills the editor and sets the format; it never generates by itself). Generate is pinned above the keyboard.
- **Request (update):** the same editor plus **Quick changes** chips (`ArtifactQuickChange`); no format (kind cannot change).
- **Format** is sent as a `FORMAT:` line in front of the request (`ArtifactFormat.requestPrefix`; none for Auto). `ArtifactDraftModel.maxInput` (cap − 150) leaves room for it. The saved version's `prompt` is what the person typed, not the prefix.
- **Preview:** title with a Page / Interactive app badge, the live dry-run preview, quick-change chips (they fill the refine field), Refine, Discard, Save.
- New ideas or chips need Arabic keys (`LocalizationTests` covers `ArtifactIdea.all` and `ArtifactQuickChange.all`).

## Using Claude or ChatGPT

The **…** menu (top right of New Artifact / Update) hands the request to another AI and takes its page back, for apps that need a stronger builder than Gemini. No API key is needed. The menu shows only before generating, and on update only for an HTML page (`ArtifactDraftModel.canUseExternalAI`): a table or chart is JSON blocks, which another AI answering in HTML cannot replace.

- **Copy artifact prompt rules** (`ArtifactDraftModel.exportPrompt()`): asks for ONE complete HTML document and nothing else (no envelope, no code fence). It carries the sandbox rules (`ArtifactPrompts.sandboxRules`, the same text the in-app prompt uses, so the two cannot drift), the live capability manual, the request, and on update the whole `CURRENT PAGE:`. It tells the AI the page may be at most 2 MB. The Gemini format picker does not apply to it.
- **Upload/paste artifact** (`ArtifactImportSheet` → `ArtifactDraftModel.importExternal`): paste, or choose an `.html`/text file. `ArtifactImport.normalize` takes the HTML document out of the chat text and fence around it (title from `<title>`, requests from the `palabra.call("…")` names it uses) and wraps it as an app; an old-style envelope still works. It then runs the same parse, lint, capability filter and approval as a Gemini answer (`ArtifactGenerator.importDraft`, no AI call). Pages from another AI are always apps.
- **Size:** an external page may be up to 2 MB (`ArtifactOutputBudget.externalMaxKB`; storage accepts the same, `ArtifactLimits.maxPayloadBytes`). The Settings → Artifacts size is what Gemini writes in the app and does not apply to imports. Pasted text over 2 MB + 64 KB is refused. Refining a large imported app with Gemini fails as "too large to extend" (Gemini cannot return 500 KB within its cap); export the update instead.
- On update the artifact's kind must stay the same; a pasted spec cannot replace an app.

## Files in Storage

Artifacts live in the database, and are also written as real files so the Storage page can show them: `Application Support/Artifacts/<Title> (<id>)/v<N>.html` (or `.json` for tables and charts), one file per kept version. Settings → Storage has an **Artifacts** row that opens the folder.

- `ArtifactFileMirror` writes it from the database (create, new version, restore, delete) and `SwiftDataArtifactRepository.syncMirror()` brings it up to date once at launch (artifacts saved before the folder existed, files deleted by hand). The database stays the source of truth: nothing is read back from the folder, a failed file write never fails a save, and a file edited or deleted in Storage is put right at the next sync.
- It is ordinary storage, not live data, so the Storage page may delete or copy out of it. `prune` only removes folders named the way the mirror names them; anything else the person puts there stays.
- Tests and previews build the repository with no mirror, so they never touch the real folder. When the real store could not be opened (`storeFailed`), the mirror is off too: the temporary store is empty and a sync would remove copies of artifacts that are safe on disk.

## Limits

| What | Limit |
|---|---|
| Stored payload | 2 MB (2,097,152 B), `ArtifactLimits.maxPayloadBytes` (what an external AI may write) |
| In-app AI output size | Settings → Artifacts → Maximum File Size, 8 to 128 KB (default 20, the user's decision), `ArtifactSettings.maxOutputKB` |
| External AI page | up to 2 MB (`externalMinKB` 128 to `externalMaxKB` 2048) |
| Versions kept | newest 20 per artifact |
| Artifact state (ticks, `storage.*`) | 256 KB total, key ≤ 64 chars |
| Capability args | 64 KB encoded |
| Spec | ≤ 60 blocks, depth ≤ 4, table ≤ 20 × 200, chart ≤ 500 points |
| Strings | truncated (not rejected) in `SpecValidator` |

`library.words` limit 1…500 (default 100), `stats.wordsPerDay` days 1…365 (default 7), `stats.wordsPerWeek` weeks 1…104 (default 8).

## Capabilities

`library.words`, `library.word`, `stats.wordsPerDay`, `stats.wordsPerWeek` (read); `storage.get`, `storage.set`, `storage.remove` (local); `ai.generate` (ai, apps only); `review.flag` (write) and `review.list` (read), see `docs/features/need-review.md`; `words.add`, `words.place` (write), `study.decks` (read), `study.addCards` (write), see `docs/features/chat.md`.

### How to add a capability

Add one `Capability` to a provider in `App/CapabilityProviders.swift` (name, class, summary, args schema, returns summary, handler). Nothing else: the registry dispatches it, the AI manual lists it, specs can bind to it.

## Rendering rules

- Every AI string uses `Text(verbatim:)`; every `ForEach` uses the enumerated offset, never the string.
- Bound blocks load in `.task` and again when the app becomes active. A failed bind shows "Couldn't load data" inline.
- Checklist/roadmap ticks persist in the artifact's state under `spec.<blockID>` (`ArtifactSpecStateStore`), across versions.

## Testing

- `StubAIClient.generateJSON` returns a fixed artifact for schema-less calls whose system instruction contains `---PAYLOAD---`: prompt contains `fallo` → rate limited; prompt contains `CURRENT PAYLOAD:` → adds an "Updated" text block. `StubArtifactTests` runs it through the real generator so stub and prompts cannot drift apart.
- The stub returns an app envelope when the prompt contains "practice app" (or an update of a payload containing "stub app").
- `MockAIClient.generateJSONCalls` / `generateJSONScript` record and script `generateJSON`; tests assert the actual prompt sent (`prompt == request`, `schema == nil`).

## Settings → Artifacts

- `ArtifactSettings` (Core/Storage, UserDefaults key `artifactSettings`, tolerant JSON decoder: add fields, never rename): `maxOutputKB` (8...128, step 4, default 20), `allowAppArtifacts`, `defaultFormat`. `AppEnvironment.artifactSettings` mirrors it; the screen is `Features/Settings/ArtifactsSettingsView`.
- **How the size reaches the AI without changing `AIClient`:** `ArtifactGenerator` runs `generateJSON` inside `ArtifactOutputBudget.$requestedTokens.withValue(...)` (a `@TaskLocal`), and `GeminiClient.structuredMaxTokens` raises `maxOutputTokens` from 8192 to the requested value, never above the model's `outputTokenLimit` and never below 8192. Every other caller is unchanged. The size also goes into the prompt ("At most N KB") and into the app lint, which never exceeds the storage ceiling.
- Tokens per KB use 3 bytes per token plus 1,024 of headroom (`ArtifactOutputBudget`). A model that cannot write that much gets a warning on the settings page; its output is cut off and the generator reports it as truncated, as before.
