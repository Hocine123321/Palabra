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

        controller.next()
        settle(controller)
        XCTAssertEqual(recorder.lastState?.page, 2)
        XCTAssertTrue(recorder.lastState?.canPrev ?? false)
        // Pages 1 and 2 are the two sides of leaf 0: after the turn page 2 is on the left stack, so leaf 0 is flipped.
        XCTAssertEqual(entry.node.leafProgress(0), 0, accuracy: 1e-9)
        controller.next()
        settle(controller)
        XCTAssertEqual(entry.node.leafProgress(0), 1, accuracy: 1e-9)

        controller.previous()
        controller.previous()
        settle(controller)
        XCTAssertEqual(recorder.lastState?.page, 1)
        XCTAssertGreaterThanOrEqual(recorder.visits.count, 3)

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
}
