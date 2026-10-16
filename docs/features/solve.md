# Solve

A tab where a math problem is typed or photographed and solved on the device, then (optionally) by Wolfram|Alpha, then by Gemini. The answer opens on its own page: the problem, a hero answer card, then the other pods (plots, alternate forms, ...), with optional step-by-step.

## Pieces

```
Features/Solve/
  Domain/    SolveModels (SolveResult / SolvePod / SolveSubpod / SolveError), MathInputNormalizer, SolveSettings (+ SolveSettingsStore)
  Service/   MathSolver (protocol + StubMathSolver), CompositeMathSolver + GeminiMathSolver + GeminiLink,
             LocalMathEngine (+ LocalMathSolver), WolframSolver, WolframParser, SolveUsage
  Resources/Math/  nerdamer.bundle.js (Apache-2.0), solver.js (our dispatcher), nerdamer-LICENSE.txt
  Capture/   TextRecognizer (+ VisionTextRecognizer, on device), GeminiTextRecognizer + FallbackTextRecognizer, PhotoPreparer (downscale to 1600 px JPEG), CameraPicker (UIImagePickerController wrapper)
  Storage/   SolveEntry (SwiftData), SolveRepository (+ SwiftDataSolveRepository)
  Library/   SolveRootView, SolveHomeView, SolveResultView, SolveSettingsView, SolveModel / SolveResultModel, WolframKeyField
  SolveTool.swift   @Observable bundle on AppEnvironment (`environment.solve`)
```

## Solve settings (`SolveSettingsView`, from the toolbar and Settings > Solve)

`SolveTool.settings` (`SolveSettings`, persisted by `SolveSettingsStore`, read by the solver off the main thread):

- `photoMode`: `sendToGemini` (default) sends the photo itself to Gemini, which copies the whole problem and solves it in one step (`GeminiMathSolver.solvePhoto`, a 2048 px JPEG, schema ordered `readable, problem, solvable, answer, steps` so the problem is copied before it is solved; multi-part answers and up to 20 steps; saved under the copied problem, which also fills the problem box). `readText` is the older flow (Gemini copies text, Vision behind it). `readOnDevice` never sends the photo anywhere.
- When direct solving can't use Gemini (no key or model: checked first by `SolveTool.geminiReady`; or offline / rate limited) `SolveModel.solvePhoto` reads the text on the device instead and says so through `photoNotice` (a hint, shown in the accent colour; `photoMessage` is for errors); nothing is lost. A photo with no problem shows the "no text found" message.
- `useOnDeviceEngine` off sends every typed problem to Gemini (`CompositeMathSolver.useLocal`).
- `modelID` is a model for Solve only (nil follows the main model); `AppEnvironment.solveModel` resolves it. It goes through `environment.ai`, so retries and backup models apply.
- The optional Wolfram App ID moved here from Settings.

## Flow

1. Photo (camera or library): in the default `sendToGemini` mode it goes straight to `solvePhoto` (see Solve settings). In the other modes -> `FallbackTextRecognizer`: Gemini vision first (`GeminiTextRecognizer`: the photo is downscaled by `PhotoPreparer`, sent with a copy-only instruction and a `{found, text}` schema, answers in the notation `solver.js` understands), then on-device `VisionTextRecognizer` when there is no key, no connection, Gemini fails, or Gemini sees nothing -> `MathInputNormalizer.normalize` -> the editable problem box. The person is still told to check the text. The photo goes to Google only through the person's own key; the camera permission text and the Solve footer say so.
2. Solve -> `SolveModel.solve()`: **saved answer first** (`SolveEntry`, keyed by `MathInputNormalizer.key`), then the chain: `LocalMathSolver` (nerdamer in JavaScriptCore, offline, no key), `WolframSolver` (only when an App ID is saved), `GeminiMathSolver` (needs the Gemini key). A repeat question costs no call.
3. The result is saved and opened. Pod images are downloaded and stored as bytes: Wolfram's image URLs are signed and expire.
4. "Show steps" is a **user-initiated extra call** (`podstate` from the pod's `states`). The richer pod replaces the old one and is saved. If Wolfram has no steps, the offer is cleared and "Open in Wolfram|Alpha" remains.

## Solver chain

- `solver.js` exposes `palabraSolve(text)` and answers only what it can check numerically (roots substituted back, derivatives/integrals by finite differences, limits probed). Anything else, or anything ambiguous (inequalities, trig/exp/log equations, degree > 4, `log` without a base), returns "unsupported" and falls through.
- Gemini goes through `AIClient.generateJSON` with a response schema (no code execution). Its answers are labelled "double-check". Steps offered as `ai:<answer>` are written by Gemini from the checked answer and cost no Wolfram call.
- `SolveResult.source` (`onDevice`, `gemini`, `wolfram`; nil = legacy Wolfram) drives the footer note and what counts toward `SolveUsage`.
- `LocalMathEngine` races an 8 s timeout and swaps its JS context on timeout; a hung script cannot be killed, only abandoned.

## Wolfram|Alpha (optional)

- `GET https://api.wolframalpha.com/v2/query?appid=...&input=...&output=json&format=image,plaintext&mag=2&width=560[&podstate=...]`.
- The person's own App ID (Full Results API) lives in the Keychain (`KeychainStore.wolfram()`, account `wolfram-app-id`). No backend.
- Free tier: 2,000 non-commercial calls a month. "Powered by Wolfram|Alpha" shows on the result screen when Wolfram answered, and on the home screen when an App ID is saved.
- **Unverified:** whether step-by-step is available on the free tier. The app degrades to a message plus the web link.
- Status mapping: 401/403 -> invalid key, 429 -> rate limited, 5xx or a thrown error -> network. `success:false` -> no result (with "did you mean" suggestions).

## Quota

`SolveUsage` is a local tally (UserDefaults key `wolframUsage`, UTC month). It counts a call on success and on "no result", not on network failures or a refused key. It is an estimate; Wolfram keeps the real count. It is shown on the Solve screen and in Solve Settings.

## Tests

- `MockMathSolver` / `MockTextRecognizer` (Support/) for model tests; `WolframSolverTests` use `MockURLProtocol` and assert the request URL (appid, input, podstate) is really sent.
- `SolvePhotoSolvingTests` assert the photo request (image bytes, copy-then-solve instruction, schema order), parsing, the text fallback and the settings. `LocalMathSolverTests` run the real engine; `GeminiMathSolverTests` assert the exact prompt, system instruction and schema sent; `CompositeMathSolverTests` cover the order and error choice.
- UI tests run on `-UITestStub` (`StubMathSolver`, `StubTextRecognizer`); `-UITestNoSolveKey` starts without an App ID (solving still works). In the stub, "fallo" gives a rate-limit error and "zzz" gives no result.
- The camera permission text (`NSCameraUsageDescription`) is in `project.yml` and is not localized.
