# Palabra Study — Web Companion

An early, no-build-tools web companion to the [Palabra](../README.md) iOS app. It adds two study-planner
features that go beyond Spanish vocabulary: **AI-generated flashcards with spaced repetition** and an
**AI-generated quiz from pasted notes** — for any subject, not just language learning.

## Run it

No build step, no dependencies. Either:

- Open `index.html` directly in a browser, or
- Serve it locally (recommended, avoids some browsers' local-file `fetch` restrictions):

  ```sh
  cd web
  python3 -m http.server 8000
  ```

  then visit `http://localhost:8000`.

## Use it

1. **Settings tab** — paste a Google AI API key (free at
   [aistudio.google.com/apikey](https://aistudio.google.com/apikey)) and pick a model. The key is stored
   only in this browser's `localStorage` and sent only to Google's Generative Language API — there is no
   backend and no other server involved.
2. **Flashcards tab** — name a subject, paste your notes (lecture notes, a textbook chapter, anything),
   and generate flashcards. Review the drafts, uncheck any you don't want, and save.
3. **Review tab** — review flashcards due today, one at a time, and grade your recall (Again / Hard / Good
   / Easy). This drives the same simplified SM-2 spaced-repetition schedule used by the iOS app
   (`Palabra/Domain/SpacedRepetition.swift`), so both surfaces treat a review the same way.
4. **Quiz tab** — paste notes and generate a short multiple-choice quiz to self-test immediately.

## Data

Flashcards and their review schedule are stored in this browser's `localStorage` under
`palabra.web.flashcards` — nothing is synced to the iOS app yet (both are independent local stores for now).
A generated quiz is not persisted; it's meant for one sitting.

## Status

This is a first scaffold of the "web version" of the bigger study-helper Palabra is growing into. Natural
next steps: shared storage/sync with the iOS app (e.g. via a small backend and account), more subjects and
content types (summaries, spaced-repetition for the quiz questions themselves), and a proper build/deploy
setup once the feature set stabilizes.
