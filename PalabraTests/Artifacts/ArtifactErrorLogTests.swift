import XCTest
@testable import Palabra

@MainActor
final class ArtifactErrorLogTests: XCTestCase {
    func testKeepsNewestTwentyEntries() {
        let log = ArtifactErrorLog()
        for index in 0..<25 { log.append("error \(index)") }
        XCTAssertEqual(log.entries.count, 20)
        XCTAssertEqual(log.entries.first, "error 5")
        XCTAssertEqual(log.entries.last, "error 24")
    }

    func testCapsEntryLengthAtThreeHundred() {
        let log = ArtifactErrorLog()
        log.append(String(repeating: "x", count: 1_000))
        XCTAssertEqual(log.entries.first?.count, 300)
    }

    func testSummaryJoinsEntriesWithNewlines() {
        let log = ArtifactErrorLog()
        log.append("a")
        log.append("b")
        XCTAssertEqual(log.summary, "a\nb")
    }

    func testClearEmptiesTheLog() {
        let log = ArtifactErrorLog()
        log.append("a")
        log.clear()
        XCTAssertTrue(log.entries.isEmpty)
        XCTAssertEqual(log.summary, "")
    }
}
