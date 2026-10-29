import Foundation

/// The state of Magnifying Glass for one reading session. Nothing here is saved: turning the mode on starts with every
/// answer hidden, and so does picking another level.
struct RecallState: Equatable {
    private(set) var isEnabled = false
    private(set) var level: RecallLevel = .essential
    /// Pages whose answers were all revealed at once.
    private(set) var revealedPages: Set<String> = []
    /// Answers the person tapped, which win over the page-wide choice. Keys start with "<page id>#".
    private(set) var overrides: [String: Bool] = [:]

    init(level: RecallLevel = .essential) {
        self.level = level
    }

    static func key(pageID: String, scope: String) -> String { "\(pageID)#\(scope)" }

    mutating func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        clearReveals()
    }

    mutating func setLevel(_ newLevel: RecallLevel) {
        guard newLevel != level else { return }
        level = newLevel
        clearReveals()
    }

    mutating func clearReveals() {
        revealedPages = []
        overrides = [:]
    }

    /// Whether a target of `target` level, with this key on this page, is hidden right now.
    func isConcealed(target: RecallLevel, key: String, pageID: String) -> Bool {
        guard isEnabled, level.conceals(target) else { return false }
        return !isRevealed(key: key, pageID: pageID)
    }

    /// Whether a target that the current level hides is currently shown.
    func isRevealed(key: String, pageID: String) -> Bool {
        overrides[key] ?? revealedPages.contains(pageID)
    }

    mutating func toggle(key: String, pageID: String) {
        overrides[key] = !isRevealed(key: key, pageID: pageID)
    }

    mutating func revealPage(_ pageID: String) {
        revealedPages.insert(pageID)
        dropOverrides(onPage: pageID)
    }

    mutating func hidePage(_ pageID: String) {
        revealedPages.remove(pageID)
        dropOverrides(onPage: pageID)
    }

    func isPageRevealed(_ pageID: String) -> Bool { revealedPages.contains(pageID) }

    private mutating func dropOverrides(onPage pageID: String) {
        let prefix = pageID + "#"
        overrides = overrides.filter { !$0.key.hasPrefix(prefix) }
    }
}
