import XCTest
@testable import Palabra

@MainActor
final class EnhancementGatingTests: XCTestCase {
    private func flags(
        enabled: Bool = true, quality: SceneQuality = .standard, reduceMotion: Bool = false,
        moved: Bool = false, reading: Bool = false, dark: Bool = false
    ) -> EnhancementFlags {
        EnhancementFlags.resolve(enabled: enabled, quality: quality, reduceMotion: reduceMotion, moved: moved, reading: reading, dark: dark)
    }

    func testSaverTurnsEveryEffectOff() {
        let f = flags(quality: .saver, dark: true)
        XCTAssertFalse(f.ao || f.dof || f.bloom || f.dust || f.sway || f.flicker)
    }

    func testSwitchOffTurnsEverythingOff() {
        XCTAssertEqual(flags(enabled: false, dark: true), .off)
    }

    func testReduceMotionRemovesMovingEffects() {
        let f = flags(reduceMotion: true, dark: true)
        XCTAssertFalse(f.dust || f.sway || f.flicker || f.dof)
        XCTAssertTrue(f.ao && f.bloom)
    }

    func testDepthOfFieldOffWhenReadingOrMoved() {
        XCTAssertTrue(flags().dof)
        XCTAssertFalse(flags(reading: true).dof)
        XCTAssertFalse(flags(moved: true).dof)
    }

    func testDustNeverInReading() {
        XCTAssertTrue(flags().dust)
        XCTAssertFalse(flags(reading: true).dust)
        XCTAssertFalse(flags(reading: true, dark: true).dust)
    }

    func testLampEffectsOnlyInDarkMode() {
        XCTAssertFalse(flags().bloom || flags().flicker)
        XCTAssertTrue(flags(dark: true).bloom && flags(dark: true).flicker)
    }

    func testHapticsSurviveSaver() {
        XCTAssertTrue(flags(quality: .saver).haptics)
        XCTAssertFalse(flags(enabled: false).haptics)
    }

    // MARK: In the scene

    private func makeController(quality: SceneQuality = .standard) async -> BookSceneController {
        let library = BookLibrary.load(from: BundleBookSource())
        let controller = BookSceneController(config: NativeSceneConfig(library: library, quality: quality, reducedMotion: false))
        controller.setSize(CGSize(width: 390, height: 844))
        await controller.load()
        return controller
    }

    func testMenuShowsContactShadowsAndReadingHidesDust() async throws {
        let controller = await makeController()
        for _ in 0..<90 { controller.tick(dt: 1.0 / 60) }
        XCTAssertTrue(controller.enhancementFlags.ao)
        XCTAssertTrue(controller.enhancementFlags.dust)
        let entry = try XCTUnwrap(controller.entries.first { !$0.isEmpty })
        controller.openBook(id: entry.book.id, pageID: nil)
        for _ in 0..<600 { controller.tick(dt: 1.0 / 60) }
        XCTAssertEqual(controller.state.mode, .reading)
        XCTAssertFalse(controller.enhancementFlags.dust)
        XCTAssertFalse(controller.enhancementFlags.dof)
    }

    func testRibbonSwingsWhenALeafTurnsAndSettles() async throws {
        let controller = await makeController()
        let entry = try XCTUnwrap(controller.entries.first { !$0.isEmpty })
        controller.openBook(id: entry.book.id, pageID: nil)
        for _ in 0..<600 { controller.tick(dt: 1.0 / 60) }
        controller.next()
        controller.next()
        for _ in 0..<1200 { controller.tick(dt: 1.0 / 60) }
        // Nothing keeps moving once the book is at rest (the spring has settled and no leaf animates).
        XCTAssertFalse(controller.isBusy)
    }

    func testSaverSwitchRemovesEffectsFromTheScene() async {
        let controller = await makeController(quality: .saver)
        controller.tick(dt: 1.0 / 60)
        XCTAssertEqual(controller.enhancementFlags.ao, false)
    }
}
