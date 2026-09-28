# Agent guide

Read this before changing code. It explains what the app is, where things live, and which names must not change.

## What this app is

A native iPhone (SwiftUI + SwiftData, iOS 17) **study app** powered by the user's own Google AI (Gemini) API key. It started as a Spanish-vocabulary app and is being generalized into a general study app.

- **Today:** one feature, **Vocabulary** — a library of Spanish words, each with AI-generated examples, meaning, forms, similar words, a follow-up chat and pronunciation audio.
- **Planned:** a second top-level page (next to the Vocabulary library) that holds AI study tools. It does not exist yet. New tools go in their own folder under `Features/` (see "Adding a feature").
- **Naming:** the app is called **Palabra** and keeps that name. It is the product name, not a claim that the app is Spanish-only: the Xcode target/module, the `Palabra/` folder, the display name and the bundle id all stay `Palabra`. Do not propose or start a rename.

## Layout

```
Palabra/
  App/                  entry point, dependency container (AppEnvironment), Router, RootView
  Core/                 shared by every feature — should not know about vocabulary
    AI/                 AIClient protocol, GeminiClient, StubAIClient, AIError, AIModel
    Audio/              WAVAudio (normalizes Gemini TTS output), PronunciationPlayer (AVAudioPlayer wrapper)
    Catalogue/          model catalogue, model filters, default-model picker, API-key entry
    DesignSystem/       Theme, glass surfaces, motion, shared components
    Localization/       SupportedLanguage (app language / AI language: en, ar)
    Storage/            KeychainStore (API key), SettingsStore (UserDefaults)
  Features/
    Onboarding/         first-run screen
    Settings/           settings + model picker (app-wide, not vocabulary-specific)
    Vocabulary/         the Spanish word library
      Domain/           WordContent, WordKey, ContentValidator, Honeycomb, chat types
      Storage/          Word (SwiftData), WordRepository, VocabularyLibraryExporter
      AI/               VocabularyPrompts, VocabularyResponseSchema
      Pronunciation/    PronunciationService, PronunciationButton
      Library/          VocabularyLibraryView (the home screen), grid/list, add-word bar
      AddWord/          add / regenerate flow and preview sheet
      WordDetail/       word screen
      Chat/             follow-up chat about one word
  Resources/            Localizable.strings (ar)
PalabraTests/           unit tests; folders mirror Palabra/ (App, Core, Vocabulary, Support)
PalabraUITests/         UI tests (stubbed AI)
project.yml             XcodeGen project definition (the .xcodeproj is generated, never committed)
docs/features/          notes on shipped features
docs/superpowers/       ORIGINAL Spanish-only design and plan — historical, not current
```

New files under `Palabra/`, `PalabraTests/` and `PalabraUITests/` are picked up automatically by XcodeGen; there is no project file to edit.

## Rules

1. **Dependency direction:** `Features/*` may use `Core/*`. `Core/*` must not use `Features/*`. Features must not use each other's internals.
2. **Known places where this is not true yet** (deliberate leftovers, fix them when the first non-vocabulary tool needs the same code — do not copy them):
   - `AIClient` / `GeminiClient` / `StubAIClient` still carry vocabulary-specific methods (`generateWord`, `sendChat`) and use `WordContent`, `ChatMessage`, `ContentValidator`, `VocabularyPrompts`, `VocabularyResponseSchema`. A general tool needs a generic "send this prompt/schema, get JSON or text back" method on the client, with the vocabulary calls built on top of it.
   - `Theme` (tile tints) calls `WordKey.tintIndex`.
   - `SettingsStore.LibraryLayout` is a vocabulary UI setting stored in Core.
   - `AppEnvironment` owns the `WordRepository`, the `PronunciationService` and `requestPronunciationIfConfigured(for: Word)`; `Router.Destination` has a `wordDetail` case; `PalabraApp` builds the SwiftData schema as `[Word.self]`.
3. **Errors and AI calls** return `Result<_, AIError>`; nothing in the UI should crash on a bad AI response.

## Names that must NOT be changed (they are on users' devices)

Changing any of these silently loses the user's saved words, settings or API key unless you also write a migration and test it:

- Bundle id `dev.palabra.app` and the Keychain service `dev.palabra.app.google`.
- The SwiftData entity `Word` and its stored property names (`spanish`, `key`, `searchKey`, `contentData`, `rawJSON`, `chatData`, `pronunciationAudio`, ...). Renaming a `@Model` class or stored property changes the on-device schema.
- UserDefaults keys in `SettingsStore.Keys`.
- The JSON keys inside `WordContent` (including `spanish` / `english` / `translation` on examples) — stored data and Gemini's response schema both use them.
- The library export envelope (`app: "Palabra"`, `version`) written by `VocabularyLibraryExporter`; old exports must keep importing.

It is fine — and encouraged — to rename Swift *types* and files that are not persisted (that is how `Prompts` became `VocabularyPrompts`).

## User-visible text

- Localization is keyed by the English string: `Resources/ar.lproj/Localizable.strings` maps the exact English text to Arabic. If you change a UI string, change its key there too.
- UI tests find elements by their English text, so changing a string means updating the UI tests as well.
- The user picks the app language and the AI-output language independently (`SupportedLanguage`).

## Build, test, verify

- Builds and tests run in GitHub Actions on a macOS runner (`.github/workflows/build-ipa.yml`). The `ipa` job produces the unsigned IPA (`Palabra-unsigned-ipa` artifact); the `tests` job runs unit and UI tests.
- When the archive or a unit-test step fails, the workflow prints the compiler / test errors as an annotation on the failed job, so they can be read through the GitHub API without downloading logs.
- A green `ipa` job means the app compiles; it does not prove the app works on a device. Check behaviour changes with tests.
- Swift settings: `SWIFT_VERSION 5.0`, `SWIFT_STRICT_CONCURRENCY targeted`.

## Adding a feature (for example a study tool)

1. Create `Palabra/Features/<Name>/` with the same sub-folders it needs (`Domain`, `Storage`, `AI`, screens) and a matching `PalabraTests/<Name>/`.
2. Take the AI client, model, language, API key and design system from `Core` via `AppEnvironment`. Do not build services inside views.
3. Put anything the tool persists in its own SwiftData model, registered where `PalabraApp` builds the schema. Adding a new model is safe; changing an existing one is not (see above).
4. Add a `Router.Destination` case (or a top-level tab once the second page exists) and wire it from `RootView`.
5. Use feature-prefixed names for anything that could be mistaken for app-wide (`VocabularyLibraryView`, not `LibraryView`).
6. Add tests, push, and make sure both CI jobs compile.
