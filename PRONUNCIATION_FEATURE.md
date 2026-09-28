# Pronunciation (Gemini TTS)

Saving a word now also asks Gemini's text-to-speech to say it. When the audio
comes back, a play button appears next to the word on its detail screen.

## How it behaves

- **Automatic on save.** `AddWordFlow.save()` (new word *or* regenerate) kicks
  off synthesis in the background. The word saves instantly; nothing waits on
  audio.
- **The button** (`PronunciationButton`, next to the headword) has four states:
  spinner while generating → play/stop once audio exists → a red slashed
  speaker if the attempt failed (tap to retry) → a plain speaker if the word
  has no audio yet (tap to generate — e.g. words saved before this feature, or
  imported libraries). A one-line reason is shown above the word when an
  attempt fails (`PronunciationNotice`).
- **Not on the preview sheet.** Before saving there's no word to attach audio
  to, so `WordContentView` only shows the button where a saved `Word` exists.
- **Auto-generation happens only on save/regenerate**, never just from
  opening a word — browsing your library never spends API calls.
- **Audio is cached** on `Word.pronunciationAudio` (a complete WAV file, a few
  tens of KB). It is *not* included in library export/import — it's
  regenerable, and keeping it out keeps exports small. Regenerating a word's
  content clears its audio (the corrected headword can change) and re-requests
  it.

## Its own model settings

Settings → **Pronunciation** has a model picker and Refresh Models, separate
from the text model. It reuses the same `models.list` call and `ModelCatalogue`
class, just with a different filter (`TTSModelFilter` keeps names containing
"tts" — the exact complement of `ModelFilter`, which drops them) and its own
cache file, so the two selections never clobber each other. `ModelPickerView`
is now shared by both pickers.

A default is chosen automatically (same heuristic as the text model: newest
non-"lite" flash, preferring non-preview) when the API key is saved, and
lazily on first use for people who already had a key before this feature —
so it works without visiting Settings. Choosing your own is never overridden.

## Languages — how I interpreted "compatibility with the different languages"

- **The audio** is always the Spanish headword. Gemini TTS detects the spoken
  language from the text itself, so no language parameter is sent, and the
  audio is independent of both App Language and AI Language (those govern the
  interface and the explanations, not the word being learned).
- **All new UI text** (Settings section, button labels/accessibility labels,
  failure notices) is localized through the existing App Language system, with
  Arabic translations added to `ar.lproj/Localizable.strings`. The button sits
  in an `HStack`, so it mirrors correctly in right-to-left.

If you meant something else (e.g. choosing a Spanish accent/voice, or
pronunciation in other learning languages), that's a small follow-up: the voice
is currently a fixed prebuilt voice ("Kore") in `GeminiClient.synthesizeSpeech`.

## API details worth knowing

- Uses the standard `generateContent` endpoint with
  `responseModalities: ["AUDIO"]` and a prebuilt voice — the request shape
  common to every Gemini TTS model generation, so any model in the picker works.
- Different generations return different formats: newer models return a complete
  WAV; older previews return headerless 16-bit PCM at 24 kHz. `WAVAudio.normalize`
  checks what actually arrived and wraps raw PCM in a WAV header when needed, so
  playback (`AVAudioPlayer`) works either way.

## Tests added

`WAVAudioTests`, `TTSModelFilterTests`, `PronunciationServiceTests`, plus
additions to `GeminiClientTests` (request shape, WAV passthrough, PCM wrapping,
block/error mapping), `ModelCatalogueTests`, `APIKeyEntryTests`,
`SwiftDataWordRepositoryTests`, `SettingsStoreTests`, `AppEnvironmentTests`, and
a play-button assertion in `SmokeUITests`.

## One thing I fixed along the way

The UI-test bootstrap (`-UITestStub`) set a selected model ID but never loaded
the catalogue, so the selection resolved to nothing and the add-word bar was
replaced by the "choose a model" prompt. It now loads the stub catalogues at
launch. (CI marks UI tests `continue-on-error`, so this may have been failing
quietly.)
