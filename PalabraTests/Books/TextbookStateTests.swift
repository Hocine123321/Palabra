import XCTest
@testable import Palabra

final class TextbookStateTests: XCTestCase {
    private func decode(_ json: String) throws -> TextbookState {
        try JSONDecoder().decode(TextbookState.self, from: Data(json.utf8))
    }

    func testEmptyObjectGivesDefaults() throws {
        let state = try decode("{}")
        XCTAssertEqual(state, TextbookState())
        XCTAssertEqual(state.preferences.recallLevel, .essential)
        XCTAssertEqual(state.preferences.textSize, .standard)
    }

    func testUnknownKeysAreIgnoredAndKnownOnesKept() throws {
        let state = try decode(#"{"progress":{"history":{"lastPageID":"a/b","visitedPageIDs":["a/b"],"future":1}},"preferences":{"recallLevel":2,"textSize":1,"future":true},"future":"x"}"#)
        XCTAssertEqual(state.progress["history"]?.lastPageID, "a/b")
        XCTAssertEqual(state.progress["history"]?.visitedPageIDs, ["a/b"])
        XCTAssertEqual(state.preferences.recallLevel, .keyFacts)
        XCTAssertEqual(state.preferences.textSize, .larger)
    }

    func testAnUnknownLevelFallsBackToTheDefaultInsteadOfLosingEverything() throws {
        let state = try decode(#"{"progress":{"history":{"lastPageID":"a/b"}},"preferences":{"recallLevel":99,"textSize":-1}}"#)
        XCTAssertEqual(state.preferences.recallLevel, .essential)
        XCTAssertEqual(state.preferences.textSize, .smaller)
        XCTAssertEqual(state.progress["history"]?.lastPageID, "a/b")
    }

    func testStoreRoundTripsAndStartsEmpty() {
        let suite = "dev.palabra.tests.textbook.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TextbookStateStore(defaults: defaults)
        XCTAssertEqual(store.value, TextbookState())

        var state = TextbookState()
        state.progress["history"] = BookProgress()
        state.progress["history"]?.lastPageID = "a/b"
        state.preferences.recallLevel = .intensive
        store.value = state
        XCTAssertEqual(TextbookStateStore(defaults: defaults).value, state)
    }

    func testGarbageInDefaultsGivesDefaultsNotACrash() {
        let suite = "dev.palabra.tests.textbook.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: TextbookStateStore.defaultsKey)
        XCTAssertEqual(TextbookStateStore(defaults: defaults).value, TextbookState())
    }

    func testBookmarkIsKeptAndOlderSavesWithoutOneStillLoad() throws {
        let withMark = try decode(#"{"progress":{"history":{"lastPageID":"a/b","bookmarkPageID":"a/c"}}}"#)
        XCTAssertEqual(withMark.progress["history"]?.bookmarkPageID, "a/c")
        let without = try decode(#"{"progress":{"history":{"lastPageID":"a/b"}}}"#)
        XCTAssertNil(without.progress["history"]?.bookmarkPageID)
    }
}
