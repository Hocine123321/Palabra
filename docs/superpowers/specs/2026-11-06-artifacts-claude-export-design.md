# Artifacts: export prompt for Claude, import of the result

Status: approved by the user, 2026-11-06.

## Intent

App artifacts are only built by Gemini inside Palabra today. The person wants a stronger builder for the apps that matter:
copy a prompt out of Palabra, give it to Claude (or ChatGPT), paste the full app back, and have it run in Palabra with
everything working. Quality bar is higher than Gemini's, so the size ceiling is higher too.

## Goals

- **Export prompt**: one button copies a complete, self-sufficient prompt: the exact system rules Gemini gets (generated
  from `ArtifactPrompts.systemInstruction`, so the live capability manual is always current), the person's request, and
  on update the current payload. It ends by telling the external AI to answer with the `---PAYLOAD---` envelope only.
- **Import**: a paste field feeds the existing path (parse, lint, preview, approval card, save). It accepts the envelope or
  plain HTML (title from `<title>`, requests inferred from `palabra.call("<name>"` usages that exist in the registry).
  On update it adds a version.
- **Higher cap for external apps**: 124 KB (126,976 bytes). The Gemini path keeps 64 KB (65,536 bytes) and its 20 KB prompt rule.

## Non-goals

- No change to the sandbox, the CSP, the capability registry or the approval flow. Imported apps get exactly the same
  permissions model and the same lint (no external URLs, no `localStorage`).
- No new artifact kind; no network call to Claude/ChatGPT; no in-app account for them.
- Spec artifacts keep their current limits.

## Anti-goals

- An import path that skips lint or approval. Pasted HTML is untrusted exactly like Gemini output.
- A silent prompt drift: the export must reuse the generator's system instruction, not a copy of it.

## Constraints

- `ArtifactLimits.maxPayloadBytes` (storage cap, 64 KB) is used by the repository and the lint. It splits into
  `maxPayloadBytes` (Gemini, 65,536) and `maxExternalPayloadBytes` (126,976). The repository accepts up to the external cap;
  the Gemini generator lints against the Gemini cap.
- 20 versions x 124 KB is at most ~2.5 MB per artifact; accepted.
- Refining an imported app larger than 64 KB with Gemini cannot succeed (Gemini output is linted at 64 KB) and reports
  "too large to extend". The route for those apps is export prompt -> Claude -> import as a new version.
- CI cannot run JavaScript inside the web view; say so after the change.
- Repo rules: every new `AIClient` method needs a `MockAIClient` stub (none is added here); new UI strings need Arabic keys
  (`LocalizationTests`).

## Approaches considered

1. **Reuse the generator's prompt and parser (chosen).** Export = system instruction + request; import = existing envelope
   parser + lint with a source-aware cap. Smallest change, cannot drift.
2. A separate hand-written "Claude prompt" and a separate import parser. Rejected: two copies of the rules that drift.
3. Share-sheet / file import of `.html` files. Possible later; clipboard is enough on mobile and needs no entitlements.

## Design

- `ArtifactPrompts.exportPrompt(request:, currentTitle:, currentPayload:, registry:, language:)` builds the text:
  system instruction (kinds `[spec, app]`, but with the app size line set to 120 KB for external use), the request
  (with the `FORMAT:` prefix the create page already builds), the `CURRENT PAYLOAD:` block on update, and a closing
  instruction to reply with the envelope only, no code fences, no commentary.
- `ArtifactPrompts.systemInstruction` gains an `appByteLimit` parameter (default: the Gemini line "At most 20 KB").
- `ArtifactImport.parse(_:, registry:, source: .external)` in `Features/Artifacts/AI/`: tries `ArtifactEnvelopeParser`;
  if no `---PAYLOAD---`, treats trimmed text as HTML when it contains `<html`; strips a surrounding code fence; runs
  `ArtifactHTMLLint.check(_, limit:)`; returns an `ArtifactDraft` with the registered capabilities only.
- `ArtifactHTMLLint.check` gets a `limit` parameter (default Gemini cap) and its message names the limit it used.
- `ArtifactDraftView` request phase: "Copy prompt for Claude" (enabled when the request is long enough) and
  "Paste Claude's answer" (opens a paste sheet; on success the draft goes to the existing preview phase).
  `ArtifactDraftModel` gets `importExternal(_ text:)` setting `draft` and `phase = .preview` or `.failed`.
- Update mode behaves the same with the current payload included in the export.
- The `ArtifactsListView` empty state and docs mention the export route.

## Left to the builder

Exact wording of the closing instruction, the paste sheet layout, Arabic strings, button placement.

## Tests

Export prompt contains the registry manual, the request and the envelope markers (assert on real strings, like the
`MockURLProtocol` tests); import accepts envelope, fenced envelope, bare HTML, rejects external URLs / `localStorage` /
over-cap / missing `<html`; repository accepts a 100 KB payload and rejects 127,000 bytes; Gemini generator still rejects
66,000 bytes; localization test covers new keys.
