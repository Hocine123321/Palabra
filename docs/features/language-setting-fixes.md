# Language Setting feature — fix notes

The previous implementation added two independent settings (App Language,
for the interface and RTL layout; AI Language, for the language Gemini
explains words in) but shipped broken. Fixed here:

## Critical bugs (the feature didn't work at all)

1. **Didn't compile.** `GeminiClient.swift`'s schema-fallback path called
   `decodeAndValidate(text)`, missing the now-required `language:` argument.
   Any real build (including the repo's own GitHub Actions workflow) would
   have failed outright.

2. **The AI Language setting did nothing.** `VocabularyPrompts.swift`'s prompt
   templates used bare `(name)` instead of Swift's `\(name)` string
   interpolation. That's not interpolation at all — it's literal text. So:
   - The instruction telling Gemini which language to explain in was never
     actually sent; the literal string `(learnerInstruction)` was, instead.
   - Worse, the *chat* system prompt never included the word's JSON context
     either — `(encoded)` was sent literally. This degraded chat quality
     in **both** languages, not just Arabic.
   Fixed by restoring proper `\(...)` interpolation. Added regression tests
   in `GeminiClientTests.swift` that inspect the actual HTTP request body to
   confirm the language instruction and word context are present.

## Secondary bugs (feature partially worked, silently)

3. **Several UI components stored localizable text as `String` instead of
   `LocalizedStringKey`.** In SwiftUI this is a real, easy-to-miss trap:
   `Text(someString)` where `someString: String` always renders verbatim in
   whatever language it was written in, silently ignoring the current
   locale — even if a translation exists in `Localizable.strings`. This
   affected:
   - `ErrorBanner` (every AI error message, e.g. offline/rate-limit/invalid
     key banners)
   - `EmptyStateView` (empty library / no search results screens)
   - `SectionCard` (the four word-detail section headers: Example
     Paragraphs, Meaning & Usage, Word Forms, Similar Words)
   - the word-detail jump bar's chip labels
   - the Save/Replace button in the add-word sheet
   - a few one-off messages (import result, "Not selected", key errors)

   Fixed by typing these as `LocalizedStringKey` and updating call sites
   accordingly (all were literal strings, so this is behavior-preserving in
   English — verified against the existing UI test suite, which asserts
   exact English button/label text).

4. **RTL layout gap.** The custom `FlowLayout` (chip-wrapping layout used
   for translations, similar words, and word forms) always laid out
   left-to-right, ignoring `layoutDirection`. It now mirrors for Arabic.

5. **~25 missing Arabic translations** were added for strings that were
   already being displayed correctly (onboarding copy, a few buttons, and
   dynamic dialogs like "Delete all N words?", "Interpreted as \"X\"",
   "Delete \"X\"?", "\"X\" is already in your Library").

## Known, intentional limitation

`AIError.modelUnavailable(id)` and `.blocked(reason)` (with a reason) embed
a runtime value into an already-built `String` before it reaches the UI, so
they can't be routed through the translation table without a larger
refactor of `AIError`. These two rare error messages remain English-only.
Everything else user-facing now respects App Language.
