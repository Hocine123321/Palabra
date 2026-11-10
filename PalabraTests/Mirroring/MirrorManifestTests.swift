import XCTest
@testable import Palabra

final class MirrorManifestTests: XCTestCase {
    func testIDsHashMatchesTheSharedVector() throws {
        let vectors = try MirrorVectors.load()
        XCTAssertEqual(MirrorManifest.idsHash(vectors.manifest.ids), vectors.manifest.idsHashHex)
        XCTAssertEqual(MirrorManifest.idsHash(vectors.manifest.ids.reversed()), vectors.manifest.idsHashHex, "order of the input does not matter")
        XCTAssertEqual(MirrorManifest.idsHash([]), vectors.empty.idsHashHex)
    }

    func testRecordHasKindRecordIDAndPayload() throws {
        XCTAssertEqual(MirrorManifest.kind, "manifest")
        XCTAssertEqual(MirrorManifest.recordID, "manifest")
        XCTAssertEqual(MirrorManifest.heartbeat, 600)
        let record = MirrorManifest.record(ids: ["b", "a"], counts: ["word": 2], now: Date(timeIntervalSince1970: 1_794_259_800))
        XCTAssertEqual(record.kind, "manifest")
        XCTAssertEqual(record.recordID, "manifest")
        guard case .object(let payload) = record.payload else { return XCTFail("payload is an object") }
        XCTAssertEqual(Set(payload.keys), ["counts", "idsHash", "pushedAt"])
        XCTAssertEqual(payload["counts"], .object(["word": .number(2)]))
        XCTAssertEqual(payload["idsHash"], .string(MirrorManifest.idsHash(["a", "b"])))
        XCTAssertEqual(payload["pushedAt"], .string("2026-11-09T21:30:00Z"))
    }
}
