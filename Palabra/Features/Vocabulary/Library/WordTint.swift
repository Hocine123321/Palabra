import SwiftUI

/// How the library tiles, rows and the headword card are coloured when a word is not a colour.
enum WordTintMode: String, CaseIterable, Identifiable {
    /// A stable colour per word (the original look).
    case mixed
    /// One colour per part of speech, so nouns, verbs and adjectives read at a glance.
    case partOfSpeech
    /// Neutral stone everywhere except colour words.
    case calm

    var id: String { rawValue }

    /// A localization key.
    var title: String {
        switch self {
        case .mixed: return "Mixed"
        case .partOfSpeech: return "By Part of Speech"
        case .calm: return "Colour Words Only"
        }
    }
}

/// UserDefaults keys behind `WordTintSettings` (the same keys `@AppStorage` uses in Settings).
enum WordTintKeys {
    static let mode = "wordTintMode"
    static let colorWords = "colorWordTints"
}

/// Which tint a word gets. The decision (`source`) is pure and tested; `color` only paints it.
enum WordTint {
    enum Source: Equatable {
        case colorWord(ColorWordMatch)
        case partOfSpeech(String)
        case word(String)
        case neutral
    }

    static func source(key: String, partOfSpeech: String, mode: WordTintMode, colorWords: Bool) -> Source {
        if colorWords, let match = ColorWords.match(key) { return .colorWord(match) }
        switch mode {
        case .mixed:
            return .word(key)
        case .partOfSpeech:
            let pos = WordKey.search(partOfSpeech)
            return pos.isEmpty ? .word(key) : .partOfSpeech(pos)
        case .calm:
            return .neutral
        }
    }

    static func color(for source: Source) -> Color {
        switch source {
        case .colorWord(let match): return Theme.tint(for: match.family, shade: match.shade)
        case .partOfSpeech(let pos): return Theme.tint(for: "pos|" + pos)
        case .word(let key): return Theme.tint(for: key)
        case .neutral: return Theme.tileTints[5]
        }
    }

    /// A flashcard front's tint: only a colour word gets one (nil otherwise), and only while the setting is on.
    /// Study asks this through a closure the app injects, so it never sees vocabulary types.
    static func cardTint(front: String, defaults: UserDefaults = .standard) -> Color? {
        guard (defaults.object(forKey: WordTintKeys.colorWords) as? Bool) ?? true,
              let match = ColorWords.match(front) else { return nil }
        return Theme.tint(for: match.family, shade: match.shade)
    }
}

/// Reads the two tint settings live, so a change in Settings repaints the library at once.
struct WordTintSettings: DynamicProperty {
    @AppStorage(WordTintKeys.mode) private var modeRaw = WordTintMode.mixed.rawValue
    @AppStorage(WordTintKeys.colorWords) private var colorWords = true

    func color(key: String, partOfSpeech: String) -> Color {
        WordTint.color(for: WordTint.source(
            key: key,
            partOfSpeech: partOfSpeech,
            mode: WordTintMode(rawValue: modeRaw) ?? .mixed,
            colorWords: colorWords
        ))
    }
}
