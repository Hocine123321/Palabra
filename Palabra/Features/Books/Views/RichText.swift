import SwiftUI

/// Lesson text with its light markup applied: highlighted terms open a definition, recall targets hide behind a
/// placeholder while Magnifying Glass is on, and `**bold**` is bold. Taps are handled through links, so the text keeps
/// normal wrapping and Dynamic Type, and VoiceOver finds the terms in its Links rotor.
struct RichText: View {
    static let termScheme = "palabra-term"
    static let recallScheme = "palabra-recall"

    let source: String
    let scope: PageScope
    /// Unique among the strings of one page. Recall targets in this string take their identity from it.
    let slot: String
    var font: Font?

    @Environment(\.bookPalette) private var palette
    @Environment(ReaderContext.self) private var context

    init(_ source: String, in scope: PageScope, slot: String, font: Font? = nil) {
        self.source = source
        self.scope = scope
        self.slot = slot
        self.font = font
    }

    var body: some View {
        Text(attributed)
            .font(font ?? palette.font(.body))
            .lineSpacing(6)
            .tint(palette.accent)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { handle($0) })
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for segment in InlineMarkup.parse(source) {
            switch segment {
            case .text(let text):
                result.append(AttributedString(text))
            case .bold(let text):
                var run = AttributedString(text)
                run.inlinePresentationIntent = .stronglyEmphasized
                result.append(run)
            case .term(let text, let id):
                var run = AttributedString(text)
                run.link = makeURL(scheme: Self.termScheme, value: id)
                run.underlineStyle = .single
                result.append(run)
            case .recall(let text, let level, let index):
                result.append(recallRun(text: text, level: level, index: index))
            }
        }
        return result
    }

    private func recallRun(text: String, level: RecallLevel, index: Int) -> AttributedString {
        let key = scope.key("\(slot).\(index)")
        let pageID = scope.page.id
        let url = makeURL(scheme: Self.recallScheme, value: key)
        if context.recall.isConcealed(target: level, key: key, pageID: pageID) {
            // The answer is not in the text at all (nothing to select, copy or read aloud), only a same-sized placeholder.
            var run = AttributedString(String(repeating: "•", count: min(max(text.count, 3), 28)))
            run.link = url
            run.backgroundColor = palette.accent.opacity(0.18)
            return run
        }
        var run = AttributedString(text)
        if context.recall.isEnabled && context.recall.level.conceals(level) {
            // Revealed by the person: highlighted, and tapping it hides it again.
            run.link = url
            run.backgroundColor = palette.accent.opacity(0.12)
        }
        return run
    }

    private func makeURL(scheme: String, value: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "p"
        components.path = "/" + value
        return components.url
    }

    private func handle(_ url: URL) -> OpenURLAction.Result {
        let value = String(url.path.dropFirst())
        if url.scheme == Self.termScheme {
            if let definition = scope.page.glossary[value] {
                context.activeTerm = ActiveTerm(id: value, term: definition.term, definition: definition.definition)
            }
            return .handled
        }
        if url.scheme == Self.recallScheme {
            context.recall.toggle(key: value, pageID: scope.page.id)
            return .handled
        }
        return .discarded
    }
}
