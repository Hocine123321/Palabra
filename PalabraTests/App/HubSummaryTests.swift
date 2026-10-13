import XCTest
import SwiftData
@testable import Palabra

@MainActor
final class HubSummaryTests: XCTestCase {
    private func recent(_ names: [String]) -> [HubSummary.RecentWord] {
        names.map { HubSummary.RecentWord(id: UUID(), spanish: $0, key: $0) }
    }

    func testEmptyLibraryHasNoWords() {
        let summary = HubSummary(wordCount: 0, recent: [])
        XCTAssertEqual(summary.wordCount, 0)
        XCTAssertTrue(summary.recent.isEmpty)
        XCTAssertEqual(summary, .empty)
    }

    func testFewerThanLimitShowsAllInOrder() {
        let words = recent(["hola", "adiós"])
        let summary = HubSummary(wordCount: 2, recent: words)
        XCTAssertEqual(summary.recent.map(\.spanish), ["hola", "adiós"])
    }

    func testMoreThanLimitKeepsOnlyTheFirstThree() {
        let summary = HubSummary(wordCount: 5, recent: recent(["a", "b", "c", "d", "e"]))
        XCTAssertEqual(summary.wordCount, 5, "the count is the whole library, not the tiles shown")
        XCTAssertEqual(summary.recent.map(\.spanish), ["a", "b", "c"])
        XCTAssertEqual(HubSummary.recentLimit, 3)
    }

    /// End to end against the real repository: the newest words come first.
    func testBuiltFromRepositoryUsesNewestFirst() throws {
        let container = try ModelContainer(for: Schema([Word.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let repository = SwiftDataWordRepository(context: ModelContext(container))
        let content = { (word: String) in
            WordContent(
                word: word,
                examples: [
                    .init(context: "a", spanish: "uno", english: "one"),
                    .init(context: "b", spanish: "dos", english: "two"),
                    .init(context: "c", spanish: "tres", english: "three")
                ],
                meaning: .init(translations: ["t"], explanation: "e"),
                usage: .init(explanation: "u", register: "neutral", nuance: nil),
                forms: .init(partOfSpeech: "verb", groups: [.init(label: "Present", items: [.init(form: word, note: nil)])]),
                similarWords: [.init(word: "s", difference: "d")]
            )
        }
        XCTAssertEqual(HubSummary(newestFirst: repository.allWords()), .empty)

        for word in ["uno", "dos", "tres", "cuatro"] {
            repository.insert(spanish: word, key: word, searchKey: word, content: content(word), rawJSON: Data())
            Thread.sleep(forTimeInterval: 0.01) // distinct createdAt, so "newest" is well defined
        }
        let summary = HubSummary(newestFirst: repository.allWords())
        XCTAssertEqual(summary.wordCount, 4)
        XCTAssertEqual(summary.recent.map(\.spanish), ["cuatro", "tres", "dos"])
        XCTAssertEqual(summary.recent.map(\.key), ["cuatro", "tres", "dos"])
    }
}
