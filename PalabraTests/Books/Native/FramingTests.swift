import XCTest
@testable import Palabra

final class FramingTests: XCTestCase {
    private func metrics(_ w: Double, _ h: Double, _ top: Double, _ bottom: Double) -> ViewMetrics {
        ViewMetrics(size: CGSize(width: w, height: h), insetTop: top, insetBottom: bottom)
    }

    private func vec(_ v: SIMD3<Double>) -> [Double] { [v.x, v.y, v.z] }

    func testMenuPosesMatchGolden() throws {
        let golden = try GoldenFixtures.load()
        XCTAssertFalse(golden.menus.isEmpty)
        for item in golden.menus {
            let pose = Framing.menu(metrics(item.w, item.h, item.insetTop, item.insetBottom))
            XCTAssertEqualArrays(vec(pose.position), item.pos, accuracy: 1e-9, "menu \(item.w)x\(item.h) position")
            XCTAssertEqualArrays(vec(pose.look), item.look, accuracy: 1e-9, "menu \(item.w)x\(item.h) look")
        }
    }

    func testCoverPosesMatchGolden() throws {
        let golden = try GoldenFixtures.load()
        let covers = golden.frames.filter { $0.kind == "cover" }
        XCTAssertFalse(covers.isEmpty)
        for item in covers {
            let pose = Framing.cover(rtl: item.rtl, metrics(item.w, item.h, item.insetTop, item.insetBottom))
            XCTAssertEqualArrays(vec(pose.position), item.pos, accuracy: 1e-9, "cover \(item.w)x\(item.h) rtl=\(item.rtl)")
            XCTAssertEqualArrays(vec(pose.look), item.look, accuracy: 1e-9)
        }
    }

    func testReadingFramesMatchGolden() throws {
        let golden = try GoldenFixtures.load()
        let readings = golden.frames.filter { $0.kind == "reading" }
        XCTAssertGreaterThan(readings.count, 100)
        for item in readings {
            let context = "reading \(item.w)x\(item.h) page=\(item.page ?? -1) rtl=\(item.rtl) focus=\(item.focus ?? false) pan=\(item.pan ?? 0)"
            let frame = Framing.reading(
                page: try XCTUnwrap(item.page), rtl: item.rtl, focus: item.focus ?? false,
                surfaceY: try XCTUnwrap(item.surfaceY), pan: try XCTUnwrap(item.pan),
                metrics(item.w, item.h, item.insetTop, item.insetBottom)
            )
            XCTAssertEqualArrays(vec(frame.pose.position), item.pos, accuracy: 1e-9, context)
            XCTAssertEqualArrays(vec(frame.pose.look), item.look, accuracy: 1e-9, context)
            XCTAssertEqual(frame.panLimit, try XCTUnwrap(item.panLimit), accuracy: 1e-9, context)
            XCTAssertEqual(frame.pxPerZ, try XCTUnwrap(item.pxPerZ), accuracy: 1e-6, context)
            XCTAssertEqual(frame.pan, try XCTUnwrap(item.panAfter), accuracy: 1e-9, context)
        }
    }

    func testMenuSlotsMatchGolden() throws {
        let golden = try GoldenFixtures.load()
        for item in golden.menuSlots {
            XCTAssertEqual(metrics(item.w, item.h, 0, 0).isWide, item.wide)
            for (index, slot) in item.slots.enumerated() {
                let ours = Framing.menuSlot(index: index, wide: item.wide)
                XCTAssertEqual(ours.x, slot.x, accuracy: 1e-12)
                XCTAssertEqual(ours.z, slot.z, accuracy: 1e-12)
                XCTAssertEqual(ours.ry, slot.ry, accuracy: 1e-12)
            }
        }
    }

    func testPanIsZeroInPortrait() {
        let frame = Framing.reading(page: 0, rtl: false, focus: false, surfaceY: 0.1, pan: 0.4, metrics(393, 852, 119, 126))
        XCTAssertEqual(frame.panLimit, 0)
        XCTAssertEqual(frame.pan, 0)
    }

    func testLandscapePanIsClampedToItsLimit() {
        let m = metrics(852, 393, 60, 113)
        let frame = Framing.reading(page: 1, rtl: false, focus: false, surfaceY: 0.1, pan: 99, m)
        XCTAssertGreaterThan(frame.panLimit, 0)
        XCTAssertEqual(frame.pan, frame.panLimit, accuracy: 1e-12)
    }

    func testUsableFractionIsClampedToThirtyFivePercent() {
        XCTAssertEqual(metrics(393, 852, 800, 0).usableFraction, 0.35)
        XCTAssertEqual(metrics(393, 852, 0, 0).usableFraction, 1)
        XCTAssertEqual(metrics(393, 852, 100, 100).usableFraction, 1 - 200.0 / 852, accuracy: 1e-12)
    }

    func testProjectionShiftIsHalfTheInsetDifference() {
        XCTAssertEqual(metrics(393, 852, 119, 154).projectionShift, -17.5, accuracy: 1e-12)
    }

    func testFourthAndLaterBooksGetASlot() {
        let slot = Framing.menuSlot(index: 3, wide: false)
        XCTAssertEqual(slot.x, 3.6, accuracy: 1e-12)
        XCTAssertEqual(slot.z, -3, accuracy: 1e-12)
    }
}
