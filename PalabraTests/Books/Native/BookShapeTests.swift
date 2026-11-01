import XCTest
@testable import Palabra

final class BookShapeTests: XCTestCase {
    private func flat(_ v: [SIMD3<Float>]) -> [Double] { v.flatMap { [Double($0.x), Double($0.y), Double($0.z)] } }
    private func flat(_ v: [SIMD2<Float>]) -> [Double] { v.flatMap { [Double($0.x), Double($0.y)] } }

    /// A book where leaves before `index` lie on the left stack, the rest on the right, and `index` is in the given state.
    private func shape(for leaf: Golden.Leaf) -> BookShape {
        var s = BookShape(leafCount: leaf.leafCount, bulk: leaf.bulk)
        for i in 0..<leaf.leafCount { s.leaves[i] = LeafState(p: i < leaf.index ? 1 : 0, peek: 0, grabZ: 0.5) }
        s.leaves[leaf.index] = LeafState(p: leaf.p, peek: leaf.peek, grabZ: leaf.grabZ)
        return s
    }

    private func flipped(_ count: Int, of leafCount: Int, bulk: Double) -> BookShape {
        var s = BookShape(leafCount: leafCount, bulk: bulk)
        for i in 0..<leafCount { s.leaves[i].p = i < count ? 1 : 0 }
        return s
    }

    func testLeafPositionsMatchGolden() throws {
        let golden = try GoldenFixtures.load()
        for leaf in golden.leaves {
            let mesh = shape(for: leaf).deform(leaf: leaf.index)
            XCTAssertEqualArrays(flat(mesh.positions), leaf.positions, accuracy: 1e-5,
                                 "n=\(leaf.leafCount) k=\(leaf.index) p=\(leaf.p) peek=\(leaf.peek) grab=\(leaf.grabZ)")
        }
    }

    func testLeafNormalsMatchGolden() throws {
        let golden = try GoldenFixtures.load()
        for leaf in golden.leaves {
            let mesh = shape(for: leaf).deform(leaf: leaf.index)
            XCTAssertEqualArrays(flat(mesh.normals), leaf.normals, accuracy: 1e-4,
                                 "normals n=\(leaf.leafCount) k=\(leaf.index) p=\(leaf.p) peek=\(leaf.peek) grab=\(leaf.grabZ)")
        }
    }

    func testRestYAndSurfaceYMatchGolden() throws {
        let golden = try GoldenFixtures.load()
        for leaf in golden.leaves {
            let s = shape(for: leaf)
            let rest = s.restY(leaf.index)
            XCTAssertEqual(rest.yr, leaf.restYr, accuracy: 1e-9)
            XCTAssertEqual(rest.yl, leaf.restYl, accuracy: 1e-9)
            XCTAssertEqual(s.surfaceY(side: 1), leaf.surfaceYRight, accuracy: 1e-9)
            XCTAssertEqual(s.surfaceY(side: -1), leaf.surfaceYLeft, accuracy: 1e-9)
        }
    }

    func testBlocksMatchGolden() throws {
        let golden = try GoldenFixtures.load()
        XCTAssertFalse(golden.blocks.isEmpty)
        for item in golden.blocks {
            let s = flipped(item.flipped, of: item.leafCount, bulk: item.bulk)
            let heights = s.blockHeights()
            for (name, mesh, expected) in [("right", s.block(height: heights.right, side: 1), item.right),
                                           ("left", s.block(height: heights.left, side: -1), item.left)] {
                let context = "n=\(item.leafCount) flipped=\(item.flipped) \(name)"
                XCTAssertEqual(mesh.visible, expected.visible, context)
                XCTAssertEqual(mesh.scaleX, expected.scaleX, context)
                XCTAssertEqualArrays(flat(mesh.positions), expected.positions, accuracy: 1e-5, context)
                XCTAssertEqualArrays(flat(mesh.uvs), expected.uvs, accuracy: 1e-4, context)
            }
        }
    }

    func testRibbonMatchesGolden() throws {
        let golden = try GoldenFixtures.load()
        for item in golden.ribbons {
            var s = flipped(item.flipped, of: item.leafCount, bulk: 0.26)
            s.coverOpen = item.coverOpen
            let ribbon = s.ribbon()
            XCTAssertEqual(ribbon.visible, item.visible, "open=\(item.coverOpen)")
            XCTAssertEqualArrays(flat(ribbon.positions), item.positions, accuracy: 1e-5, "ribbon open=\(item.coverOpen)")
        }
    }

    func testOneLeafBookDeformsWithoutNaN() {
        var s = BookShape(leafCount: 1, bulk: 0.2)
        for p in stride(from: 0.0, through: 1.0, by: 0.05) {
            s.leaves[0] = LeafState(p: p, peek: 0.6, grabZ: 0.3)
            let mesh = s.deform(leaf: 0)
            XCTAssertEqual(mesh.positions.count, BookDims.verticesPerLeaf)
            XCTAssertTrue(flat(mesh.positions).allSatisfy { $0.isFinite }, "positions at p=\(p)")
            XCTAssertTrue(flat(mesh.normals).allSatisfy { $0.isFinite }, "normals at p=\(p)")
        }
    }

    func testZeroLeavesIsTreatedAsOne() {
        XCTAssertEqual(BookShape(leafCount: 0).leaves.count, 1)
    }

    func testLeafIndicesAreCounterClockwiseQuads() {
        let indices = BookShape.leafIndices
        XCTAssertEqual(indices.count, 28 * 8 * 6)
        XCTAssertEqual(Array(indices.prefix(6)), [0, 29, 1, 1, 29, 30])
        XCTAssertTrue(indices.allSatisfy { Int($0) < BookDims.verticesPerLeaf })
    }

    func testBackUVsAreTheFrontMirroredInU() {
        let front = BookShape.leafUVs(back: false), back = BookShape.leafUVs(back: true)
        XCTAssertEqual(front.count, BookDims.verticesPerLeaf)
        for (f, b) in zip(front, back) {
            XCTAssertEqual(f.x, 1 - b.x, accuracy: 1e-6)
            XCTAssertEqual(f.y, b.y)
        }
        XCTAssertEqual(front[0], SIMD2<Float>(0, 1))
    }

    func testBlockIndicesStayInRange() {
        XCTAssertTrue(BookShape.blockIndices.allSatisfy { Int($0) < BookDims.blockVertexCount })
        XCTAssertEqual(BookShape.blockIndices.count, BookDims.blockColumns * 6 * 2 + 6)
    }
}
