import Foundation
import XCTest

/// Numbers produced by the original Three.js scene code (kept in `native-golden.json`; the web scene itself has been removed)
/// that the native Swift scene must reproduce. They are the reference for the book geometry and camera framing.
struct Golden: Decodable {
    struct Constants: Decodable {
        let pw: Double, ph: Double, coverT: Double, sx: Int, sz: Int, blockCols: Int, gutterDip: Double, fov: Double
        enum CodingKeys: String, CodingKey {
            case pw = "PW", ph = "PH", coverT = "COVER_T", sx = "SX", sz = "SZ", blockCols = "BLOCK_COLS", gutterDip = "GUTTER_DIP", fov = "FOV"
        }
    }

    struct Leaf: Decodable {
        let leafCount: Int, index: Int, bulk: Double
        let p: Double, peek: Double, grabZ: Double
        let restYr: Double, restYl: Double, surfaceYRight: Double, surfaceYLeft: Double
        let positions: [Double], normals: [Double]
    }

    struct BlockSide: Decodable {
        let visible: Bool, scaleX: Double
        let positions: [Double], uvs: [Double]
    }

    struct Block: Decodable {
        let leafCount: Int, flipped: Int, bulk: Double
        let right: BlockSide, left: BlockSide
    }

    struct Ribbon: Decodable {
        let leafCount: Int, flipped: Int, coverOpen: Double, visible: Bool
        let positions: [Double]
    }

    struct Frame: Decodable {
        let kind: String
        let w: Double, h: Double, insetTop: Double, insetBottom: Double
        let rtl: Bool
        let focus: Bool?, page: Int?, pan: Double?, surfaceY: Double?
        let pos: [Double], look: [Double]
        let panLimit: Double?, pxPerZ: Double?, panAfter: Double?
    }

    struct Menu: Decodable {
        let w: Double, h: Double, insetTop: Double, insetBottom: Double
        let pos: [Double], look: [Double]
    }

    struct MenuSlots: Decodable {
        struct Slot: Decodable { let x: Double, y: Double, z: Double, ry: Double }
        let w: Double, h: Double, wide: Bool
        let slots: [Slot]
    }

    struct Ease: Decodable {
        let name: String, t: Double, value: Double
    }

    struct Pagination: Decodable {
        struct Part: Decodable {
            struct PlacedBlock: Decodable { let index: Int, height: Double }
            let id: String, baseId: String, part: Int, parts: Int, scale: Double
            let blocks: [PlacedBlock]
        }
        let bookId: String, scale: Double, pageId: String
        let parts: [Part]
    }

    let constants: Constants
    let leaves: [Leaf]
    let blocks: [Block]
    let ribbons: [Ribbon]
    let frames: [Frame]
    let menus: [Menu]
    let menuSlots: [MenuSlots]
    let eases: [Ease]
    let pagination: [Pagination]
}

enum GoldenFixtures {
    private static var cached: Golden?

    static func load() throws -> Golden {
        if let cached { return cached }
        let bundle = Bundle(for: GoldenToken.self)
        guard let url = bundle.url(forResource: "native-golden", withExtension: "json") else {
            throw NSError(domain: "GoldenFixtures", code: 1, userInfo: [NSLocalizedDescriptionKey: "native-golden.json is not in the test bundle"])
        }
        let golden = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
        cached = golden
        return golden
    }

    private final class GoldenToken {}
}

/// Asserts two flat arrays are equal element by element within `accuracy`, naming the first mismatch.
func XCTAssertEqualArrays(_ actual: [Double], _ expected: [Double], accuracy: Double, _ context: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    guard actual.count == expected.count else {
        XCTFail("\(context()) length \(actual.count) != \(expected.count)", file: file, line: line)
        return
    }
    for (i, pair) in zip(actual, expected).enumerated() where abs(pair.0 - pair.1) > accuracy {
        XCTFail("\(context()) index \(i): \(pair.0) != \(pair.1) (accuracy \(accuracy))", file: file, line: line)
        return
    }
}
