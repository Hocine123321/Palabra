# Palabra

A native iPhone study app powered by Google AI. It is growing from a Spanish-vocabulary app into a general study app; see `AGENTS.md` for the architecture and the rules for changing it.

**Vocabulary** (the current feature): enter a Spanish word; the app asks a Google AI model for three example paragraphs, meaning and usage, word forms and similar words, saves it permanently, lets you ask follow-up questions about it, and can play its pronunciation.

**Library organization:** the AI can group your words into sections and tag them; search by word, meaning, section or `#tag`. See `docs/features/library-organization.md`.

**Planned:** a second page of AI study tools.

## Build and install (no Mac required)

1. Create a GitHub repository, push this project to `main`.
2. Open the repository's **Actions** tab. The **Build** workflow starts automatically (or run it with *Run workflow*).
3. When the `ipa` job finishes, download the artifact **Palabra-unsigned-ipa** and extract `Palabra-unsigned.ipa`.
4. Sideload it with a tool that signs with your free Apple ID (AltStore, Sideloadly, or a Linux equivalent). Free certificates last 7 days; re-sign weekly.
5. In the app, paste your Google AI API key (get one at https://aistudio.google.com/apikey).

The IPA is **unsigned by design**. It cannot be installed until a sideload tool signs it.

## Tests

The `tests` job runs unit tests, UI tests (with screenshots uploaded as the `test-results` artifact) and packages nothing. To also run the live Google API smoke test, add a repository secret named `GEMINI_API_KEY`.

## Data safety

Some sideload tools rewrite the bundle id; if it changes, the on-device library does not carry over. Use **Settings > Data > Export library** before reinstalling and **Import library** afterwards.

## Project layout

~~~
Palabra/App                  app entry, dependency container, navigation router
Palabra/Core                 shared by every feature: AI client, audio, model catalogue, design system, storage
Palabra/Features/Vocabulary  the Spanish word library (domain, storage, AI prompts, pronunciation, screens)
Palabra/Features/Settings    app-wide settings and model picker
Palabra/Features/Onboarding  first-run screen
PalabraTests                 unit tests (folders mirror Palabra/)
PalabraUITests               UI tests (stubbed AI)
docs/features                notes on shipped features
project.yml                  XcodeGen project definition
~~~

See `AGENTS.md` for conventions and for the names that must not change.
