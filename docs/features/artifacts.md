# Artifacts

The Spanish tab's **Artifacts** page. The person asks the AI for a table, chart, roadmap or checklist; it is previewed (live), saved as a versioned artifact, reopened later, updated, and rolled back. Tables and charts can bind live to library data.

Plans B1 (spec artifacts), B2 (`app` artifacts in a sandboxed web view) and C (Need Review) are shipped. Design: `docs/superpowers/specs/2026-10-06-artifacts-design.md`.

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

An `app` artifact is one self-contained HTML document (no external `src`/`href`, no `localStorage`; lint in `ArtifactHTMLLint`, ≤ 64 KB) run in a sandboxed `WKWebView`. Kind cannot change on update.

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

## Limits

| What | Limit |
|---|---|
| Stored payload | 64 KB (65,536 B) |
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
