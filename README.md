# Palabra

A native iPhone study app powered by Google AI. It is growing from a Spanish-vocabulary app into a general study app; see `AGENTS.md` for the architecture and the rules for changing it.

**Vocabulary** (the current feature): enter a Spanish word; the app asks a Google AI model for three example paragraphs, meaning and usage, word forms and similar words, saves it permanently, lets you ask follow-up questions about it, and can play its pronunciation.

**Library organization:** the AI can group your words into sections and tag them; search by word, meaning, section or `#tag`. See `docs/features/library-organization.md`.

**Study:** flashcards with spaced repetition. Decks, a review screen, AI card generation from pasted notes; library words are mirrored into a "Vocabulary" deck.

**Exam:** tests built from your own words: meaning, typing, grammar (blanks, forms, word order), listening and speaking. It works fully offline; with AI switched on it adds fresh sentences, checks written answers and coaches you on your mistakes. Results, weak words and history are kept.

**Solve:** typed or photographed math problems, solved on the device first, then by Wolfram|Alpha (your own App ID, optional), then by Gemini.

**Artifacts and Chat:** AI-built tables, charts, checklists and small apps that run in a locked-down web view, and an assistant that can read and (with your approval) change your library, decks and review list.

**Reliability:** automatic retries, a backup key and backup models, and an offline queue for words added without a connection.

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

Some sideload tools rewrite the bundle id; if it changes, the on-device library does not carry over. Use **Settings > Data > Export library** before reinstalling and **Import library** afterwards. The export is one compact `.palabra` file (compressed binary, not JSON) with the words, sections and tags, pronunciation audio, chats, your decks and study progress. Importing merges: nothing already in the library is overwritten. Exports from older versions (`.json`) still import.

## Project layout

~~~
Palabra/App                  app entry, dependency container, navigation router
Palabra/Core                 shared by every feature: AI client, audio, model catalogue, design system, storage
Palabra/Features/Vocabulary  the Spanish word library (domain, storage, AI prompts, pronunciation, screens)
Palabra/Features/Study       flashcards and spaced repetition
Palabra/Features/Solve       math solver (on-device, Wolfram|Alpha, Gemini)
Palabra/Features/Artifacts   AI-built tables, charts and small apps
Palabra/Features/Chat        the assistant
Palabra/Features/Review      Need Review list
Palabra/Features/Resilience  retry, backup key and model settings
Palabra/Features/Settings    app-wide settings and model picker
Palabra/Features/Onboarding  first-run screen
PalabraTests                 unit tests (folders mirror Palabra/)
PalabraUITests               UI tests (stubbed AI)
docs/features                notes on shipped features
docs/REVIEW.md               code review: open weaknesses and what was fixed
project.yml                  XcodeGen project definition
~~~

See `AGENTS.md` for conventions and for the names that must not change.
