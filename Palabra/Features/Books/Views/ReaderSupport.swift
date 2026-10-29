import SwiftUI

/// A highlighted term the person tapped, shown in the definition card.
struct ActiveTerm: Equatable, Identifiable {
    let id: String
    let term: String
    let definition: String
}

/// State shared by everything on the reading screen: Magnifying Glass and the open definition. Not saved.
@MainActor
@Observable
final class ReaderContext {
    var recall: RecallState
    var activeTerm: ActiveTerm?

    init(level: RecallLevel = .essential) {
        recall = RecallState(level: level)
    }
}

/// Where a string sits on a page, so every recall target in it gets its own stable key.
struct PageScope {
    let page: BookPage

    func key(_ slot: String) -> String { RecallState.key(pageID: page.id, scope: slot) }
}

private struct BookPaletteKey: EnvironmentKey {
    static let defaultValue = Theme.Textbook.history
}

extension EnvironmentValues {
    /// The colours and type of the book being read.
    var bookPalette: Theme.Textbook.Palette {
        get { self[BookPaletteKey.self] }
        set { self[BookPaletteKey.self] = newValue }
    }
}

extension Theme.Textbook {
    static func palette(for subject: BookSubject) -> Palette {
        switch subject {
        case .history: return history
        case .geography: return geography
        }
    }
}

extension BookSubject {
    var titleKey: LocalizedStringKey {
        switch self {
        case .history: return "History"
        case .geography: return "Geography"
        }
    }

    var systemImage: String {
        switch self {
        case .history: return "building.columns"
        case .geography: return "globe.europe.africa"
        }
    }
}

extension RecallLevel {
    var titleKey: LocalizedStringKey {
        switch self {
        case .essential: return "Essential"
        case .keyFacts: return "Key facts"
        case .intensive: return "Intensive"
        }
    }
}

extension ReaderTextSize {
    var titleKey: LocalizedStringKey {
        switch self {
        case .smaller: return "Smaller"
        case .standard: return "Default"
        case .larger: return "Larger"
        case .largest: return "Largest"
        }
    }
}

extension View {
    /// A bordered surface for blocks that sit on the page (definition cards, diagram nodes, tiles).
    func bookCard(_ palette: Theme.Textbook.Palette, emphasized: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
        return padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(emphasized ? palette.accent.opacity(0.14) : palette.paperEdge.opacity(0.55), in: shape)
            .overlay(shape.stroke(emphasized ? palette.accent : palette.rule, lineWidth: 1))
    }
}
