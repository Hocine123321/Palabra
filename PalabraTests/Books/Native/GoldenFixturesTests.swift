import XCTest

final class GoldenFixturesTests: XCTestCase {
    func testGoldenFixturesLoadAndAreNotEmpty() throws {
        let g = try GoldenFixtures.load()
        XCTAssertEqual(g.constants.sx, 28)
        XCTAssertEqual(g.constants.sz, 8)
        XCTAssertEqual(g.constants.blockCols, 14)
        XCTAssertEqual(g.constants.pw, 1.0)
        XCTAssertEqual(g.constants.ph, 1820.0 / 1280.0, accuracy: 1e-12)
        XCTAssertEqual(g.constants.coverT, 0.04)
        XCTAssertFalse(g.leaves.isEmpty)
        XCTAssertFalse(g.blocks.isEmpty)
        XCTAssertFalse(g.ribbons.isEmpty)
        XCTAssertFalse(g.frames.isEmpty)
        XCTAssertFalse(g.menus.isEmpty)
        XCTAssertFalse(g.menuSlots.isEmpty)
        XCTAssertFalse(g.eases.isEmpty)
        XCTAssertFalse(g.pagination.isEmpty)
        // 29 x 9 vertices per leaf, three floats each.
        for leaf in g.leaves {
            XCTAssertEqual(leaf.positions.count, (g.constants.sx + 1) * (g.constants.sz + 1) * 3)
            XCTAssertEqual(leaf.normals.count, leaf.positions.count)
        }
    }
}
