import XCTest
@testable import Palabra

/// Runs the whole scripted tour against a controller with no renderer. Every step must pass.
@MainActor
final class TourScriptTests: XCTestCase {
    final class TestHost: TourHost {
        let controller: BookSceneController
        var state = SceneState()
        var clock = 0.0
        var picker: GeometryPicker?

        init(controller: BookSceneController) {
            self.controller = controller
            controller.sink = { [weak self] message in
                if case .state(let s) = message { self?.state = s }
            }
        }

        func send(_ command: SceneCommand) {
            // Commands arrive in order, as the model sends them; text-size changes finish within `wait`.
            Task { await controller.handle(command) }
        }

        func wait(_ seconds: Double) async {
            var left = seconds
            while left > 0 {
                let dt = min(1.0 / 60, left)
                controller.tick(dt: dt)
                clock += dt
                left -= dt
                if Int(clock * 60) % 6 == 0 { await Task.yield() }
            }
            await Task.yield()
        }
    }

    private func makeHost() async -> TestHost {
        let library = BookLibrary.load(from: BundleBookSource())
        let controller = BookSceneController(config: NativeSceneConfig(library: library, reducedMotion: true))
        controller.setSize(CGSize(width: 390, height: 844))
        let host = TestHost(controller: controller)
        host.picker = GeometryPicker(controller: controller)
        controller.picker = host.picker
        await controller.load()
        return host
    }

    func testScriptHasUniqueIdsAndRestoresWhatItChanges() {
        let steps = TourScript.steps(originals: .init(dark: false, level: .essential, textSize: .standard, quality: .standard))
        XCTAssertEqual(Set(steps.map(\.id)).count, steps.count)
        XCTAssertGreaterThan(steps.count, 40)
        let ids = Set(steps.map(\.id))
        for id in ["appearance-light", "memorize-off", "text-size-restore", "quality-restore", "close-book"] { XCTAssertTrue(ids.contains(id), id) }
    }

    func testWholeTourPassesHeadless() async throws {
        let host = await makeHost()
        let context = TourContext(host: host)
        let steps = TourScript.steps(originals: .init(dark: false, level: .essential, textSize: .standard, quality: .standard))
        var failures: [String] = []
        for step in steps {
            await step.run(context)
            var failure = step.check(context)
            if failure != nil {
                _ = await context.waitUntil(timeout: step.timeout) { step.check(context) == nil }
                failure = step.check(context)
            }
            if let failure { failures.append("\(step.id): \(failure) [\(context.observed())]") }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    func testReportRoundTrips() throws {
        let report = TourReport(
            date: Date(timeIntervalSince1970: 1_700_000_000), device: "iPhone", osVersion: "26", refreshRate: 60, engine: "native",
            quality: "standard", appearance: "light", recorded: false,
            steps: [TourStepResult(id: "a", caption: "A", start: 0, end: 1, expected: "x", observed: "y", passed: false, reason: "r", frameStats: TourFrameStats(frames: 3, averageMs: 16, worstMs: 20, slowFrames: 0))],
            warnings: ["w"], residentMemoryMB: 120
        )
        let back = try TourReport.decode(try report.encoded())
        XCTAssertEqual(back, report)
        XCTAssertFalse(back.allPassed)
        XCTAssertEqual(back.failedSteps.count, 1)
    }

    func testSafetyRestoresASavedCopy() {
        let defaults = UserDefaults(suiteName: "tour-\(UUID().uuidString)")!
        let shelf = BookShelf.inMemory()
        var original = shelf.state
        original.preferences.textSize = .largest
        TourSafety.save(original, defaults: defaults)
        shelf.preferences.textSize = .smaller
        XCTAssertTrue(TourSafety.restoreIfNeeded(into: shelf, defaults: defaults))
        XCTAssertEqual(shelf.preferences.textSize, .largest)
        XCTAssertFalse(TourSafety.restoreIfNeeded(into: shelf, defaults: defaults))
    }

    func testPointOnPath() {
        let path = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)]
        XCTAssertEqual(TourContext.point(on: path, at: 0.5), CGPoint(x: 10, y: 0))
        XCTAssertEqual(TourContext.point(on: path, at: 0.75), CGPoint(x: 10, y: 5))
        XCTAssertEqual(TourContext.point(on: path, at: 1), CGPoint(x: 10, y: 10))
    }

    func testUnavailableReasons() {
        var p = ReaderPreferences()
        XCTAssertNotNil(TourRunner.unavailableReason(preferences: p))
        p.sceneEngine = .native
        XCTAssertNil(TourRunner.unavailableReason(preferences: p))
        p.viewStyle = .classic
        XCTAssertNotNil(TourRunner.unavailableReason(preferences: p))
    }
}
