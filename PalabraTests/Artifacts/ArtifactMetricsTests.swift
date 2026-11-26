import XCTest
@testable import Palabra

final class ArtifactMetricsTests: XCTestCase {
    private func html(_ lines: [String]) -> Data { Data(lines.joined(separator: "\n").utf8) }

    func testSizeCountsLinesAndBytes() {
        let size = ArtifactMetrics.size(of: html(["<html>", "<p>hi</p>", "</html>"]), kind: .app)
        XCTAssertEqual(size.lines, 3)
        XCTAssertEqual(size.bytes, 6 + 1 + 9 + 1 + 7)
    }

    func testTrailingNewlineIsNotAnotherLine() {
        XCTAssertEqual(ArtifactMetrics.size(of: Data("a\nb\n".utf8), kind: .app).lines, 2)
        XCTAssertEqual(ArtifactMetrics.size(of: Data(), kind: .app).lines, 0)
    }

    func testCompactSpecJSONIsCountedPrettyPrinted() {
        let payload = Data(#"{"blocks":[{"type":"text","text":"hola"}]}"#.utf8)
        XCTAssertGreaterThan(ArtifactMetrics.size(of: payload, kind: .spec).lines, 1)
        XCTAssertEqual(ArtifactMetrics.size(of: payload, kind: .spec).bytes, payload.count)
    }

    func testChangeCountsAddedAndRemovedLines() {
        let old = html(["a", "b", "c"])
        let new = html(["a", "b2", "c", "d"])
        XCTAssertEqual(ArtifactMetrics.change(from: old, to: new, kind: .app), ArtifactChange(added: 2, removed: 1))
    }

    func testIdenticalPagesChangeNothing() {
        let page = html(["x", "y"])
        let change = ArtifactMetrics.change(from: page, to: page, kind: .app)
        XCTAssertEqual(change, ArtifactChange(added: 0, removed: 0))
        XCTAssertEqual(change?.isEmpty, true)
    }

    func testNoBaselineMeansNoChange() {
        XCTAssertNil(ArtifactMetrics.change(from: nil, to: html(["x"]), kind: .app))
    }

    func testHugePagesFallBackToTheLengthDifference() {
        let big = html((0..<(ArtifactMetrics.exactDiffLimit + 10)).map { "line \($0)" })
        let small = html(["only"])
        let change = ArtifactMetrics.change(from: small, to: big, kind: .app)
        XCTAssertEqual(change?.removed, 0)
        XCTAssertEqual(change?.added, ArtifactMetrics.exactDiffLimit + 9)
    }

    func testSpecChangeIsMeasuredOnTheSortedPrettyJSON() {
        let old = Data(#"{"blocks":[{"text":"a","type":"text"}]}"#.utf8)
        let new = Data(#"{"blocks":[{"text":"a","type":"text"},{"text":"b","type":"text"}]}"#.utf8)
        let change = ArtifactMetrics.change(from: old, to: new, kind: .spec)
        XCTAssertEqual(change?.removed, 0)
        XCTAssertGreaterThan(change?.added ?? 0, 0)
    }
}
