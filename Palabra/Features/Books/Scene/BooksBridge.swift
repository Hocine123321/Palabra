import Foundation

// The conversation between Swift and the 3D scene (Resources/Books3D/books3d.html, built from web/books3d).
// Messages come in as dictionaries from WKWebView; commands go out as one line of JavaScript. Both are plain data so they
// can be tested without a web view.

/// A book as the scene lists it.
struct SceneBookInfo: Equatable, Identifiable {
    var id: String
    var title: String
    var subject: String
    var pages: Int
    var isRightToLeft: Bool
}

/// The scene's own state, sent after every change.
struct SceneState: Equatable {
    enum Mode: String { case menu, opening, reading, closing }

    var mode: Mode = .menu
    var bookID: String?
    var title: String?
    var page = 0
    var pageCount = 0
    var basePageID: String?
    var tool: String?
    var focus = false
    var recall = false
    var level = RecallLevel.essential
    var revealed = false
    var bookmarkPageID: String?
    var textSize = ReaderTextSize.standard
    var canNext = false
    var canPrev = false
    var isRightToLeft = false
    var books: [SceneBookInfo] = []
    var problems = 0

    var isReading: Bool { mode == .reading || mode == .opening }

    init() {}

    init(json: [String: Any]) {
        mode = (json["mode"] as? String).flatMap(Mode.init(rawValue:)) ?? .menu
        bookID = json["bookId"] as? String
        title = json["title"] as? String
        page = json["page"] as? Int ?? 0
        pageCount = json["pageCount"] as? Int ?? 0
        basePageID = json["basePageId"] as? String
        tool = json["tool"] as? String
        focus = json["focus"] as? Bool ?? false
        recall = json["recall"] as? Bool ?? false
        level = RecallLevel(rawValue: json["level"] as? Int ?? 1) ?? .essential
        revealed = json["revealed"] as? Bool ?? false
        bookmarkPageID = json["bookmark"] as? String
        textSize = ReaderTextSize(rawValue: json["textSize"] as? Int ?? 0) ?? .standard
        canNext = json["canNext"] as? Bool ?? false
        canPrev = json["canPrev"] as? Bool ?? false
        isRightToLeft = json["rtl"] as? Bool ?? false
        problems = json["problems"] as? Int ?? 0
        books = (json["books"] as? [[String: Any]] ?? []).compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            return SceneBookInfo(
                id: id,
                title: item["title"] as? String ?? id,
                subject: item["subject"] as? String ?? "",
                pages: item["pages"] as? Int ?? 0,
                isRightToLeft: item["rtl"] as? Bool ?? false
            )
        }
    }
}

/// Everything the scene can tell Swift.
enum SceneMessage: Equatable {
    case ready
    case state(SceneState)
    case visit(bookID: String, pageID: String)
    case term(id: String, term: String, definition: String)
    case termClose
    case bookmark(bookID: String, pageID: String)
    case preference(recallLevel: RecallLevel?, textSize: ReaderTextSize?)
    case empty(bookID: String)
    case error(String)

    /// Nil for anything that isn't a message this app knows.
    init?(body: Any) {
        guard let json = body as? [String: Any], let type = json["type"] as? String else { return nil }
        switch type {
        case "ready":
            self = .ready
        case "state":
            guard let state = json["state"] as? [String: Any] else { return nil }
            self = .state(SceneState(json: state))
        case "visit":
            guard let book = json["bookId"] as? String, let page = json["pageId"] as? String else { return nil }
            self = .visit(bookID: book, pageID: page)
        case "term":
            guard let id = json["id"] as? String else { return nil }
            self = .term(id: id, term: json["term"] as? String ?? "", definition: json["definition"] as? String ?? "")
        case "termClose":
            self = .termClose
        case "bookmark":
            guard let book = json["bookId"] as? String, let page = json["pageId"] as? String else { return nil }
            self = .bookmark(bookID: book, pageID: page)
        case "preference":
            let level = (json["recallLevel"] as? Int).flatMap(RecallLevel.init(rawValue:))
            let size = (json["textSize"] as? Int).flatMap(ReaderTextSize.init(rawValue:))
            self = .preference(recallLevel: level, textSize: size)
        case "empty":
            self = .empty(bookID: json["bookId"] as? String ?? "")
        case "error":
            self = .error(json["message"] as? String ?? "")
        default:
            return nil
        }
    }
}

/// Everything Swift can ask of the scene.
enum SceneCommand: Equatable {
    case openBook(id: String, pageID: String?)
    case closeBook
    case next
    case previous
    case goTo(pageID: String)
    case setRecall(Bool)
    case setLevel(RecallLevel)
    case togglePageReveal
    case setTool(String?)
    case setFocus(Bool)
    case setTextSize(ReaderTextSize)
    case setInsets(top: Double, bottom: Double)
    case setAppearance(dark: Bool)
    case setQuality(SceneQuality)
    case closeTerm

    var dictionary: [String: Any] {
        switch self {
        case .openBook(let id, let pageID):
            var d: [String: Any] = ["name": "openBook", "bookId": id]
            if let pageID { d["pageId"] = pageID }
            return d
        case .closeBook: return ["name": "closeBook"]
        case .next: return ["name": "next"]
        case .previous: return ["name": "prev"]
        case .goTo(let id): return ["name": "goto", "pageId": id]
        case .setRecall(let on): return ["name": "setRecall", "enabled": on]
        case .setLevel(let level): return ["name": "setLevel", "level": level.rawValue]
        case .togglePageReveal: return ["name": "togglePageReveal"]
        case .setTool(let tool): return ["name": "setTool", "tool": tool.map { $0 as Any } ?? NSNull()]
        case .setFocus(let on): return ["name": "setFocus", "on": on]
        case .setTextSize(let size): return ["name": "setTextSize", "size": size.rawValue]
        case .setInsets(let top, let bottom): return ["name": "setInsets", "top": top, "bottom": bottom]
        case .setAppearance(let dark): return ["name": "setAppearance", "dark": dark]
        case .setQuality(let quality): return ["name": "setQuality", "quality": quality.rawValue]
        case .closeTerm: return ["name": "closeTerm"]
        }
    }

    /// The JavaScript that runs this command in the scene.
    var javaScript: String {
        let data = (try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])) ?? Data("{}".utf8)
        return "window.palabra && window.palabra.command(\(String(decoding: data, as: UTF8.self)));"
    }
}

/// The books, lessons and reading state the scene starts from. The scene does its own page layout from the same JSON the
/// app validates, so a lesson file is the single source of truth for both.
enum BooksScenePayload {
    static func make(source: BookContentSource, state: TextbookState) throws -> Data {
        let catalogueData = try source.catalogueData()
        let catalogue = try JSONDecoder().decode(BookCatalogue.self, from: catalogueData)
        var lessons: [String: Any] = [:]
        for book in catalogue.books {
            for chapter in book.chapters {
                for ref in chapter.lessons where lessons[ref.file] == nil {
                    // A missing or unreadable lesson is left out; the scene reports it as a problem and carries on.
                    guard let data = try? source.lessonData(file: ref.file),
                          let object = try? JSONSerialization.jsonObject(with: data) else { continue }
                    lessons[ref.file] = object
                }
            }
        }
        var progress: [String: Any] = [:]
        var bookmarks: [String: String] = [:]
        for (bookID, item) in state.progress {
            var entry: [String: Any] = ["visitedPageIDs": Array(item.visitedPageIDs).sorted()]
            if let last = item.lastPageID { entry["lastPageID"] = last }
            progress[bookID] = entry
            if let mark = item.bookmarkPageID { bookmarks[bookID] = mark }
        }
        let payload: [String: Any] = [
            "catalogue": try JSONSerialization.jsonObject(with: catalogueData),
            "lessons": lessons,
            "preferences": [
                "recallLevel": state.preferences.recallLevel.rawValue,
                "textSize": state.preferences.textSize.rawValue,
                "sceneQuality": state.preferences.sceneQuality.rawValue,
            ] as [String: Any],
            "progress": progress,
            "bookmarks": bookmarks,
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    /// The call that hands the payload to the scene.
    static func loadScript(payload: Data, reducedMotion: Bool) -> String {
        "window.palabra.load(\(String(decoding: payload, as: UTF8.self)), {reducedMotion: \(reducedMotion)});"
    }
}
