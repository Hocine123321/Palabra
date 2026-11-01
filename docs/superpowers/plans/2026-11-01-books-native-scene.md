# Books Native Scene Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Three.js/WKWebView Books 3D scene with a native SceneKit scene that matches it, plus Free view, readability gates and "Pull a test" (recorded self-test), checked by golden numbers, screenshots and real footage.

**Architecture:** Pure Swift core (tweens, book geometry maths, framing, free view, page layout) with no SceneKit import, unit-tested against numbers generated from the JS. A thin SceneKit layer builds nodes and materials from it. Input is one pure decision tree fed by a touch view and by the tour. `BooksSceneModel` keeps its public surface so the HUD and UI tests do not change.

**Tech Stack:** Swift 5 (strict concurrency targeted), SwiftUI, SceneKit, CoreGraphics/CoreText, ReplayKit + AVAssetWriter, XCTest/XCUITest, XcodeGen, GitHub Actions (macos-26), Node (fixtures only, `three` 0.170).

**Spec:** `docs/superpowers/specs/2026-11-01-books-native-scene-design.md`

## Global Constraints

- Nothing compiles here; every change is "compiled by eye only, needs a real CI run". CI is dispatched on branch `native-books` (`gh workflow run build-ipa.yml --ref native-books -f scope=...`); `main` is not changed by code tasks. Deliver as a zip.
- iOS 17 deployment target; `SWIFT_VERSION 5.0`; `SWIFT_STRICT_CONCURRENCY targeted`; iPhone only, all orientations.
- `scripts/check-conventions.sh`: no `withAnimation`/`.animation(` (use `Motion`), no `try? context.save()`, no `Color(hex:)` outside Theme, no numeric `cornerRadius:`. Scene art colours live in `Native/Art/Palette.swift`, which the check is told to skip for `Color(hex:)`-style literals only if needed.
- Names that must not change (AGENTS.md): `textbookState`, page/lesson ids, catalogue and lesson formats, accessibility ids `bookCover.<id>`, `bookBack`, `pageNext`, `pagePrevious`, `pageIndicator`, `focusButton`, `focusExit`, `recallToggle`, `recallLevel`, `recallReveal`, `toolLens`, `toolBookmark`, `toolRuler`, `readAsText`. New ids: `booksSceneNative`, `viewReset`, `pullATestButton`.
- New persisted fields are optional with tolerant decoding: `TextbookState.preferences.freeView` (default true), `.sceneEngine` (`original`|`native`, default `original` until Task 15).
- JS constants copied exactly: PW 1.0, PH = 1820/1280, COVER_T .04, OVER_X .035, OVER_Z .045, SX 28, SZ 8, BLOCK_COLS 14, GUTTER_DIP .03, FOV 32, near .05, far 40, page bitmap 1280x1820, margins top 110 bottom 130 outer 104 gutter 152, GAP 40, TEXT_SCALE {-1:.96, 0:1.1, 1:1.26, 2:1.42}, tween durations and eases from `app.js`.
- Every UI-visible string added gets an `ar.lproj/Localizable.strings` entry keyed by the English text.
- **Spike result (Task 1, verified in CI footage):** SceneKit renders on the macos-26 simulator; PBR, chamfered boxes, `shaderModifiers` and `.forward` shadows work; `.deferred` shadows do NOT render there. All shadow-casting lights use `shadowMode = .forward`.
- Commit messages end with the two trailer lines the harness requires (Co-Authored-By, Claude-Session).

## Review Focus

- A lesson page with zero blocks, a one-page book, and a book with no lessons: one blank leaf, no crash, no off-by-one in `canNext`/`canPrev` (tests in Tasks 5, 7, 11).
- Right-to-left mirroring of every interaction (drag direction, which page the lens is over, bookmark side, framing x) (tests in Tasks 5, 12, 13).
- A single word wider than the column, and the largest text size: layout terminates and never drops a block (Task 7).
- Rapid input: tapping next during a flip, switching tools mid-flight, pinching while a leaf turns, closing during the cover opening (Tasks 11, 13, 14).
- App backgrounded, rotated or memory-warned mid-turn or mid-tour: textures evicted and redrawn, tour restores preferences, no stale animation callbacks (Tasks 10, 15, 17).

---

### Task 1: CI scope input, review job, and rendering spike

**Files:**
- Modify: `.github/workflows/build-ipa.yml`
- Create: `Palabra/Features/Books/Native/Spike/SceneKitSpikeView.swift`, `PalabraUITests/SceneKitSpikeUITests.swift`
- Modify: `Palabra/App/PalabraApp.swift` (launch arg `-UITestSceneKitSpike` shows the spike view as root)

**Interfaces:**
- Produces: workflow input `scope` (`unit` default | `full` | `compile`), job `review` that runs a named UI test class with `TEST_RUNNER_REVIEW_DIR`, records the simulator with `simctl recordVideo`, and publishes `build/review` to branch `ci-recordings` under `latest/`; `SceneKitSpikeView: View`.

- [ ] **Step 1:** Add `workflow_dispatch.inputs.scope` and `.review_test` (string, e.g. `PalabraUITests/SceneKitSpikeUITests`). `FULL_UI` becomes true only for `scope == full`; `compile` stops after build-for-testing. Same pattern as the existing `tour` job for the `review` job (reuse its boot/record/publish steps, output dir `build/review`).
- [ ] **Step 2:** `SceneKitSpikeView` wraps an `SCNView` (lit `SCNBox`, ground plane, shadow-casting directional light, one `SCNMaterial` with a fragment shader modifier tinting by `u_time`); UIViewRepresentable, accessibility id `sceneKitSpike`.
- [ ] **Step 3:** `SceneKitSpikeUITests.testRenders`: launch with `-UITestSceneKitSpike`, wait 2 s, write `XCUIScreen.main.screenshot()` JPEG to `$REVIEW_DIR/spike.jpg`, assert the element exists.
- [ ] **Step 4:** Push `native-books`, dispatch `scope=compile` with `review_test=PalabraUITests/SceneKitSpikeUITests`; fetch `ci-recordings`, open `latest/spike.jpg`.
  Expected: the box, its shadow and the shader tint are visible. If blank/black, stop and tell the owner (spec Step 0).
- [ ] **Step 5:** Commit.

### Task 2: Golden fixtures from the JS

**Files:**
- Create: `web/books3d/scripts/gen-native-golden.mjs`, `PalabraTests/Books/Native/native-golden.json`, `PalabraTests/Books/Native/GoldenFixtures.swift`

**Interfaces:**
- Produces: `GoldenFixtures.load() -> Golden` with `leaves: [LeafCase]` (`p`, `peek`, `grabZ`, `index`, `leafCount`, `bulk`, `positions: [Double]` flat xyz, `normals: [Double]`), `blocks: [BlockCase]` (`h`, `side`, `positions`), `ribbon: [RibbonCase]`, `frames: [FrameCase]` (inputs size/insets/page/rtl/focus/pan → `pos`, `look`, `panLimit`, `pxPerZ`), `eases: [EaseCase]` (`name`, `t`, `value`), `pagination: [PaginationCase]` (page ids → part counts and block index lists with measure = 14 px per char).

- [ ] **Step 1:** Script imports `three` and `src/book3d.js`, `src/tween.js`, `src/pagetex.js`; stubs `document.createElement('canvas')` with a Proxy canvas whose `getContext` returns a chainable no-op, so `Book3D` constructs in Node. Writes the JSON for: leaf counts {1, 3, 8}; progress p in {0, .1, .25, .5, .75, .9, 1}; peek in {0, .6}; grabZ in {.2, .5, .9}; `_restY`; blocks for h in {.05,.2}; ribbon for coverP in {0,.7,1}; framing for sizes {393x852, 852x393, 430x932}, insets {(59,60+..)} (use the real HUD insets from `SceneHUD` formulas), pages {0,1,2,5}, rtl {false,true}, focus {false,true}; eases at t in {0,.1,.25,.5,.75,1}.
- [ ] **Step 2:** `cd web/books3d && npm ci && node scripts/gen-native-golden.mjs`; Expected: JSON written, non-empty arrays for every key.
- [ ] **Step 3:** Swift loader decodes it; test `testGoldenFixturesLoad` asserts every array non-empty.
- [ ] **Step 4:** Commit.

### Task 3: Tweens and easings

**Files:** Create `Palabra/Features/Books/Native/Core/Tweens.swift`; Test `PalabraTests/Books/Native/TweensTests.swift`

**Interfaces:**
- Produces: `enum Ease { case linear, inOut, out, inOutSine, outBack; func apply(_ t: Double) -> Double }`; `final class Tween { var isDead: Bool }`; `final class Tweens { var timeScale: Double; var isActive: Bool; @discardableResult func add(duration: Double, delay: Double = 0, ease: Ease = .inOut, onUpdate: @escaping (Double) -> Void, onDone: (() -> Void)? = nil) -> Tween; func update(dt: Double); func cancel(_ tween: Tween?) }`

- [ ] **Step 1 (tests):** `testEasesMatchGolden` (all `eases` within 1e-9); `testDelayHoldsThenRuns` (delay .5, dt .25 twice → no update, third step starts); `testTimeScaleCollapsesDurations` (`timeScale = 0.001` finishes in one update); `testCancelledTweenNeverFiresDone`; `testOnDoneFiresOnceAtExactlyOne`.
- [ ] **Step 2:** Run (CI `scope=unit`); Expected FAIL (types missing). **Step 3:** Implement as in `tween.js` (`dur = max(0.0001, duration*scale)`, `delay*scale`, progress clamp, dead flag, removal after the pass). **Step 4:** Passes. **Step 5:** Commit.

### Task 4: Book geometry maths

**Files:** Create `Native/Core/BookShape.swift`; Test `PalabraTests/Books/Native/BookShapeTests.swift`

**Interfaces:**
- Consumes: `GoldenFixtures` (Task 2).
- Produces: `enum BookDims { static let pw, ph, coverT, overX, overZ: Double; static let sx = 28, sz = 8, blockCols = 14; static let gutterDip: Double }`; `struct LeafState { var p, peek, grabZ: Double }`; `struct MeshArrays { var positions: [SIMD3<Float>]; var normals: [SIMD3<Float>] }`; `struct BookShape { init(leafCount: Int, bulk: Double); var leaves: [LeafState]; var coverOpen: Double; func restY(_ i: Int) -> (yr: Double, yl: Double); func surfaceY(side: Int) -> Double; func deform(leaf i: Int) -> MeshArrays; func block(height: Double, side: Int) -> BlockArrays; func ribbon() -> [SIMD3<Float>]; static func leafIndices() -> [UInt32] }`

- [ ] **Step 1 (tests):** `testLeafPositionsMatchGolden` and `testLeafNormalsMatchGolden` for every case within 1e-5; `testRestYAndSurfaceYMatchGolden`; `testBlockAndRibbonMatchGolden`; `testOneLeafBookDeformsWithoutNaN` (leafCount 1, all p); `testIndicesAreCounterClockwiseQuads` (count 6*sx*sz).
- [ ] **Step 2:** FAIL. **Step 3:** Port `_restY`, `_deform` (lag, flight, grab, dip, peek), `computeVertexNormals` (area-weighted, summed per vertex, normalized), `_placeBlock`, `_ribbon`; compute in Double, store Float. **Step 4:** Pass. **Step 5:** Commit.

### Task 5: Camera framing

**Files:** Create `Native/Core/Framing.swift`; Test `PalabraTests/Books/Native/FramingTests.swift`

**Interfaces:**
- Produces: `struct ViewMetrics { var size: CGSize; var insetTop: Double; var insetBottom: Double; var fovDegrees = 32.0; var isWide: Bool }`; `struct CameraPose: Equatable { var position, look: SIMD3<Double> }`; `enum Framing { static func rect(cx:cz:hw:hh:pitchDeg:y:_ m: ViewMetrics) -> CameraPose; static func menu(_ m: ViewMetrics) -> CameraPose; static func cover(rtl: Bool, _ m: ViewMetrics) -> CameraPose; static func reading(page: Int, rtl: Bool, focus: Bool, surfaceY: Double, pan: Double, _ m: ViewMetrics) -> (pose: CameraPose, panLimit: Double, pxPerZ: Double); static func menuSlots(wide: Bool) -> [(x: Double, z: Double, ry: Double)]; static func projectionShift(_ m: ViewMetrics) -> Double }`

- [ ] **Step 1 (tests):** `testFramesMatchGolden` (pos/look/panLimit/pxPerZ within 1e-9 for every frame case, rtl and focus included); `testPanIsZeroInPortrait`; `testUsableFractionClampedToHalfMinimum`.
- [ ] **Steps 2-5:** Fail, port `_frameRect/_readTarget/frameMenu` and `_applyCamera`'s `(top-bottom)/2` shift exactly, pass, commit.

### Task 6: Free view maths

**Files:** Create `Native/Core/FreeView.swift`; Test `PalabraTests/Books/Native/FreeViewTests.swift`

**Interfaces:**
- Produces: `struct FreeView: Equatable { var zoom: Double = 1; var pan: SIMD2<Double> = .zero; var isMoved: Bool; mutating func pinch(scale: Double, focus: SIMD2<Double>, limits: ZoomLimits); mutating func drag(by delta: SIMD2<Double>, bounds: PanBounds); mutating func reset(); func rubberBanded(_ z: Double, _ l: ZoomLimits) -> Double }`; `struct ZoomLimits { var minZoom, maxZoom: Double; static let reading = ZoomLimits(0.55, 3); static let menu = ZoomLimits(0.55, 2.5) }`; `struct PanBounds { var extent: SIMD2<Double>; var keepVisibleFraction = 0.3 }`; `struct Inertia { init(velocity: SIMD2<Double>); mutating func step(dt: Double) -> SIMD2<Double>?; }`; `struct SmoothDamp { mutating func step(current: Double, target: Double, dt: Double, smoothTime: Double = 0.18) -> Double }`

- [ ] **Step 1 (tests):** `testZoomClampsWithRubberBand` (1 → 5 caps below 3.3 and relaxes to 3); `testFocalPointStaysUnderFingers` (world point under focus identical before and after pinch, for 5 focus points); `testPanClampKeepsThirtyPercentVisible`; `testInertiaDecaysToZero`; `testResetClearsMoved`; `testReducedMotionPath` (no damping when `smoothTime == 0`).
- [ ] **Steps 2-5:** standard cycle.

### Task 7: Page layout (pagination, rich text, blocks)

**Files:** Create `Native/Layout/PageLayout.swift`, `Native/Layout/BlockLayout.swift`, `Native/Layout/DisplayList.swift`; Test `PalabraTests/Books/Native/PageLayoutTests.swift`

**Interfaces:**
- Consumes: `Lesson`, `Block` (`LessonModels.swift`), `InlineMarkup`/`InlineSegment`, `RecallState`.
- Produces: `struct FontSpec: Hashable { var size: Double; var bold: Bool }`; `typealias Measure = (String, FontSpec) -> Double`; `struct LayoutEnv { var measure: Measure; var rtl: Bool; var scale: Double; var palette: PagePalette; var width: Double }`; `enum DisplayPart` (rich, rect, dot, num, arrow, label, image as in `drawPart`); `struct PhysicalPage { var id, baseID: String; var part, parts: Int; var blocks: [PlacedBlock]; var scale: Double; var title: String; var dateLabel: String?; var lessonTitle: String; var glossary: [String: Term]; var number: Int }`; `enum PageLayout { static func paginate(_ bookPage: BookPage, env: LayoutEnv) -> [PhysicalPage]; static func headerLayout(...) ; static func layoutRich(_ source: String, ...) -> RichLayout }`

- [ ] **Step 1 (tests):** `testPaginationNeverDropsOrReordersABlock` (all bundled books, scales {.88,1,1.28}); `testSplitsMatchGoldenWithFixedMeasure` (14 px/char measure, compare part counts and block index lists); `testWordWiderThanColumnTerminates` (one 400-char word at scale 1.42); `testEmptyPageGivesOneBlankPhysicalPage`; `testRTLRunPositionsMirror` (rtl x = width - ltr x - w); `testRecallRunsMergeAcrossWords`; `testTermHitsPresent`.
- [ ] **Steps 2-5:** Port `toWords`, `layoutRich` (line height 1.85, baseline formula), every `layoutBlock` case (read `pagetex.js` 148-345 first), `headerLayout`, `capacityFor`, `paginate` (scale shrink 0.94/0.88, `GAP` 40).

### Task 8: Fonts and text measuring

**Files:** Create `Palabra/Resources/Fonts/Amiri-Regular.ttf`, `Amiri-Bold.ttf` (+ latin variants if separate), `scripts/convert-amiri-fonts.py`, `Native/Art/PageFonts.swift`; Modify `project.yml` (`UIAppFonts` or runtime `CTFontManagerRegisterFontsForURL`); Test `PalabraTests/Books/Native/PageFontsTests.swift`

**Interfaces:**
- Produces: `enum PageFonts { static func register(); static func ctFont(_ spec: FontSpec) -> CTFont; static let measure: Measure }` (cache keyed by font+text, cascade Amiri → Geeza Pro → Georgia).

- [ ] **Step 1 (tests):** `testAmiriIsRegisteredAndUsed` (font name starts with "Amiri"); `testEveryLessonGlyphHasAnAmiriGlyph` (all characters of all bundled lessons map via `CTFontGetGlyphsForCharacters` on the Amiri CTFont, excluding whitespace); `testMeasureIsMonotonicAndCached`.
- [ ] **Step 2:** `npm ci` in `web/books3d`, `pip install fonttools brotli`, run `convert-amiri-fonts.py` over the four `@fontsource/amiri` woff2 files, commit TTFs. **Steps 3-5:** implement, test, commit.

### Task 9: Page, cover, wood and felt art

**Files:** Create `Native/Art/Palette.swift`, `PageRenderer.swift`, `CoverArt.swift`, `DeskArt.swift`; Test `PalabraTests/Books/Native/ArtTests.swift`

**Interfaces:**
- Produces: `struct PagePalette`; `enum Palettes { static func forSubject(_: String) -> PagePalette }`; `enum PageRenderer { static func draw(_ page: PhysicalPage?, face: Face, rtl: Bool, subject: String, recall: RecallState?, revealAll: Bool, density: Double, images: [String: CGImage]) -> (image: CGImage, hits: [HitRegion]) }`; `struct HitRegion { enum Kind { case recall(key: String, level: Int), term(id: String) }; var rect: CGRect }`; `struct CoverTextures { var color, metalRough, bump, endpaper: CGImage }`; `enum CoverArt { static func make(subject: String) -> CoverTextures; static func pageEdge() -> CGImage }`; `enum DeskArt { static func wood() -> (map: CGImage, bump: CGImage); static func felt() -> CGImage }`; `struct SeededRandom { init(seed: Int); mutating func next() -> Double }` (LCG 16807 mod 2147483647).

- [ ] **Step 1 (tests):** `testSeededRandomMatchesJS` (first five values for seeds 42, 5, 11 equal golden); `testBlankPageIsPaperColour` (centre pixel within 12/255 of paper); `testHitsForTermsAndConcealedRecall`; `testConcealedAnswerIsNotDrawn` (pixels in the blot area contain no ink-colour text pixels); `testPageSizeIs1280x1820AtDensity1AndScales`; `testCoversHaveExpectedSizes`.
- [ ] **Steps 2-5:** Port `drawPage`, `drawPart`, cover and desk canvases operation by operation (gradients, grain, foil, hairline text stroke 1.1/1.5, term dotted underline, blot gradient). Add golden pixel samples from a Node render only if `skia-canvas` is installable; otherwise rely on Task 16 screenshots.

### Task 10: Native scene shell, engine switch, menu and cover opening

**Files:**
- Create: `Native/Scene/BookSceneController.swift`, `BookNode.swift`, `DeskNode.swift`, `SceneRig.swift` (camera, lights, background), `TouchSurface.swift`, `Native/BooksNativeSceneView.swift`
- Modify: `Features/Books/Scene/BooksSceneView.swift` (choose native or WKWebView by `preferences.sceneEngine`), `Features/Books/Storage/TextbookState.swift` (+`sceneEngine`, `freeView`), `Features/Books/Views/BooksSettingsView.swift` (+Scene engine picker, +Free view switch), `Features/Books/Scene/BooksBridge.swift` (+`SceneCommand.setFreeView(Bool)`; keep `javaScript` for the original engine until Task 20), `Resources/ar.lproj/Localizable.strings`
- Test: `PalabraTests/Books/NativeSettingsTests.swift`

**Interfaces:**
- Consumes: Tasks 3-9.
- Produces: `@MainActor final class BookSceneController { init(model: BooksSceneModel, library: BookLibrary, state: TextbookState, reducedMotion: Bool); var view: SCNView; func apply(_ command: SceneCommand); func resize(_ m: ViewMetrics); func openBook(id: String, pageID: String?); func closeBook(); func setAppearance(dark: Bool); func setQuality(_ q: SceneQuality) }`; `BookNode` (`init(subject:rtl:leafCount:bulk:)`, `setCoverOpen(_:)`, `setLeafProgress(_:_:)`, `setLeafTexture(_:face:image:)`, `relayout()`); host sets accessibility id `booksSceneNative`; `BooksSceneModel.attach(controller:)` replaces `run`.

- [ ] **Step 1 (tests):** `testPreferencesDecodeWithoutNewKeys` (old JSON → engine `original`, freeView true); `testNewPreferencesRoundTrip`; `testSettingsCommandMapsFreeView`.
- [ ] **Steps 2-4:** Implement controller state machine (`menu/opening/reading/closing`), menu slots, hover lift, `openBook` choreography (0.8 s book to origin with 0.35 arc, camera to cover frame 0.8 s, cover 1.15 s after 0.55 s delay, camera to reading 1.2 s), `closeBook` (flip back, cover 0.9 s, return), `_closeAfterOpen`, RTL mirrored body, `SCNView` as render-on-demand (`rendersContinuously = false`, `isPlaying` only while tweens/dirty) driven by `SCNSceneRendererDelegate.renderer(_:updateAtTime:)`. Desk, mat, cutouts (`SCNShape`), lamp, inkwell, pencil, tools (static meshes only here) as in `desk.js`/`tools.js`. Materials: `.physicallyBased`. Lights: ambient+hemisphere stand-in, sun with shadow (frustum ±3.2/3.4, map 2048 or 1024), dark lamp spot. Camera: vertical FOV 32, projection shift from `Framing.projectionShift`.
- [ ] **Step 5:** Push, dispatch `scope=unit`, then review job on a smoke UI test `BooksNativeUITests.testMenuShowsBothBooks` (asserts `booksSceneNative` exists, `bookCover.history` exists, tap opens, `pageIndicator` appears). Fetch footage, extract frames with ffmpeg, inspect. Commit.

### Task 11: Reading: leaves, textures window, page turns, resume, text size

**Files:** Create `Native/Scene/LeafTextures.swift`, `Native/Scene/PageTurning.swift`, `Native/Core/InputRouter.swift`; Modify `BookSceneController.swift`, `BookNode.swift`, `TouchSurface.swift`; Test `PalabraTests/Books/Native/InputRouterTests.swift`, `LeafTexturesTests.swift`

**Interfaces:**
- Produces: `struct PointerEvent { enum Phase { case down, move, up, cancel }; var phase: Phase; var location: CGPoint; var time: TimeInterval; var isMouse: Bool }`; `protocol SceneHitTesting { func book(at: CGPoint) -> String?; func tool(at: CGPoint) -> ToolKind?; func page(at: CGPoint) -> PageHit?; func planePoint(side: Int, at: CGPoint) -> SIMD2<Double>? }`; `final class InputRouter { init(host: InputHost, hits: SceneHitTesting); func handle(_ e: PointerEvent) }` where `InputHost` is the controller's command surface (`openBook`, `beginTurn(...)`, `setLeafProgress`, `finishTurn(complete:)`, `placeLens(...)`, `tapPage(at:)`, `pan(by:)`…); `final class LeafTextures { init(entry:...); func ensure(around page: Int); func redrawVisible() }`.

- [ ] **Step 1 (tests, fake host and hits):** `testTapOnBookOpensIt`; `testDragFromOuterEdgeBeginsTurnAndCompletesPast42Percent` (+ back at 58%); `testFastFlickCompletesAtVelocityOver0_9`; `testReleaseEarlyFallsBack`; `testMovementUnder8PointsIsATap`; `testRTLDragDirectionIsMirrored`; `testCannotTurnPastLastPage`; `testSecondTurnIgnoredWhileLeafTweening`; `testTapDuringOpeningQueuesCloseAfterOpen`.
- [ ] **Steps 2-4:** Port `_down/_move/_up/_hoverMove/_beginTurn/_dragTurn/_canTurn`, `goToPage` (stagger/duration rules), `_afterNavigate` (posts visit/state), `setTextSize` (relayout, keep base page), texture window ±3 assign, ±6 keep, 1280x1820 bitmaps drawn on a background queue and uploaded on main; leaf materials with a shader modifier for the ruler band (`uBand`).
- [ ] **Step 5:** CI unit + review footage of page turns; extract frames mid-turn and compare curve shape with the JS golden. Commit.

### Task 12: Tools, lens shader, Focus, Memorize, terms, bookmark

**Files:** Create `Native/Scene/ToolNodes.swift`, `LensShader.swift`, `RecallController.swift`; Modify controller; Test `PalabraTests/Books/Native/ToolPoseTests.swift`

**Interfaces:**
- Produces: `enum ToolKind: String { case lens, bookmark, ruler }`; `enum ToolPoses { static func use(_ k: ToolKind, side: Int, rtl: Bool, surfaceY: Double) -> (position: SIMD3<Double>, euler: SIMD3<Double>); static func rest(_ k: ToolKind, focus: Bool) -> (...) }`; lens uniforms identical to `LENS_FRAG` (`tPage, uWorldToBook, uCamBook, uCentre, uPlaneY, uMag 1.9, uSide, uRtl, uHas, uPW, uPH, uTone .92/.78`); the 2048-wide fully revealed bitmap for the lens.

- [ ] **Step 1 (tests):** `testUsePosesMatchSpec` (lens x = rtl*side*0.5, y = surface + .26, z .1; ruler y = surface+.012, z -.25; bookmark x = side*(PW-.16), z = -PH/2+.17), `testBookmarkPlacedAndRemovedPostsMessages`, `testSwitchingToolStowsPrevious`, `testFocusHidesPropsAndKeepsTools`, `testRecallLevelChangeClearsReveals` (uses `RecallState`), `testLensSideFollowsMirroredX`.
- [ ] **Steps 2-4:** flights (0.85 s with arc .45/.35 sin lift, slerp), ruler band, bookmark persistence message, Focus (props opacity 0.7 s; camera 0.9 s), terms via hit regions, recall blots tap/redraw, lens refresh keys, `setTool` rules. **Step 5:** footage review; commit.

### Task 13: Free view gestures and recenter

**Files:** Modify `TouchSurface.swift`, controller, `SceneHUD.swift` (+`viewReset` button), localizations; Test `PalabraTests/Books/Native/FreeViewGestureTests.swift`, UI test `BooksNativeUITests.testPinchAndRecenter`

**Interfaces:**
- Consumes: `FreeView`, `InputRouter`. Produces: `SceneCommand.setFreeView`; `SceneState.viewMoved: Bool`; controller applies `FreeView` as an offset after `Framing` (dolly along the view axis, pan on the desk plane, focal point fixed by ray/plane maths); double tap resets; page turn keeps zoom and re-centres pan; text-size/book change resets.

- [ ] **Step 1 (tests):** the Task 6 maths through the controller's offset (`testPinchKeepsFocusPoint`), `testSwipeBodyPansWhenZoomedButEdgeStillTurns`, `testTurnKeepsZoomResetsPan`, `testFreeViewOffDisablesGestures`. UI: pinch out/in, `pageIndicator` unchanged, `viewReset` appears then disappears after tap.
- [ ] **Steps 2-5:** standard cycle with footage.

### Task 14: Pull a test (recorder, overlay, runner, report, Settings button)

> Ordering: the recorder, banner, finger ring, runner skeleton, log and Settings button are built right after Task 10 (steps 1-3 below) so every later task's review run already produces footage; each later task appends its own `TourAction`s. The full script and the result screen are completed here.

**Files:** Create `Features/Books/Tour/TourScript.swift`, `TourRunner.swift`, `TourRecorder.swift`, `TourOverlay.swift`, `TourReport.swift`, `TourView.swift`, `TourSnapshot.swift`; Modify `BooksSettingsView.swift` (Test section, button `pullATestButton`), `BooksSceneScreen.swift`; add `-UITestTour` handling; Test `PalabraTests/Books/Tour/TourTests.swift`, `PalabraUITests/BooksTourRunUITests.swift`

**Interfaces:**
- Produces: `struct TourAction { let id: String; let caption: String; let run: (TourContext) async -> Void; let expect: (SceneState, FreeViewInfo) -> String? ; let timeout: Double }`; `enum TourScript { static let actions: [TourAction] }` (the nine chapters in the spec); `@MainActor final class TourRunner { init(controller:, model:, recorder: TourRecording); func run() async -> TourReport; func stop() }`; `protocol TourRecording { func start() async throws; func stop() async throws -> URL? }` with `ReplayKitRecorder` and `NoRecorder`; `struct TourReport: Codable` (device, ios, refresh, engine, quality, appearance, actions: [ActionResult(id, caption, start, end, expected, observed, pass, reason, avgFrameMs, worstFrameMs, slowFrames)], warnings, residentMB); `TourSnapshot.capture()/restore()` (also persisted for crash recovery, restored in `PalabraApp.init`).

- [ ] **Step 1 (tests):** `testScriptIdsUniqueAndNonEmpty`; `testEveryChapterPresent` (nine); `testReportRoundTrips`; `testSnapshotRestoresPreferencesAfterAbort`; `testRestoreRunsAtNextLaunchIfMarkerPresent`; `testButtonDisabledForOriginalEngine`; `testRunnerContinuesAfterFailedExpectation`; UI: with `-UITestTour` and `NoRecorder` all actions pass.
- [ ] **Steps 2-4:** Runner feeds `InputRouter.handle(PointerEvent)` with scripted paths (speeds from real use), uses HUD handlers for buttons, rings in `TourOverlay`, banner "n of N · caption", `CADisplayLink` frame stats; `ReplayKitRecorder` uses `RPScreenRecorder.startCapture` → `AVAssetWriter` H.264 ≈780 px wide, bitrate chosen from estimated length to stay under 40 MB; result view with `ShareLink`/`UIActivityViewController` for mp4+json. Update CI `review` job to run `BooksTourRunUITests` and publish `latest/tour.mp4` + `tour.json`; delete `BooksTourUITests` and the old `tour` job after the new one is green.
- [ ] **Step 5:** Run review job; extract frames at log times with ffmpeg; fix; commit.

### Task 15: Lighting, shadows, environment, tone; parity tuning

**Files:** Create `Native/Scene/SceneLighting.swift`, `ToneTechnique.swift`, `Environment.swift`; `PalabraUITests/BooksParityShotsUITests.swift`; `scripts/compare-shots.py`

**Interfaces:**
- Produces: waypoint screenshots (menu portrait/landscape light/dark, cover open, page 1, page 2, lens, ruler, bookmark, Focus, Memorize hidden/revealed, four text sizes) written to `$REVIEW_DIR/<engine>/<name>.png` and `pageIndicator` texts to `pages.json`; `compare-shots.py baseline/ native/` prints per-waypoint mean abs diff, contrast ratio, mean luminance and Laplacian variance of the text crop.

- [ ] **Step 1:** UI test runs on `sceneEngine=original` (baseline from current main bundle) and `native` by launch argument `-UITestSceneEngine`. **Step 2:** run both through the review job; `compare-shots.py` must show native contrast, luminance and sharpness ≥ baseline. **Steps 3-5:** tune environment intensity, sun, ambient, tone curve (Khronos Neutral + exposure .92/1.1), shadow radius/bias; repeat until differences are visually minor on looked-at frames; flip default engine to `native`; commit.

### Task 16: Readability

**Files:** Modify `LeafTextures.swift`, controller, `BookShape` gutter parameter; Test `PalabraTests/Books/Native/ReadabilityTests.swift`

**Interfaces:** `PageDensity.choose(onScreenWidthPoints: Double, scale: Double, maxBytes: Int) -> Double` (1…2.5); `BookShape.deform` gains `gutterScale: Double = 1`; scene host exposes plain page text through `accessibilityValue`.

- [ ] **Step 1 (tests):** `testDensityGrowsWithZoomAndRespectsMemoryCap`; `testGutterEasedWhileReading` (0.4 reading, 0 focus, 1 elsewhere); `testAccessibilityTextForPage`; `testHighDensitySwapKeepsHits`. **Steps 2-5:** cycle plus waypoint compare for zoomed-in crops.

### Task 17: Enhancement tier (one item per CI run)

**Files:** Create `Native/Scene/Enhancements/` (`AmbientOcclusion`, `DepthOfField`, `LampBloom`, `DustMotes`, `MaterialDetail`, `LeafShadow`, `RibbonSway`, `MotionSway`, `ExtraProps`); Modify controller flags; Test `EnhancementGatingTests.swift`

**Interfaces:** `struct EnhancementFlags { var ao, dof, bloom, dust, sway, flicker: Bool; static func resolve(quality: SceneQuality, reduceMotion: Bool, moved: Bool, reading: Bool) -> EnhancementFlags }`.

- [ ] **Step 1 (tests):** `testSaverTurnsEverythingOff`; `testReduceMotionRemovesMovingEffects`; `testDepthOfFieldOffWhenReadingOrMoved`; `testDustNeverInReading`. **Steps 2-5:** for each item: implement, review footage and readability compare (must not regress), keep or cut, commit.

### Task 18: Performance pass

**Files:** Modify controller, `LeafTextures`; Create `PalabraTests/Books/Native/PagePerfTests.swift`

- [ ] **Step 1 (test):** `testScriptedPageTurnFrameWork` using `measure` on `BookShape.deform` for 8 leaves ×60 frames (budget well under 1 ms/frame on the runner); `testBitmapMemoryBudget` (≤150 MB for 7 pages at max density). **Steps 2-5:** profile via the tour's frame stats, fix hotspots (reuse buffers, update only dirty leaves, cap per-frame texture uploads), commit.

### Task 19: Cleanup, docs, hand-over

**Files:** Delete `web/books3d`, `Palabra/Resources/Books3D`, the `scene` job, the WKWebView host, `BooksScenePayload`, JS command strings, `BooksTourUITests`, the engine picker (after the owner accepts); Modify `AGENTS.md` (Books section rules 1-3 and the layout), `docs/features/books.md`, `PalabraTests/Books/BooksBridgeTests.swift`.

- [ ] **Step 1:** Wait for owner acceptance of the native scene. **Step 2:** remove the above; update tests so `SceneCommand` keeps its dictionary only if still used. **Step 3:** full CI (`scope=full`) green. **Step 4:** zip of the repo to `SendUserFile`. **Step 5:** commit; tell the owner it is compiled by CI only and not device-verified beyond footage.
