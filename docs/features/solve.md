# Solve

A tab where a math problem is typed or photographed and solved by Wolfram|Alpha. The answer opens on its own page: the problem, a hero answer card, then the other pods (plots, alternate forms, ...), with optional step-by-step.

## Pieces

```
Features/Solve/
  Domain/    SolveModels (SolveResult / SolvePod / SolveSubpod / SolveError), MathInputNormalizer
  Service/   MathSolver (protocol + StubMathSolver), WolframSolver, WolframParser, SolveUsage
  Capture/   TextRecognizer (Apple Vision on device), CameraPicker (UIImagePickerController wrapper)
  Storage/   SolveEntry (SwiftData), SolveRepository (+ SwiftDataSolveRepository)
  Library/   SolveRootView, SolveHomeView, SolveResultView, SolveModel / SolveResultModel, WolframKeyField
  SolveTool.swift   @Observable bundle on AppEnvironment (`environment.solve`)
```

## Flow

1. Photo (camera or library) -> `VisionTextRecognizer` (on device, free, offline) -> `MathInputNormalizer.normalize` -> the editable problem box. Vision is weak on math notation, so the person is told to check the text; the symbol row and the normalizer exist for that.
2. Solve -> `SolveModel.solve()`: **saved answer first** (`SolveEntry`, keyed by `MathInputNormalizer.key`), then the missing-key check, then `WolframSolver.solve`. A repeat question costs no call, even without a key.
3. The result is saved and opened. Pod images are downloaded and stored as bytes: Wolfram's image URLs are signed and expire.
4. "Show steps" is a **user-initiated extra call** (`podstate` from the pod's `states`). The richer pod replaces the old one and is saved. If Wolfram has no steps, the offer is cleared and "Open in Wolfram|Alpha" remains.

## Wolfram|Alpha

- `GET https://api.wolframalpha.com/v2/query?appid=...&input=...&output=json&format=image,plaintext&mag=2&width=560[&podstate=...]`.
- The person's own App ID (Full Results API) lives in the Keychain (`KeychainStore.wolfram()`, account `wolfram-app-id`). No backend.
- Free tier: 2,000 non-commercial calls a month. "Powered by Wolfram|Alpha" must stay visible on the home and result screens.
- **Unverified:** whether step-by-step is available on the free tier. The app degrades to a message plus the web link.
- Status mapping: 401/403 -> invalid key, 429 -> rate limited, 5xx or a thrown error -> network. `success:false` -> no result (with "did you mean" suggestions).

## Quota

`SolveUsage` is a local tally (UserDefaults key `wolframUsage`, UTC month). It counts a call on success and on "no result", not on network failures or a refused key. It is an estimate; Wolfram keeps the real count. It is shown on the Solve screen and in Settings -> Math Solver.

## Tests

- `MockMathSolver` / `MockTextRecognizer` (Support/) for model tests; `WolframSolverTests` use `MockURLProtocol` and assert the request URL (appid, input, podstate) is really sent.
- UI tests run on `-UITestStub` (`StubMathSolver`, `StubTextRecognizer`); `-UITestNoSolveKey` starts without an App ID. In the stub, "fallo" gives a rate-limit error and "zzz" gives no result.
- The camera permission text (`NSCameraUsageDescription`) is in `project.yml` and is not localized.
