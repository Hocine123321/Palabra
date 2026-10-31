import XCTest
@testable import Palabra

/// The words spoken between Swift and the 3D scene. No web view: plain dictionaries in, plain JavaScript out.
final class BooksBridgeTests: XCTestCase {
    // MARK: Messages from the scene

    func testStateMessageDecodesEveryField() throws {
        let body: [String: Any] = [
            "type": "state",
            "state": [
                "mode": "reading", "bookId": "history", "title": "التاريخ", "page": 3, "pageCount": 7,
                "basePageId": "lesson/p3", "tool": "lens", "focus": true, "recall": true, "level": 2, "revealed": true,
                "bookmark": "lesson/p1", "textSize": 1, "canNext": true, "canPrev": false, "rtl": true, "problems": 0,
                "books": [["id": "history", "title": "التاريخ", "subject": "history", "pages": 7, "rtl": true]],
            ] as [String: Any],
        ]
        guard case .state(let state)? = SceneMessage(body: body) else { return XCTFail("not a state message") }
        XCTAssertEqual(state.mode, .reading)
        XCTAssertEqual(state.bookID, "history")
        XCTAssertEqual(state.page, 3)
        XCTAssertEqual(state.pageCount, 7)
        XCTAssertEqual(state.basePageID, "lesson/p3")
        XCTAssertEqual(state.tool, "lens")
        XCTAssertTrue(state.focus)
        XCTAssertEqual(state.level, .keyFacts)
        XCTAssertEqual(state.textSize, .larger)
        XCTAssertEqual(state.bookmarkPageID, "lesson/p1")
        XCTAssertTrue(state.isRightToLeft)
        XCTAssertEqual(state.books.first?.pages, 7)
        XCTAssertTrue(state.isReading)
    }

    func testAnOddStateStillDecodesWithDefaults() throws {
        guard case .state(let state)? = SceneMessage(body: ["type": "state", "state": ["mode": "nonsense", "level": 99]]) else {
            return XCTFail("not a state message")
        }
        XCTAssertEqual(state.mode, .menu)
        XCTAssertEqual(state.level, .essential)
        XCTAssertFalse(state.isReading)
    }

    func testReadingMessages() {
        XCTAssertEqual(SceneMessage(body: ["type": "ready"]), .ready)
        XCTAssertEqual(SceneMessage(body: ["type": "visit", "bookId": "history", "pageId": "a/b"]), .visit(bookID: "history", pageID: "a/b"))
        XCTAssertEqual(SceneMessage(body: ["type": "bookmark", "bookId": "history", "pageId": "a/b"]), .bookmark(bookID: "history", pageID: "a/b"))
        XCTAssertEqual(SceneMessage(body: ["type": "term", "id": "t", "term": "Term", "definition": "Meaning"]), .term(id: "t", term: "Term", definition: "Meaning"))
        XCTAssertEqual(SceneMessage(body: ["type": "termClose"]), .termClose)
        XCTAssertEqual(SceneMessage(body: ["type": "empty", "bookId": "geography"]), .empty(bookID: "geography"))
        XCTAssertEqual(SceneMessage(body: ["type": "error", "message": "boom"]), .error("boom"))
    }

    func testPreferenceMessageKeepsOnlyWhatItCarries() {
        XCTAssertEqual(SceneMessage(body: ["type": "preference", "recallLevel": 3]), .preference(recallLevel: .intensive, textSize: nil))
        XCTAssertEqual(SceneMessage(body: ["type": "preference", "textSize": -1]), .preference(recallLevel: nil, textSize: .smaller))
    }

    func testUnknownOrIncompleteMessagesAreIgnored() {
        XCTAssertNil(SceneMessage(body: "text"))
        XCTAssertNil(SceneMessage(body: ["type": "mystery"]))
        XCTAssertNil(SceneMessage(body: ["type": "visit", "bookId": "history"]))
        XCTAssertNil(SceneMessage(body: ["nothing": 1]))
    }

    // MARK: Commands to the scene

    func testCommandsBecomeOneLineOfJavaScript() {
        XCTAssertEqual(SceneCommand.next.javaScript, #"window.palabra && window.palabra.command({"name":"next"});"#)
        XCTAssertEqual(SceneCommand.previous.dictionary["name"] as? String, "prev")
        XCTAssertEqual(SceneCommand.openBook(id: "history", pageID: nil).dictionary["bookId"] as? String, "history")
        XCTAssertNil(SceneCommand.openBook(id: "history", pageID: nil).dictionary["pageId"])
        XCTAssertEqual(SceneCommand.openBook(id: "history", pageID: "a/b").dictionary["pageId"] as? String, "a/b")
        XCTAssertEqual(SceneCommand.setLevel(.intensive).dictionary["level"] as? Int, 3)
        XCTAssertEqual(SceneCommand.setRecall(true).dictionary["enabled"] as? Bool, true)
        XCTAssertEqual(SceneCommand.setTextSize(.smaller).dictionary["size"] as? Int, -1)
        XCTAssertEqual(SceneCommand.setInsets(top: 10, bottom: 20).dictionary["bottom"] as? Double, 20)
        XCTAssertEqual(SceneCommand.setAppearance(dark: true).dictionary["dark"] as? Bool, true)
    }

    func testCommandNamesMatchTheScene() throws {
        // The scene (web/books3d/src/app.js) switches on these names; renaming one on either side breaks the bridge.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("web/books3d/src/app.js")
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return } // the web sources are not on the test device
        for name in ["openBook", "closeBook", "next", "prev", "goto", "setRecall", "setLevel", "togglePageReveal", "setTool", "setFocus", "setTextSize", "setInsets", "setAppearance", "closeTerm"] {
            XCTAssertTrue(source.contains("case '\(name)'"), "the scene doesn't know \(name)")
        }
    }

    // MARK: Payload

    func testPayloadCarriesCatalogueLessonsAndReadingState() throws {
        var state = TextbookState()
        state.preferences.recallLevel = .intensive
        state.preferences.textSize = .larger
        var progress = BookProgress()
        progress.lastPageID = "empires/p1"
        progress.visitedPageIDs = ["empires/p1"]
        progress.bookmarkPageID = "empires/p2"
        state.progress["history"] = progress

        let source = StubBookSource(
            catalogue: BookFixtures.catalogue,
            lessons: ["lesson-empires": BookFixtures.empires, "lesson-revolutions": BookFixtures.revolutions]
        )
        let data = try BooksScenePayload.make(source: source, state: state)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let books = try XCTUnwrap((json["catalogue"] as? [String: Any])?["books"] as? [[String: Any]])
        XCTAssertEqual(books.count, 2)
        let lessons = try XCTUnwrap(json["lessons"] as? [String: Any])
        XCTAssertNotNil(lessons["lesson-empires"])
        XCTAssertNotNil(lessons["lesson-revolutions"])
        XCTAssertNil(lessons["lesson-rivers"], "a missing lesson is left out, not fatal")
        let preferences = try XCTUnwrap(json["preferences"] as? [String: Int])
        XCTAssertEqual(preferences["recallLevel"], 3)
        XCTAssertEqual(preferences["textSize"], 1)
        let saved = try XCTUnwrap((json["progress"] as? [String: Any])?["history"] as? [String: Any])
        XCTAssertEqual(saved["lastPageID"] as? String, "empires/p1")
        XCTAssertEqual(saved["visitedPageIDs"] as? [String], ["empires/p1"])
        XCTAssertEqual((json["bookmarks"] as? [String: String])?["history"], "empires/p2")
    }

    func testLoadScriptEmbedsThePayloadAndMotionChoice() throws {
        let source = StubBookSource(catalogue: BookFixtures.catalogue, lessons: [:])
        let data = try BooksScenePayload.make(source: source, state: TextbookState())
        let script = BooksScenePayload.loadScript(payload: data, reducedMotion: true)
        XCTAssertTrue(script.hasPrefix("window.palabra.load({"))
        XCTAssertTrue(script.hasSuffix("{reducedMotion: true});"))
    }

    func testTheBundledBooksProduceAPayload() throws {
        let data = try BooksScenePayload.make(source: BundleBookSource(), state: TextbookState())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertFalse((json["lessons"] as? [String: Any] ?? [:]).isEmpty)
    }

    func testTheSceneIsInTheAppBundle() {
        XCTAssertNotNil(BooksSceneView.sceneURL, "Resources/Books3D/books3d.html is missing: run `npm run build` in web/books3d")
    }
}

/// The model's side of the conversation: what the scene reports ends up in the saved reading state.
@MainActor
final class BooksSceneModelTests: XCTestCase {
    private func makeModel() -> (BooksSceneModel, BookShelf, Void) {
        let shelf = BookShelf.inMemory(source: StubBookSource(catalogue: BookFixtures.catalogue, lessons: ["lesson-empires": BookFixtures.empires, "lesson-revolutions": BookFixtures.revolutions]))
        return (BooksSceneModel(shelf: shelf), shelf, ())
    }

    func testVisitsPreferencesAndBookmarksAreSaved() {
        let (model, shelf, _) = makeModel()
        model.handle(.visit(bookID: "history", pageID: "empires/p1"))
        model.handle(.bookmark(bookID: "history", pageID: "empires/p2"))
        model.handle(.preference(recallLevel: .keyFacts, textSize: nil))
        model.handle(.preference(recallLevel: nil, textSize: .larger))
        XCTAssertEqual(shelf.lastPageID(bookID: "history"), "empires/p1")
        XCTAssertEqual(shelf.bookmarkPageID(bookID: "history"), "empires/p2")
        XCTAssertEqual(shelf.preferences.recallLevel, .keyFacts)
        XCTAssertEqual(shelf.preferences.textSize, .larger)
    }

    func testCommandsWaitForTheSceneAndOnlyTheLatestAppearanceIsKept() {
        let (model, _, _) = makeModel()
        var sent: [String] = []
        model.run = { sent.append($0) }
        model.send(.setAppearance(dark: false))
        model.send(.next)
        model.send(.setAppearance(dark: true))
        XCTAssertTrue(sent.isEmpty, "nothing is sent before the scene is ready")
        model.handle(.ready)
        XCTAssertEqual(sent.count, 2)
        XCTAssertTrue(sent[0].contains("next"))
        XCTAssertTrue(sent[1].contains("\"dark\":true"))
        model.send(.previous)
        XCTAssertEqual(sent.count, 3)
    }

    func testTermsOpenAndCloseWithTheScene() {
        let (model, _, _) = makeModel()
        model.handle(.term(id: "t", term: "Term", definition: "Meaning"))
        XCTAssertEqual(model.activeTerm?.term, "Term")
        model.handle(.termClose)
        XCTAssertNil(model.activeTerm)
        model.handle(.term(id: "t", term: "Term", definition: "Meaning"))
        var stateInMenu = SceneState()
        stateInMenu.mode = .menu
        model.handle(.state(stateInMenu))
        XCTAssertNil(model.activeTerm, "leaving the book closes the definition")
    }

    func testAnEmptyBookExplainsItself() {
        let (model, _, _) = makeModel()
        model.handle(.empty(bookID: "geography"))
        XCTAssertEqual(model.notice, "No lessons yet")
    }

    func testASceneErrorSwitchesToTheTextShelf() {
        let (model, _, _) = makeModel()
        model.handle(.error("boom"))
        XCTAssertNotNil(model.failure)
    }
}
