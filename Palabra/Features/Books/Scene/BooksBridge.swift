import Foundation

// What the 3D desk reports to the app (`SceneMessage`, `SceneState`) and what the app can ask of it (`SceneCommand`). Plain data,
// so the HUD and the model can be tested without a renderer.

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
    /// Free view: the reader has moved or zoomed the camera away from the framed pose (native engine only).
    var viewMoved = false

    var isReading: Bool { mode == .reading || mode == .opening }

    /// The reading controls stay on screen while the book closes, and the menu controls and tab bar only come back once it
    /// is shut. (Swapping them at the tap changed the camera's view window and the layout in the middle of the move, which
    /// showed as a lurch with the page still full-screen.)
    var showsReadingChrome: Bool { isReading || mode == .closing }

    init() {}
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
    case setFreeView(Bool)
    case resetView
    case setEnhancements(Bool)
}
