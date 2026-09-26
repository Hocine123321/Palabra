# Palabra

A native iPhone app for learning Spanish vocabulary with Google AI. Enter a word you met at school; the app asks a Google AI model for three example paragraphs, meaning and usage, word forms and similar words, saves it permanently, and lets you ask follow-up questions about it.

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
Palabra/App          app entry, dependency container, navigation router
Palabra/Domain       models, validation, keys, pure logic
Palabra/Services     Google AI client, model catalogue, storage
Palabra/DesignSystem theme, glass, motion, shared components
Palabra/Features     onboarding, library, add-word, detail, chat, settings
PalabraTests         unit tests
PalabraUITests       UI tests (stubbed AI)
project.yml          XcodeGen project definition
~~~
