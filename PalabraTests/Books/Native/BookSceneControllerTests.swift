import SceneKit
import XCTest
@testable import Palabra

/// Headless checks of the native desk: no SCNView, so no GPU is needed.
@MainActor
final class BookSceneControllerTests: XCTestCase {
    private func makeController() async -> (BookSceneController, Recorder) {
        let library = BookLibrary.load(from: BundleBookSource())
        let controller = BookSceneController(config: NativeSceneConfig(library: library, reducedMotion: true))
        controller.setSize(CGSize(width: 390, height: 844))
        let recorder = Recorder()
        controller.sink = { recorder.messages.append($0) }
        await controller.load()
        return (controller, recorder)
    }

    final class Recorder {
        var messages: [SceneMessage] = []
        var lastState: SceneState? {
            for message in messages.reversed() { if case .state(let s) = message { return s } }
            return nil
        }
        var visits: [String] {
            messages.compactMap { if case .visit(_, let id) = $0 { return id } else { return nil } }
        }
        var gotReady: Bool { messages.contains { if case .ready = $0 { return true } else { return false } } }
    }

    /// Runs the tween clock until nothing animates (reduced motion makes every animation a few frames).
    private func settle(_ controller: BookSceneController) {
        for _ in 0..<600 where controller.tweens.isActive { controller.tick(dt: 0.05) }
    }

    func testLoadPostsReadyAndListsBooks() async {
        let (controller, recorder) = await makeController()
        XCTAssertTrue(recorder.gotReady)
        XCTAssertEqual(recorder.lastState?.mode, .menu)
        XCTAssertEqual(recorder.lastState?.books.count, controller.entries.count)
        XCTAssertFalse(controller.entries.isEmpty)
    }

    func testOpenReadTurnAndClose() async throws {
        let (controller, recorder) = await makeController()
        let entry = try XCTUnwrap(controller.entries.first { !$0.isEmpty })
        controller.openBook(id: entry.book.id, pageID: nil)
        XCTAssertEqual(controller.state.mode, .opening)
        settle(controller)
        XCTAssertEqual(controller.state.mode, .reading)
        let start = try XCTUnwrap(recorder.lastState)
        XCTAssertEqual(start.page, 1)
        XCTAssertTrue(start.canNext)
        XCTAssertFalse(start.canPrev)

        // Page index 1 is the back of leaf 0: turning to it flips leaf 0 onto the left stack.
        controller.next()
        settle(controller)
        XCTAssertEqual(recorder.lastState?.page, 2)
        XCTAssertTrue(recorder.lastState?.canPrev ?? false)
        XCTAssertEqual(entry.node.leafProgress(0), 1, accuracy: 1e-9)
        // Index 2 is the front of leaf 1 (right stack): leaf 1 stays down.
        controller.next()
        settle(controller)
        XCTAssertEqual(entry.node.leafProgress(0), 1, accuracy: 1e-9)
        XCTAssertEqual(entry.node.leafProgress(1), 0, accuracy: 1e-9)
        controller.next()
        settle(controller)
        XCTAssertEqual(entry.node.leafProgress(1), 1, accuracy: 1e-9)

        controller.previous()
        controller.previous()
        controller.previous()
        settle(controller)
        XCTAssertEqual(recorder.lastState?.page, 1)
        XCTAssertEqual(entry.node.leafProgress(0), 0, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(recorder.visits.count, 4)

        controller.closeBook()
        settle(controller)
        XCTAssertEqual(controller.state.mode, .menu)
        XCTAssertNil(recorder.lastState?.bookID)
    }

    func testOpeningThenCloseRequestClosesAfterOpen() async throws {
        let (controller, _) = await makeController()
        let entry = try XCTUnwrap(controller.entries.first { !$0.isEmpty })
        controller.openBook(id: entry.book.id, pageID: nil)
        controller.closeBook()
        settle(controller)
        XCTAssertEqual(controller.state.mode, .menu)
    }

    func testRecallTogglesAndLevelReportsPreference() async throws {
        let (controller, recorder) = await makeController()
        let entry = try XCTUnwrap(controller.entries.first { !$0.isEmpty })
        controller.openBook(id: entry.book.id, pageID: nil)
        settle(controller)
        controller.setRecall(true)
        XCTAssertTrue(recorder.lastState?.recall ?? false)
        controller.setLevel(.intensive)
        XCTAssertEqual(recorder.lastState?.level, .intensive)
        let preference = recorder.messages.contains {
            if case .preference(let level, _) = $0 { return level == .intensive } else { return false }
        }
        XCTAssertTrue(preference)
    }

    func testCameraProjectionMatchesPerspectiveWithoutShift() {
        let m = CameraRig.projection(fovDegrees: 32, size: CGSize(width: 400, height: 800), shiftY: 0)
        let f = 1 / tan(32.0 * .pi / 360)
        XCTAssertEqual(Double(m.m22), f, accuracy: 1e-5)
        XCTAssertEqual(Double(m.m11), f / 0.5, accuracy: 1e-5)
        XCTAssertEqual(m.m32, 0, accuracy: 1e-6)
        XCTAssertEqual(m.m34, -1)
    }

    func testPageImagesExistForOpenWindow() async throws {
        let (controller, _) = await makeController()
        let entry = try XCTUnwrap(controller.entries.first { !$0.isEmpty })
        controller.openBook(id: entry.book.id, pageID: nil)
        settle(controller)
        XCTAssertNotNil(controller.pageImage(entry, 0))
    }

    // MARK: Input

    private final class FakePicker: ScenePicker {
        var book: String?
        var page: PageHit?
        func bookID(at point: CGPoint) -> String? { book }
        func pageHit(at point: CGPoint) -> PageHit? { page }
        var tool: String?
        func toolName(at point: CGPoint) -> String? { tool }
    }

    /// The screen point (middle row) whose view ray meets the page plane at world x.
    private func screenPoint(_ controller: BookSceneController, worldX: Double, y: Double) -> CGPoint {
        var lo = 0.0, hi = Double(controller.camera.size.width)
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            let hit = controller.camera.planePoint(through: CGPoint(x: mid, y: Double(controller.camera.size.height) / 2), y: y)
            if (hit?.x ?? 0) < worldX { lo = mid } else { hi = mid }
        }
        return CGPoint(x: (lo + hi) / 2, y: Double(controller.camera.size.height) / 2)
    }

    func testTapOnBookInMenuOpensIt() async throws {
        let (controller, _) = await makeController()
        let entry = try XCTUnwrap(controller.entries.first { !$0.isEmpty })
        let picker = FakePicker()
        picker.book = entry.book.id
        controller.picker = picker
        let p = CGPoint(x: 100, y: 400)
        controller.pointerDown(p, touch: true, time: 0)
        controller.pointerUp(p, time: 0.1)
        XCTAssertEqual(controller.state.mode, .opening)
        XCTAssertEqual(controller.state.bookID, entry.book.id)
    }

    func testDraggingTheOuterEdgeTurnsThePage() async throws {
        let (controller, recorder) = await makeController()
        let entry = try XCTUnwrap(controller.entries.first { !$0.isEmpty && !$0.book.isRightToLeft })
        controller.openBook(id: entry.book.id, pageID: nil)
        settle(controller)
        let picker = FakePicker()
        controller.picker = picker
        let surface = entry.node.surfaceY(side: 1)
        picker.page = PageHit(pageIndex: 0, leaf: 0, front: true, px: 1100, py: 900)
        let from = screenPoint(controller, worldX: 0.9, y: surface)
        let to = screenPoint(controller, worldX: -0.2, y: surface)
        controller.pointerDown(from, touch: true, time: 0)
        controller.pointerMove(CGPoint(x: (from.x + to.x) / 2, y: from.y), time: 0.1)
        XCTAssertGreaterThan(entry.node.leafProgress(0), 0)
        controller.pointerMove(to, time: 0.2)
        controller.pointerUp(to, time: 0.25)
        settle(controller)
        XCTAssertEqual(entry.node.leafProgress(0), 1, accuracy: 1e-9)
        XCTAssertEqual(recorder.lastState?.page, 2)
    }

    func testShortDragSettlesBack() async throws {
        let (controller, recorder) = await makeController()
        let entry = try XCTUnwrap(controller.entries.first { !$0.isEmpty && !$0.book.isRightToLeft })
        controller.openBook(id: entry.book.id, pageID: nil)
        settle(controller)
        let picker = FakePicker()
        controller.picker = picker
        let surface = entry.node.surfaceY(side: 1)
        picker.page = PageHit(pageIndex: 0, leaf: 0, front: true, px: 1100, py: 900)
        let from = screenPoint(controller, worldX: 0.9, y: surface)
        let to = screenPoint(controller, worldX: 0.7, y: surface)
        controller.pointerDown(from, touch: true, time: 0)
        controller.pointerMove(to, time: 0.5)
        controller.pointerUp(to, time: 0.6)
        settle(controller)
        XCTAssertEqual(entry.node.leafProgress(0), 0, accuracy: 1e-9)
        XCTAssertEqual(recorder.lastState?.page, 1)
    }

    func testRayThroughViewCentreHitsLookPoint() async {
        let (controller, _) = await makeController()
        controller.camera.setShift(0)
        controller.camera.setPose(CameraPose(position: SIMD3(0, 5, 5), look: .zero))
        let centre = CGPoint(x: controller.camera.size.width / 2, y: controller.camera.size.height / 2)
        let p = controller.camera.planePoint(through: centre, y: 0)
        XCTAssertEqual(p?.x ?? 9, 0, accuracy: 1e-9)
        XCTAssertEqual(p?.z ?? 9, 0, accuracy: 1e-9)
    }

    // MARK: Free view

    func testPinchMovesTheViewAndDoubleTapResets() async throws {
        let (controller, recorder) = await makeController()
        let centre = CGPoint(x: 195, y: 422)
        controller.pinchChanged(scale: 1.5, at: centre)
        controller.pinchEnded(at: centre)
        XCTAssertEqual(controller.free.zoom, 1.5, accuracy: 1e-9)
        XCTAssertTrue(recorder.lastState?.viewMoved ?? false)
        for _ in 0..<5 { controller.tick(dt: 0.05) }
        XCTAssertEqual(controller.camera.zoom, 1.5, accuracy: 1e-9) // reduced motion: no spring
        controller.doubleTapped(at: centre)
        for _ in 0..<5 { controller.tick(dt: 0.05) }
        XCTAssertEqual(controller.camera.zoom, 1, accuracy: 1e-9)
        XCTAssertFalse(recorder.lastState?.viewMoved ?? true)
    }

    func testZoomIsLimited() async {
        let (controller, _) = await makeController()
        let centre = CGPoint(x: 195, y: 422)
        controller.pinchChanged(scale: 20, at: centre)
        controller.pinchEnded(at: centre)
        XCTAssertEqual(controller.free.zoom, ZoomLimits.menu.maxZoom, accuracy: 1e-9)
    }

    func testFreeViewOffIgnoresGestures() async {
        let (controller, _) = await makeController()
        controller.setFreeViewEnabled(false)
        controller.pinchChanged(scale: 2, at: CGPoint(x: 100, y: 100))
        XCTAssertEqual(controller.free.zoom, 1, accuracy: 1e-9)
    }

    // MARK: Tools

    func testLensRulerAndBookmarkToggle() async throws {
        let (controller, recorder) = await makeController()
        let entry = try XCTUnwrap(controller.entries.first { !$0.isEmpty })
        controller.openBook(id: entry.book.id, pageID: nil)
        settle(controller)
        controller.setTool("lens")
        XCTAssertEqual(recorder.lastState?.tool, "lens")
        controller.setTool("ruler") // swaps: the lens goes back, the ruler comes out
        XCTAssertEqual(recorder.lastState?.tool, "ruler")
        controller.setTool("ruler") // same tool again puts it away
        XCTAssertNil(recorder.lastState?.tool)
        controller.setTool("bookmark")
        XCTAssertNotNil(recorder.lastState?.bookmarkPageID)
        XCTAssertEqual(recorder.lastState?.bookmarkPageID, recorder.lastState?.basePageID)
        let posted = recorder.messages.contains { if case .bookmark = $0 { return true } else { return false } }
        XCTAssertTrue(posted)
        settle(controller)
        controller.closeBook()
        settle(controller)
        XCTAssertNil(recorder.lastState?.tool)
    }

    func testRulerFollowsFingerAndStaysOnPage() async throws {
        let (controller, _) = await makeController()
        let entry = try XCTUnwrap(controller.entries.first { !$0.isEmpty })
        controller.openBook(id: entry.book.id, pageID: nil)
        settle(controller)
        controller.setTool("ruler")
        settle(controller)
        controller.moveRuler(CGPoint(x: 195, y: 100))
        XCTAssertLessThan(abs(controller.rulerZ), BookDims.pageHeight / 2)
        let before = controller.rulerZ
        controller.moveRuler(CGPoint(x: 195, y: 700))
        XCTAssertNotEqual(controller.rulerZ, before)
    }

    func testLensWindowMovesTheTexture() async throws {
        let (controller, _) = await makeController()
        let entry = try XCTUnwrap(controller.entries.first { !$0.isEmpty })
        controller.openBook(id: entry.book.id, pageID: nil)
        settle(controller)
        controller.setTool("lens")
        settle(controller)
        controller.updateLens()
        XCTAssertTrue(controller.lens.glass.geometry?.firstMaterial?.diffuse.contentsTransform.m11 ?? 0 > 0)
    }
}
