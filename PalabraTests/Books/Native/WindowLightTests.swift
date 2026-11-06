import SceneKit
import XCTest
@testable import Palabra

@MainActor
final class WindowLightTests: XCTestCase {
    func testPanesFillTheWindowLeavingRoomForTheBars() {
        let layout = WindowLight.Layout()
        let panes = layout.panes
        XCTAssertEqual(panes.count, layout.columns * layout.rows)
        for pane in panes {
            XCTAssertGreaterThan(pane.x1, pane.x0)
            XCTAssertGreaterThan(pane.y1, pane.y0)
            XCTAssertGreaterThanOrEqual(pane.x0, 0)
            XCTAssertLessThanOrEqual(pane.x1, 1)
            XCTAssertGreaterThanOrEqual(pane.y0, 0)
            XCTAssertLessThanOrEqual(pane.y1, 1)
        }
        // Most of a window is glass, but the bars are visible.
        XCTAssertGreaterThan(layout.openShare, 0.6)
        XCTAssertLessThan(layout.openShare, 0.9)
    }

    /// The design check behind the window's size and angle (found by simulation): the light must reach every book in the menu,
    /// leave most of each one bright (a window that darkened the books would defeat its purpose) and still lay visible bars on them.
    func testTheWindowLightsBothMenuBooksAndBarsShowOnThem() {
        let layout = WindowLight.Layout()
        // The two portrait menu slots (`Framing.menuSlot`), a page spread about 1 x 1.4.
        for (name, slot) in [("near", SIMD2(-0.2, 0.85)), ("behind", SIMD2(0.25, -1.05))] {
            let c = layout.coverage(centre: slot, half: SIMD2(0.5, 0.7))
            XCTAssertEqual(c.outside, 0, accuracy: 0.001, "\(name): the window must reach the whole book")
            XCTAssertGreaterThan(c.lit, 0.65, "\(name): the book stays bright")
            XCTAssertGreaterThan(c.bar, 0.08, "\(name): the bars show")
            XCTAssertLessThan(c.bar, 0.35, "\(name): but do not smother it")
        }
        // And the whole felt mat is within reach, so the light has no hard edge across the desk.
        let mat = layout.coverage(centre: SIMD2(0, -0.1), half: SIMD2(1.65, 2.15))
        XCTAssertEqual(mat.outside, 0, accuracy: 0.001)
        XCTAssertGreaterThan(mat.lit, 0.6)
    }

    func testTheLandscapeBooksAreLitToo() {
        let layout = WindowLight.Layout()
        for slot in [Framing.menuSlot(index: 0, wide: true), Framing.menuSlot(index: 1, wide: true)] {
            let c = layout.coverage(centre: SIMD2(slot.x, slot.z), half: SIMD2(0.5, 0.7))
            XCTAssertEqual(c.outside, 0, accuracy: 0.001)
            XCTAssertGreaterThan(c.lit, 0.65, "the book stays bright")
            XCTAssertGreaterThan(c.bar, 0.08, "and the bars show")
            XCTAssertLessThan(c.bar, 0.35)
        }
    }

    func testPanesDoNotOverlap() {
        let panes = WindowLight.Layout().panes
        for (i, a) in panes.enumerated() {
            for b in panes.dropFirst(i + 1) {
                let overlapX = min(a.x1, b.x1) - max(a.x0, b.x0)
                let overlapY = min(a.y1, b.y1) - max(a.y0, b.y0)
                XCTAssertFalse(overlapX > 1e-9 && overlapY > 1e-9)
            }
        }
    }

    func testBarsHaveTheSameThicknessAcrossAndDown() {
        let layout = WindowLight.Layout()
        let panes = layout.panes
        let gapX = panes[1].x0 - panes[0].x1
        let gapY = panes[layout.columns].y0 - panes[0].y1
        XCTAssertEqual(gapX * layout.width, gapY * layout.height, accuracy: 1e-9)
    }

    func testCountsAreNeverZero() {
        var layout = WindowLight.Layout()
        layout.columns = 0
        layout.rows = -2
        XCTAssertEqual(layout.columns, 1)
        XCTAssertEqual(layout.rows, 1)
        XCTAssertFalse(layout.panes.isEmpty)
        _ = WindowLight(layout: layout)
    }

    func testTheSunComesFromTheLeftAndAbove() {
        let sun = WindowLight.sunPosition(centre: SCNVector3Zero)
        XCTAssertLessThan(sun.x, -1, "the window is on the left")
        XCTAssertGreaterThan(sun.y, 1, "above the desk")
        let length = (sun.x * sun.x + sun.y * sun.y + sun.z * sun.z).squareRoot()
        XCTAssertEqual(Double(length), 5.2, accuracy: 0.01)
        XCTAssertGreaterThan(sun.z, 0, "slightly from the camera's side, so the books are lit on the faces the camera sees")
    }

    func testItFadesInAndOutAndHidesWhenOff() {
        let light = WindowLight()
        XCTAssertTrue(light.root.isHidden)
        for _ in 0..<120 { light.update(dt: 1.0 / 60, target: 1) }
        XCTAssertFalse(light.root.isHidden)
        XCTAssertGreaterThan(light.amount, 0.95)
        for _ in 0..<120 { light.update(dt: 1.0 / 60, target: 0) }
        XCTAssertTrue(light.root.isHidden)
        XCTAssertLessThan(light.amount, 0.01)
    }

    /// Leaving the desk for a book clears the light faster than it came, so no bar can drift over a page.
    func testItClearsFasterThanItArrives() {
        let rise = WindowLight(), fall = WindowLight()
        var up = 0, down = 0
        while rise.amount < 0.9, up < 1000 { rise.update(dt: 1.0 / 60, target: 1); up += 1 }
        for _ in 0..<up { fall.update(dt: 1.0 / 60, target: 1) }
        while fall.amount > 0.1, down < 1000 { fall.update(dt: 1.0 / 60, target: 0); down += 1 }
        XCTAssertLessThan(down, up)
    }

    func testTheLightBackgroundIsAGradientAndDarkStaysFlat() throws {
        XCTAssertTrue(SceneLighting.background(dark: false) is UIImage)
        XCTAssertTrue(SceneLighting.background(dark: true) is UIColor)
    }

    func testSunMovesWithTheWindowAndGivesStrongerWarmerLight() throws {
        let lighting = SceneLighting()
        let sun = try XCTUnwrap(lighting.root.childNodes.first { $0.light?.type == .directional })
        let plainIntensity = try XCTUnwrap(sun.light?.intensity)
        let plainPosition = sun.position
        lighting.setWindowAmount(1)
        XCTAssertGreaterThan(try XCTUnwrap(sun.light?.intensity), plainIntensity)
        // It moves to the window's place: a different spot, and higher than the plain light.
        XCTAssertNotEqual(sun.position.x, plainPosition.x)
        XCTAssertGreaterThan(sun.position.y, plainPosition.y, "the window sun is higher than the plain light")
        lighting.setWindowAmount(0)
        XCTAssertEqual(try XCTUnwrap(sun.light?.intensity), plainIntensity, accuracy: 1e-6)
        XCTAssertEqual(sun.position.x, plainPosition.x, accuracy: 1e-5)
        XCTAssertEqual(sun.position.y, plainPosition.y, accuracy: 1e-5)
    }

    /// The sun glides: a half-faded window puts it half way, so opening a book never makes the light jump.
    func testSunGlidesBetweenItsTwoPlaces() throws {
        let lighting = SceneLighting()
        let sun = try XCTUnwrap(lighting.root.childNodes.first { $0.light?.type == .directional })
        let start = sun.position
        lighting.setWindowAmount(1)
        let end = sun.position
        lighting.setWindowAmount(0.5)
        XCTAssertEqual(sun.position.x, (start.x + end.x) / 2, accuracy: 1e-4)
        XCTAssertEqual(sun.position.y, (start.y + end.y) / 2, accuracy: 1e-4)
        XCTAssertEqual(sun.position.z, (start.z + end.z) / 2, accuracy: 1e-4)
    }

    func testDarkModeNeverUsesTheWindowSun() throws {
        let lighting = SceneLighting()
        lighting.setAppearance(dark: true)
        let sun = try XCTUnwrap(lighting.root.childNodes.first { $0.light?.type == .directional })
        let dim = try XCTUnwrap(sun.light?.intensity)
        let place = sun.position
        lighting.setWindowAmount(1)
        XCTAssertEqual(try XCTUnwrap(sun.light?.intensity), dim, accuracy: 1e-6, "moonlight does not become sunshine")
        XCTAssertEqual(sun.position.x, place.x, accuracy: 1e-5)
    }

    /// Switching to dark mode while the window is lit must put the sun back at once.
    func testSwitchingToDarkReturnsTheSun() throws {
        let lighting = SceneLighting()
        let sun = try XCTUnwrap(lighting.root.childNodes.first { $0.light?.type == .directional })
        let plain = sun.position
        lighting.setWindowAmount(1)
        lighting.setAppearance(dark: true)
        XCTAssertEqual(sun.position.x, plain.x, accuracy: 1e-5)
        XCTAssertEqual(sun.position.y, plain.y, accuracy: 1e-5)
    }

    func testMixBlendsColours() {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        SceneLighting.mix(0x000000, 0xff8000, 0.5).getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 0.5, accuracy: 0.01)
        XCTAssertEqual(g, 0.25, accuracy: 0.01)
        XCTAssertEqual(b, 0, accuracy: 0.01)
        SceneLighting.mix(0x102030, 0x405060, 0).getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 16.0 / 255, accuracy: 0.002)
    }
}
