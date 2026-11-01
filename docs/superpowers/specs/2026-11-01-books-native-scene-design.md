# Books 3D scene: native SceneKit rewrite

Date: 2026-11-01. Status: draft, waiting for approval. Size: project.

## Intent

The Books tab is a Three.js scene running in a `WKWebView` (`web/books3d`, ~2.7k lines of JS, bundled into
`Resources/Books3D/books3d.html`). The owner wants it rebuilt entirely in native iOS code so the scene stops being limited by
web-view performance and more can be added to it later. The rebuilt scene must look and behave like the current one.

## Goals

1. Same pictures: desk, felt mat, cutouts, lamp, props, both books (covers, spine bands, page blocks, ribbon, leaves), tools,
   light and dark looks, both orientations. Geometry, page layout, text, colours, camera framing and timings match the JS
   numbers exactly. Shading (lighting, shadows, tone) is tuned until a side-by-side is visually indistinguishable at normal
   viewing size (see "Parity method"). Bit-identical shading is not possible in any native engine and is not promised.
2. Same behaviour: every interaction rule in `app.js` (tap a book, cover opening, drag/tap page turns with the same
   thresholds, edge peek, tools and their flights, Focus Mode, Memorize, definitions, text size relayout, bookmarks,
   resume page, landscape pan, Reduce Motion, quality setting, right-to-left mirroring) is reproduced.
3. The SwiftUI layer (`SceneHUD`, `BooksSceneScreen`, Settings), the accessibility ids, `TextbookState`, `BookShelf`, lesson
   JSON and the catalogue stay as they are. The UI tests keep passing unchanged.
4. Steady 60 fps on a modern iPhone, and no main-thread stalls while pages are drawn.
5. After this change, adding scene content means adding Swift nodes. No JS, no Node build, no bundle step.
6. **Readability is a gate, not a preference.** The page text must be at least as sharp, as high-contrast and as evenly lit as
   in the web scene in every pose, and no atmosphere effect may trade it away (see "Readability").
7. **Immersion and detail beyond the web scene**, added only after parity is accepted, in a separate tier (see "Enhancement
   tier"). Parity comes first so the owner can tell a regression from a deliberate change.

8. **Free view.** The person can move the camera with their fingers: pinch to zoom out and in smoothly, drag to move the view
   (for example when the book sits low behind the controls), in the menu and while reading. It is an option in Books Settings
   and part of parity sign-off, not the later tier (see "Free view").

9. **"Pull a test": real footage for review.** A button in Settings runs a scripted walk through the whole Books feature on the
   person's own device the way a regular user would use it, records the screen to an MP4 with each action captioned, and hands
   the MP4 and a machine-readable log over so Claude can review actual footage and fix what it shows (see "Pull a test").
   This is how the work is checked beyond code and unit tests, and it is built early so every later step can be reviewed with it.

## Non-goals

- No new lesson block types, no lesson format change, no scene features outside Free view, Pull a test and the Enhancement tier below.
- No change to Classic pages (`BookshelfView` and the reader), which stay the fallback.
- No AI, OCR or upload in Books (existing rule).

## Anti-goals (a failure even if it compiles)

- A scene that looks "close" but turns pages differently, frames the page differently, or loses Arabic text shaping.
- Anything that renames or breaks persisted state: `textbookState`, page and lesson ids, the saved bookmark, resume page.
- Text clipped or content dropped by the new layout (the JS test "pagination never drops or reorders a block" must hold).
- Claiming the look is verified without CI screenshots to show it.

## Constraints

- Nothing can be compiled or run where this work is done. GitHub Actions (macOS runner) is the only compiler, so everything
  is written to compile by eye and checked by CI. Every report says so.
- Deployment target iOS 17. `SWIFT_VERSION 5.0`, `SWIFT_STRICT_CONCURRENCY targeted`. iPhone only, portrait and landscape.
- `scripts/check-conventions.sh` rules apply (no `withAnimation` / `.animation(`, no `try? context.save()`, no hardcoded
  `Color(hex:)`, no numeric corner radii). Scene art colours that must equal the JS values live in one palette file that
  the check is told about, rather than being scattered.
- AGENTS.md "names that must not change" applies: textbook state, ids, catalogue and lesson formats, the accessibility ids
  `bookCover.<id>`, `bookBack`, `pageNext`, `pagePrevious`, `pageIndicator`, `focusButton`, `focusExit`, `recallToggle`,
  `recallLevel`, `recallReveal`, `toolLens`, `toolBookmark`, `toolRuler`, `readAsText`.
- Delivery to the owner is a zip of the full repo (or labelled changed files), not a PR (owner works on mobile).

## Approaches considered

| | SceneKit | RealityKit | Raw Metal |
|---|---|---|---|
| Fit to the Three.js scene graph | Nodes, materials, lights, shadows map one to one | Entity/component model, different shape | None, all written by hand |
| Dynamic page curl | `SCNGeometrySource` rebuilt per frame | `LowLevelMesh` is iOS 18+, target is 17 | Full control |
| Lens (view-ray magnifier) | Shader modifier | Custom Metal material | Full control |
| Compile-blind risk | Medium | High | Highest (a PBR renderer from scratch) |
| Long-term | Apple lists it as maintenance-only, still works on iOS 26 | Apple's direction | Always valid |

**Chosen: SceneKit** (owner approved the recommendation). Reasons: closest model to the existing scene, runs on iOS 17,
smallest compile-blind surface. Accepted cost: Apple may later retire it; the scene logic (tweens, input, layout, geometry
math, page drawing) is written in plain Swift/CoreGraphics so only the thin node/material layer would change.

## Design

### Module map (JS to Swift)

New folder `Palabra/Features/Books/Native/` (Books stays self-contained; Core is not touched).

| JS | Swift | Notes |
|---|---|---|
| `app.js` `App` | `BookSceneController` (+ extensions per concern) | State machine menu/opening/reading/closing, owns the `SCNScene`, tweens, camera, tools, focus, recall, input dispatch |
| `tween.js` | `Tweens` | Same easings (`inOut`, `out`, `inOutSine`, `outBack`, `linear`), delay, `scale` for Reduce Motion; stepped from the renderer delegate |
| `book3d.js` | `BookNode` | Same constants (PW 1, COVER_T .04, OVER_X/Z, SX 28, SZ 8, BLOCK_COLS 14, GUTTER_DIP .03), same `_deform` maths, `_restY`, `_placeBlock`, ribbon; mirrored body for RTL |
| `desk.js` | `DeskNode` | Desk slab, felt mat, cutouts, lamp, inkwell, pencil |
| `tools.js` | `LensTool`, `BookmarkTool`, `RulerTool` | Rest and use poses copied |
| lens GLSL | `LensShader` (SceneKit shader modifier) | Same view-ray maths and uniforms |
| `cover.js` | `CoverArt` | CoreGraphics, same seeded generator (LCG 16807) so grain matches |
| `pagetex.js` layout | `PageLayout` | `layoutRich`, `layoutBlock`, `headerLayout`, `paginate`, `GAP`, margins; works from the Swift `Lesson`/`Block` models and `InlineMarkup` directly (no JSON round trip) |
| `pagetex.js` `drawPage` | `PageRenderer` | CoreGraphics + CoreText into a 1280x1820 bitmap; returns hit regions |
| `pagetex.js` `RecallState` | existing `RecallState.swift` | Already mirrors it |
| `data.js` | `BookLibrary` (existing) + a small adapter | Page numbering, glossary, resume index |
| `hud.js`, `main.js`, `markup.js` | not needed | HUD is SwiftUI; markup is `InlineMarkup.swift` |
| WKWebView host | `BooksSceneView` rewritten around `SCNView` | Same `UIViewRepresentable` name and call site |
| (new) | `FreeView` (+ gesture layer in the touch view) | Pinch/pan camera offset, see "Free view" |
| (new) | `Features/Books/Tour/`: `TourScript`, `TourRunner`, `TourRecorder`, `TourOverlay`, `TourReport`, settings row and result view | "Pull a test", see below |

### Bridge

`BooksSceneModel` keeps its public surface: `state: SceneState`, `isReady`, `activeTerm`, `failure`, `notice`, `send(_:)`.
`SceneCommand` stays (HUD unchanged) but loses its JavaScript form. The controller calls the model directly instead of
posting dictionaries, so `SceneMessage`, `BooksScenePayload` and the JS command strings are removed, and
`BooksBridgeTests` is rewritten to test command handling and state decoding that remain. `failure` now means "no Metal / scene
could not start", and still drops the screen to the Classic shelf.

### Rendering decisions

- World units, handedness (Y up), and camera parameters are the Three.js ones (vertical FOV 32, near .05, far 40). The
  `setViewOffset` content shift for the HUD insets is reproduced as an off-centre projection so framing is identical.
- Materials use SceneKit's physically based model: albedo, roughness, metalness, clear coat. Bump maps are converted once to
  normal maps. Gold foil keeps its metal mask.
- Lighting reproduces the rig: hemisphere (as ambient plus ground bounce), directional sun with the same shadow frustum and
  map size, the dark-mode spot "lamp" and emissive bulb, and an image-based environment standing in for Three's
  `RoomEnvironment` at the same intensities (built procedurally once).
- Tone: Three uses Khronos PBR Neutral with exposure .92 (light) / 1.1 (dark). SceneKit has no equal, so a small full-screen
  `SCNTechnique` pass implements the Neutral curve and exposure.
- Page leaves are two meshes (front, back) sharing one dynamic position/normal source, 29x9 vertices, normals recomputed on
  the CPU only for leaves whose progress/peek changed (same dirty rules as JS).
- The ruler band dim is a fragment shader modifier on leaf materials (same `uBand` maths). The lens is a shader modifier on
  the glass disc, fed a 2048-wide fully revealed page bitmap (same as JS).
- Page bitmaps are 1280x1820 `CGImage`s drawn off the main thread, kept for pages within 6 of the current one, assigned for
  within 3 (same windows as `_ensureTextures`), with mipmaps and anisotropy 8.
- Rendering is on demand: the view runs only while a tween is active or the scene is dirty (same as the `dirty` flag), and
  pauses when the app is inactive. Quality "Battery saver" = no shadows, lower pixel scale (1.25 vs device scale up to 2.5).
- Fonts: Amiri 400 and 700, the same four files the web build inlines (`@fontsource/amiri@5.1.0`: Arabic and Latin subsets;
  they live in `node_modules`, not in the repo, so they are installed with npm and converted woff2 to TTF with fonttools,
  lossless, then committed under `Resources/Fonts`). Registered at launch. The font stack keeps JS's fallback order
  (Amiri, Geeza Pro, Georgia) as a CoreText cascade list. Layout uses the same sizes and the same line-wrapping algorithm
  as JS, computing every word and fragment position itself (only glyph shaping inside one fragment is left to CoreText),
  including the thin stroke added over Amiri text. A unit test checks that every character in the bundled lessons has a
  glyph in the Amiri subsets (so no silent fallback changes widths).
- Touch: one `UIView` subclass over the `SCNView` handles touches with the JS decision tree ported literally: 8 pt move
  threshold, press on the outer 22% of a page to grab a leaf, horizontal-vs-vertical ratio 1.1, release completes a turn at
  p > .42 forward / p < .58 back or velocity beyond 0.9, lens held 0.38 above a finger, landscape pan limits. Picking uses
  `SCNView.hitTest` and ray/plane maths shared with the shader code.

### Parity method (how "pixel perfect" is checked without Xcode)

1. **Golden numbers from the JS.** A Node script (runs here, `three` is already a dev dependency) writes fixtures:
   leaf vertex positions for sample (p, peek, grabZ) values, block vertices, `_frameRect` camera poses for several
   screen sizes and insets, `paginate` splits using a fixed measure function, tween values. Swift unit tests assert equality
   within 1e-5. This makes geometry, framing, pagination and animation curves exact rather than eyeballed.
2. **Screenshots at fixed waypoints.** One new UI test drives the real HUD (ids above) and attaches a screenshot at each
   waypoint: menu portrait and landscape (light, dark), cover just opened, page 1 and page 2, mid-menu hover is skipped (not
   deterministic), lens, ruler, bookmark, Focus, Memorize hidden and revealed, a Reduce-Motion run. It uses only the HUD, so
   it runs against both the old web scene (baseline, from the current `main`) and the new scene. CI uploads both sets, a
   script prints a per-waypoint difference number, and the images are pulled and looked at to tune lighting.
2b. **Readability measurements** from the same waypoint screenshots (crop the text area of the page): contrast ratio between ink
   and paper pixels, average page luminance, and edge sharpness (variance of the Laplacian of the crop). Each must be equal to
   or better than the web baseline at the same waypoint, light and dark, portrait and landscape, all four text sizes, with
   Memorize off and on. A regression fails the comparison script, not just the eye test.
3. **Page breaks.** The fake-measure fixtures prove the algorithm, not CoreText's widths. The waypoint test also records the
   `pageIndicator` text (page count) for every text size in both scenes; the page counts must match, and any difference is
   investigated as a measuring problem before it is blamed on lighting. Individual line breaks may differ by a word where a
   CoreText advance differs from the browser's by a fraction of a pixel; that is accepted, page ids are unaffected.
4. **Proof the native scene ran.** The scene host carries its own accessibility id (`booksSceneNative`; the Classic fallback
   keeps `booksFallback`). The waypoint test and a smoke test fail if the fallback shows when the native scene is selected,
   so green tests cannot mean "the scene never started".
5. Existing unit and UI tests keep running.

### Delivery order (each step ends on a CI run)

0. Feasibility spike (throwaway, own CI run): a bare `SCNView` with a lit box, a shadow and a shader modifier, screenshotted in
   the macos-26 simulator. If SceneKit does not render there, stop and bring the owner a decision (screenshots would then
   come from a device or another route) before any other work.
1. Fixtures from JS; `Tweens`, `BookNode` maths, `PageLayout`/pagination with their tests.
2. Fonts (with the glyph-coverage test), `PageRenderer`, `CoverArt` (bitmaps visible in a debug waypoint).
3. Scene shell: `SCNView` host, desk, books closed, camera, menu, tap to open, cover opening.
4. Reading: leaves, page turns (buttons, then drag), textures window, resume, text size relayout.
5. Tools, Focus, Memorize, definitions, bookmark, landscape pan, and Free view (the `FreeView` maths and its tests can start
   at step 1, the gesture layer joins here).
6. Lighting, shadows, environment, tone pass; tune against the baseline screenshots; dark mode lamp.
7. Make the native scene the default (the engine switch below flips); update tests and docs. The web scene is removed only
   after the owner accepts (see Cleanup).

Pull a test is built from step 3 on and grows with each step: the recorder, caption banner, finger ring, runner and log first
(over the closed-book menu and cover opening), then each later step adds its actions, so every step's CI run already ends with
footage to review. The Settings button and result screen ship with the first version.

8. Enhancement tier (below), one item per CI run with before/after screenshots, readability measurements rerun each time.
9. Performance pass on a real frame budget (below), then the cleanup.

Engine switch while both exist: from step 3 on, Books Settings has a temporary "Scene engine" picker (Native / Original),
saved next to the other Books preferences, so the owner can compare on a device (launch arguments do not work in an installed
build). It defaults to Original until step 7, then to Native, and is deleted in Cleanup. The screenshot test picks the engine
through a debug launch argument. The `scene` CI job stays until Cleanup.

### Pull a test (recorded self-test)

**What the person sees.** Settings > Books > Books Settings has a "Test" section with a button named **Pull a test**. Tapping it
opens a short explanation (it takes over the screen for about 3 minutes, records only this app's screen with no microphone, and
needs the system's screen-recording permission the first time), then a Start button. The run covers the Books feature from the
tab opening to leaving it, with a banner at the top naming each action ("14 of 52 · Turn page: next") and a ring showing where
the scripted finger is touching. A Stop button is always on screen. At the end a result screen lists every action with a pass or
fail mark and offers **Share video and log**, which opens the share sheet with the MP4 and the JSON log so they can be sent
straight into the chat for review (or saved to Files). Tapping Pull a test again re-runs it.

**What it does, in the order a regular user would.** Each action drives the same code a finger does:
1. Books tab opens, desk is shown and left alone for two seconds (idle look, lamp, light); light and dark appearance.
2. Tap History: the book lifts, the camera comes down, the cover swings open; wait for reading. Tap Geography: "No lessons yet".
3. Read page 1 (dwell), tap next several times, tap previous, jump far ahead and back (multi-leaf flip), drag a leaf from its
   edge and release past halfway, drag and let go early (it must fall back), flick quickly, swipe the page body.
4. Tap a highlighted term (definition card opens), dismiss it. Turn Memorize on, step through its three levels, tap a blot to
   reveal one answer, reveal the whole page, hide again.
5. Pick up the magnifying glass, drag it across text and across the spine to the other page, put it away. Same for the ruler
   and for the bookmark (place, turn away and come back, remove).
6. Focus Mode in and out with a tool in hand; the four text sizes with a page re-layout each.
7. Free view: pinch out, pinch in, two-finger drag, one-finger pan while zoomed, double-tap reset, the recenter button.
8. Rotate to landscape: the half-page framing, the vertical pan, a turn, back to portrait (the original orientation is restored).
9. Quality Standard then Battery saver (original value restored), then Back to the desk, Read as text and return, leave the tab.

**How the gestures are real.** The touch layer takes plain points (down, move, up, with times) from UIKit and feeds one decision
tree; the tour feeds that same entry point with scripted points on realistic paths and speeds, not the high-level commands. HUD
buttons are driven through the same handlers the buttons call. So a bug in hit testing, thresholds or page turning shows in
the footage exactly as it would for a person. UIKit's own recognizers (the pinch) are fed by a thin scripted source that calls
the same recognizer callbacks.

**Footage.** On device: `RPScreenRecorder` (in-app capture, microphone off) writes H.264 through `AVAssetWriter`, scaled to
about 780 px wide with the bitrate chosen so the file stays under about 40 MB; the captions and finger ring are part of the
app's own view tree, so they are in the video. The simulator has no ReplayKit, so there the CI job records the simulator with
`simctl recordVideo` while the same in-app tour runs (launch argument), and the MP4 and log are published to the
`ci-recordings` branch automatically after a push or manual dispatch (replaces `BooksTourUITests`). Claude reads either the shared
files or the CI ones: frames are extracted at the log's timestamps with ffmpeg (available in the working sandbox) and
inspected, so each action is checked at its start, middle and end.

**The log** (`tour-<date>.json`, written next to the video): per action the id, caption, video-relative start and end times, the
expected scene state and the observed one (page, mode, tool, focus, recall, zoom, canNext/canPrev), a pass or fail result with a
reason, frame statistics (average and worst frame time, number of frames over 1.5x the display interval), and resident memory at
the end; plus device model, iOS version, display refresh rate, scene engine, quality, appearance, and any warnings the scene
logged (a texture that failed to draw, a missing glyph, a tween that never finished). Expectations are checked in code with a
timeout, and a failing action does not stop the run, so one footage shows every problem.

**Safety for the person's data.** The tour reads and writes reading progress and bookmarks like a person would, so it first
copies `TextbookState` (and the Books preferences it will change: text size, level, quality, free view, engine) and restores
them at the end, on Stop, on backgrounding, and, if the app is killed mid-run, at next launch from a saved copy. Nothing is
sent anywhere by the app: sharing is the person's own share sheet. Not available (button disabled with a one-line reason)
when the scene engine is Original, when the scene could not start, or when screen recording is restricted by the device (the tour
can still run without video and produce just the log, which the person can choose).

**Tests.** Unit: the script is valid (unique ids, every expectation reachable, restore list complete), the report encodes and
decodes, restore-after-abort puts preferences back, caption and ring positions. UI test in CI runs the tour in the simulator
with the recorder stubbed out and requires every action to pass, and the CI tour job produces the real footage as above.

### Free view (move, zoom out, zoom in)

A layer on top of the framed camera, not a replacement for it. The scripted framing (menu, cover, page, Focus, landscape
half-page) still decides the base pose and all its flights; the person's view is an offset applied after it: a zoom factor
and a pan, kept in `FreeView` (pure Swift, unit-tested; no SceneKit types).

- **Gestures.** Pinch zooms about the point between the fingers (that point on the desk/page stays under the fingers).
  Two-finger drag pans at any time. When zoomed in (above 1.05x), a one-finger drag on the page also pans, except a drag that
  starts on the outer 22% edge of a page (which still grabs the leaf to turn it) and except while the lens or ruler is held.
  Swipe-to-turn from the page body is therefore off while zoomed in; the arrows, edge drag and VoiceOver actions still turn
  pages. At 1x or below everything behaves as in the web scene (including the landscape one-finger vertical pan, which
  becomes the same pan with the same limits). Tapping terms, recall blots, books and tools works at any zoom because picking
  is done on rays.
- **Range.** 0.55x (the whole desk or both pages with room around them) to 3x in the reading pose and 2.5x in the menu. A
  rubber-band resists past either limit and eases back. Pan is clamped so the book, or in reading the current page, can never
  be fully pushed off screen (at least 30% of it stays inside the area not covered by the controls).
- **Smoothness.** Targets move through a critically damped spring (about 0.18 s), so pinching and dragging feel direct but
  never jump; releasing a pan or a fast pinch continues with inertia (deceleration like a scroll view). Reduce Motion: no
  spring, no inertia, the view follows the fingers exactly.
- **Resetting.** A double tap on the page or desk body (not on a term, blot, book or tool) animates back to the framed pose. A
  small round "Recenter view" HUD button (`viewReset`) appears whenever the view is off its framed pose and goes away when it is
  reset. Closing a book, opening another, and changing text size reset the view. Turning a page keeps the zoom but re-centres
  the pan on the new page, so a zoomed-in reader keeps reading at the same size.
- **Interaction with the rest.** The camera inset shift for the controls is applied before the offset, so "a little bit down"
  is fixable by one drag. Focus Mode, tools and Memorize work unchanged; the lens and ruler follow the finger in world space
  and ignore the zoom. The `-1..2` text size and the camera tween code do not know about the offset.
- **Readability.** The current page's high-density bitmap is chosen by on-screen size, not a fixed 1.5x: up to 2.5x
  (2560x3640) when zoomed in, capped by the memory budget, redrawn once the zoom settles and swapped in without a pop; texture
  filtering is trilinear with maximum anisotropy so zooming out stays clean. Effects that blur (depth of field) are off whenever
  the person has moved the view.
- **Option.** Books Settings, View section: "Free view" switch, on by default, saved as `TextbookState.preferences.freeView`
  (tolerant decoder; a missing value means on). Off disables the gestures and hides the recenter button; the framed camera is
  then exactly the web scene's. Sent to the scene as `SceneCommand.setFreeView(Bool)`; state exposes `viewOffset` (moved or
  not) so the HUD can show the recenter button.
- **Tests.** Unit tests for the maths: zoom clamp and rubber band, focal-point invariance (the world point under the pinch
  centre is the same before and after), pan clamp for several insets, inertia decay, reset. UI tests use the XCUITest `pinch` and
  `swipe` to zoom and pan, check `pageIndicator` is unchanged, `viewReset` appears and disappears, and add zoomed-in and
  zoomed-out waypoints to the screenshot set (with the readability measurements on the zoomed-in crop).

### Readability (applies to parity and to every enhancement)

- **Sharpness.** A page bitmap is drawn at 1280x1820 for leaves in the window (as in the web scene). The page being read is
  additionally redrawn at higher density (1.5x, 1920x2730) as soon as the camera settles on it, and again in Focus Mode and under
  the lens, then swapped in with no pop. Mipmaps stay on and anisotropic filtering goes to the device maximum (16 where
  available, the web scene used 8). Bitmaps are drawn with subpixel positioning and the same hairline thickening as the web scene.
- **Gutter.** Text sits inside the zone where resting leaves dip into the binding (`GUTTER_DIP`). While a page is being read
  the dip over the text area is eased to 40% (0% in Focus Mode) and returns when the leaf turns, so lines near the spine do not
  bend away. Parity pose without reading (menu, opening) keeps the original curve.
- **Light on the page.** Reading poses add a soft fill that evens the page and keeps cast shadows (the other page, the HUD
  band, the turning leaf) from darkening text. Paper keeps roughness .92 so there is no specular glare on the text. In dark mode
  the lamp lights the page and the desk falls off around it; a page is never darker than the measured baseline.
- **Contrast and tone.** Ink and paper colours stay the web values (already above 7:1). The tone pass must not lift blacks or
  crush the paper: checked by the contrast measurement above.
- **Depth effects off the text.** Depth of field, bloom and particles never apply to the page being read (see below).
- **Size and layout.** The four text sizes and the page-count rule stay. Framing keeps the page as large as in the web scene in
  portrait, and in landscape the half-width framing with vertical pan, now with inertia and edge resistance instead of a hard stop.
- **Accessibility.** The scene host exposes the current page's plain text and title to VoiceOver as one element (the web scene hid
  the whole scene), with the existing HUD buttons unchanged. "Read as text" remains.

### Enhancement tier (after parity is accepted)

Every item below is staged separately, can be turned off, and is dropped or reduced if it costs readability or frame time.
Reduce Motion removes anything that moves by itself (sway, drift, flicker, dust). "Battery saver" removes depth of field,
ambient occlusion, bloom, particles and motion sway, as it already removes shadows.

- **Light and depth.** Contact shadows under books and tools via ambient occlusion; in the menu a gentle depth of field that
  falls away to nothing when a book opens or reading starts; in dark mode a soft bloom on the bulb and a warm cone of lamp
  light with a very slow, subtle intensity drift.
- **Atmosphere.** A few dust motes drifting through the sun beam (light) or the lamp cone (dark); they never cross the page
  being read and fade out when reading starts.
- **Materials.** Leather grain and cloth weave as real normal maps, gold foil with a proper reflective response, gilded page
  edges for the History book, wood grain with fine scratches on the desk, a slightly irregular felt nap. All in the existing
  palette.
- **Paper behaviour.** The turning leaf casts a moving soft shadow on the page below it; resting pages show a very slight
  edge curl at the fore edge; the ribbon has a few verlet segments so it sways when the book moves and settles.
- **Motion feel.** A subtle camera sway from device motion in the menu and while the book is closed (off while reading, off
  with Reduce Motion), springy settle on tool landings, a light haptic when a leaf lands. No sound effects: they need audio
  assets that cannot be auditioned here, so they stay out unless the owner asks.
- **Desk detail.** A few extra small props in the Palabra palette (for example an eraser and a paper clip) and tidier,
  more believable placement, shown to the owner as screenshots before they stay.

Frame budget: 16.6 ms at 60 fps on an iPhone 12 class device with everything on, 8.3 ms headroom target on 120 Hz devices
(ProMotion), no more than 150 MB of scene and bitmap memory, nothing allocated per frame in the page-turn path. The scene
profile is measured in CI with a `measure` block over a scripted page turn, and checked on the owner's device.

### Cleanup when approved as done

Delete `web/books3d`, `Resources/Books3D`, the `scene` CI job and the bundle-current check, the WKWebView host and bridge
code, `BooksTourUITests` (replaced by the in-app tour); keep the Classic shelf and Pull a test. Rewrite the Books sections of `AGENTS.md` (rules 1 to 3 now point at the Swift files; rule 3's
"new block type" list becomes `LessonModels.swift`, `scripts/validate-lessons.py`, `PageLayout`/`PageRenderer`) and
`docs/features/books.md`. Keep the old scene until the owner has seen the new one and accepts it.

## Decisions by the owner

- Rebuild the Books 3D landscape entirely native; SceneKit; aim for pixel parity and correct behaviour.

## Calls I made (change any of them)

- Keep all UI-facing names, ids and the `BooksSceneModel` API so the HUD, tests and settings do not change.
- Parity is "exact numbers for geometry/layout/animation, visually matched shading", checked by golden fixtures plus CI
  screenshots, not claimed beyond that.
- Bump and tone: bump maps become normal maps; tone mapping is a custom Neutral pass.
- Old web scene stays in the repo, selectable through a temporary Settings picker (see "Engine switch"), until the owner
  accepts the new one; then it and the picker are deleted. The picker is a migration aid, not a feature.
- Amiri comes from the npm package the web build already uses (subsets, converted to TTF); the repo has no woff2 files.
- Page breaks need the same page count as the web scene, not identical line breaks everywhere.
- The scene host exposes `booksSceneNative` so tests can prove the native scene (not the fallback) was running.
- Step 0 is a rendering feasibility spike; SceneKit on the CI simulator is unconfirmed.
- Owner asked for "as immersive and detailed" plus essential readability: parity is built first, the enhancements follow as a
  separate tier, and readability has measurable gates. Where immersion and readability conflict, readability wins.
- Higher-density redraw of the current page, eased gutter dip while reading, VoiceOver page text, pan inertia and Free view
  (pinch, drag, recenter, setting) are deliberate differences from the web scene; they are the only changes allowed before
  parity sign-off.
- Free view is on by default, with the Settings switch as the option you asked for; the zoom range, the one-finger pan rule while
  zoomed in, double-tap to reset and the recenter button are my choices.
- Pull a test lives in Books Settings (the Books feature's own settings), not the top-level Settings list; it is a normal
  button in release builds (the owner uses sideloaded builds), disabled with a reason when it cannot run. Captured with
  ReplayKit on device and `simctl recordVideo` in CI; sent through the share sheet because nothing in the app uploads anywhere
  and no token is ever embedded in the app. The owner passes the files to Claude in chat; CI footage needs no step by the owner.
- The tour walks the native scene only (the Original engine stays checked by the screenshot waypoints).
- While zoomed in, swiping the page body does not turn pages (it pans); edge drag and arrows still turn. Say if you would
  rather keep swipe-to-turn and use only two fingers to pan.
- No sound effects (cannot be auditioned here); haptics only.
- Work is verified on a separate branch (`native-books`) pushed with the provided token and run through CI by manual
  dispatch; `main` is not touched and nothing is merged. The result is delivered as a zip.
- Rounded boxes use `SCNBox` chamfer, cutouts use `SCNShape`, lathe/half-pipe/arc-torus use small custom geometry builders.

## Left to the builder

File-level breakdown inside `Native/`, exact shader code, the procedural environment map, per-material tuning, memory
budget for page bitmaps, the screenshot comparison script, and how to split the CI waypoints across jobs.

## Risks

- Scope creep: the enhancement tier is large. It is gated behind parity sign-off and delivered one item at a time so any item
  can be cut.
- Depth effects, bloom and particles are the most likely to hurt either battery or text clarity; each has an off switch and a
  measurement before it stays.
- Compile-blind Swift against SceneKit and CoreText APIs: expect several CI round trips per step.
- SceneKit shader modifiers and `SCNTechnique` are the least forgiving parts; the lens and tone pass are the first to verify.
- SceneKit shadow softness and Three's `PCFSoftShadowMap` will not match exactly; tuned by eye from screenshots.
- Simulator rendering (software GL in the old scene, Metal in the new) may differ slightly from a device.
