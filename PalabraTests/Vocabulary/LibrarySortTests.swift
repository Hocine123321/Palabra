import XCTest
@testable import Palabra

final class LibrarySortTests: XCTestCase {
    private func word(_ spanish: String, day: Int) -> Word {
        Word(spanish: spanish, key: spanish, searchKey: WordKey.search(spanish),
             content: StubAIClient.sampleContent(for: spanish), rawJSON: Data(),
             createdAt: Date(timeIntervalSince1970: TimeInterval(day) * 86_400))
    }

    private var words: [Word] { [word("mesa", day: 2), word("\u{00E1}rbol", day: 3), word("casa", day: 1)] }

    func testNewestFirst() {
        XCTAssertEqual(LibrarySort.newest.apply(words).map(\.spanish), ["\u{00E1}rbol", "mesa", "casa"])
    }

    func testOldestFirst() {
        XCTAssertEqual(LibrarySort.oldest.apply(words).map(\.spanish), ["casa", "mesa", "\u{00E1}rbol"])
    }

    func testAlphabeticalIgnoresAccentsWhenOrdering() {
        XCTAssertEqual(LibrarySort.alphabetical.apply(words).map(\.spanish), ["\u{00E1}rbol", "casa", "mesa"])
    }

    func testAnUnknownStoredValueFallsBackToNewest() {
        XCTAssertEqual(LibrarySort(rawValue: "nonsense") ?? .newest, .newest)
        XCTAssertEqual(Set(LibrarySort.allCases.map(\.rawValue)).count, 3)
    }
}
