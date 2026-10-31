import Foundation
import Observation
import UIKit

/// Connects the 3D scene to the rest of the app: keeps the scene's state for the HUD, saves what the scene reports into the
/// `BookShelf`, and sends the scene commands. The web view itself only provides `run` (evaluate a line of JavaScript).
@MainActor
@Observable
final class BooksSceneModel {
    private(set) var state = SceneState()
    private(set) var isReady = false
    private(set) var activeTerm: ActiveTerm?
    /// Set when the scene could not start; the shelf then falls back to reading as text.
    private(set) var failure: String?
    /// A short message about the last tap (a book without lessons, say). The HUD clears it.
    var notice: String?

    @ObservationIgnored private let shelf: BookShelf
    @ObservationIgnored var run: ((String) -> Void)?
    @ObservationIgnored private var queued: [SceneCommand] = []
    @ObservationIgnored private var started = false
    @ObservationIgnored private let selection = UISelectionFeedbackGenerator()
    @ObservationIgnored private let impact = UIImpactFeedbackGenerator(style: .light)

    init(shelf: BookShelf) {
        self.shelf = shelf
    }

    // MARK: Starting

    /// Called once the page has loaded: hands the scene the books and the reading state.
    func start(reducedMotion: Bool) {
        guard !started else { return }
        started = true
        do {
            let payload = try BooksScenePayload.make(source: shelf.source, state: shelf.state)
            run?(BooksScenePayload.loadScript(payload: payload, reducedMotion: reducedMotion))
        } catch {
            failure = "\(error)"
        }
    }

    func fail(_ message: String) {
        failure = message
    }

    // MARK: Commands

    func send(_ command: SceneCommand) {
        guard isReady else {
            // Appearance and insets only matter at their latest value; everything else is kept in order.
            queued.removeAll { $0.supersededBy(command) }
            queued.append(command)
            return
        }
        run?(command.javaScript)
    }

    // MARK: Messages from the scene

    func handle(_ message: SceneMessage) {
        switch message {
        case .ready:
            isReady = true
            let waiting = queued
            queued = []
            waiting.forEach { run?($0.javaScript) }
        case .state(let next):
            // A small tick when the page or the tool in hand changes, the way a real page would click into place.
            if next.isReading, state.isReading, next.basePageID != state.basePageID || next.page != state.page { selection.selectionChanged() }
            if next.tool != state.tool, next.tool != nil { impact.impactOccurred() }
            state = next
            if !next.isReading { activeTerm = nil }
        case .visit(let bookID, let pageID):
            shelf.recordVisit(bookID: bookID, pageID: pageID)
        case .term(let id, let term, let definition):
            activeTerm = ActiveTerm(id: id, term: term, definition: definition)
        case .termClose:
            activeTerm = nil
        case .bookmark(let bookID, let pageID):
            shelf.setBookmark(bookID: bookID, pageID: pageID)
        case .preference(let level, let size):
            if let level { shelf.preferences.recallLevel = level }
            if let size { shelf.preferences.textSize = size }
        case .empty:
            notice = "No lessons yet"
        case .error(let message):
            failure = message
        }
    }

    func closeTerm() {
        activeTerm = nil
        send(.closeTerm)
    }

    func progress(forBook id: String) -> BookShelf.Progress? {
        shelf.book(id: id).map { shelf.progress(for: $0) }
    }
}

private extension SceneCommand {
    /// True when `newer` makes this queued command pointless.
    func supersededBy(_ newer: SceneCommand) -> Bool {
        switch (self, newer) {
        case (.setAppearance, .setAppearance), (.setInsets, .setInsets): return true
        default: return false
        }
    }
}
