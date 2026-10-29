import Foundation

/// How much Magnifying Glass hides. A level hides its own targets and those of every easier level.
enum RecallLevel: Int, CaseIterable, Codable, Identifiable, Sendable {
    /// Dates, figures and measurements.
    case essential = 1
    /// Also important names, terms and selected facts.
    case keyFacts = 2
    /// A broader set of lesson-specific targets.
    case intensive = 3

    var id: Int { rawValue }

    /// The one-letter tag used inside lesson text: `[[1815|e]]`.
    var tag: String {
        switch self {
        case .essential: return "e"
        case .keyFacts: return "k"
        case .intensive: return "i"
        }
    }

    init?(tag: String) {
        guard let match = RecallLevel.allCases.first(where: { $0.tag == tag }) else { return nil }
        self = match
    }

    /// True when a person who picked `self` should have a target of level `target` hidden.
    func conceals(_ target: RecallLevel) -> Bool { target.rawValue <= rawValue }
}

/// One piece of a lesson string after its light markup is read.
///
/// Markup (the only formatting lesson text has):
/// - `{{text|term-id}}`  a highlighted term; tapping it shows the definition registered under `term-id`.
/// - `[[text|e]]`        a recall target for Magnifying Glass; `e`, `k` or `i` is its level (see `RecallLevel`).
/// - `**text**`          bold.
enum InlineSegment: Equatable, Sendable {
    case text(String)
    case bold(String)
    case term(text: String, id: String)
    /// `index` counts recall targets within the one string, so each has a stable identity.
    case recall(text: String, level: RecallLevel, index: Int)
}

struct InlineScan: Equatable, Sendable {
    var segments: [InlineSegment]
    /// Authoring mistakes found while reading (unclosed markers, unknown level tags). The text still renders.
    var problems: [String]
}

enum InlineMarkup {
    private struct Rule {
        let open: String
        let close: String
    }

    private static let rules = [
        Rule(open: "{{", close: "}}"),
        Rule(open: "[[", close: "]]"),
        Rule(open: "**", close: "**")
    ]

    static func parse(_ source: String) -> [InlineSegment] { scan(source).segments }

    /// The text with every marker removed.
    static func plainText(_ source: String) -> String {
        parse(source).map { segment -> String in
            switch segment {
            case .text(let text): return text
            case .bold(let text): return text
            case .term(let text, _): return text
            case .recall(let text, _, _): return text
            }
        }.joined()
    }

    static func scan(_ source: String) -> InlineScan {
        var segments: [InlineSegment] = []
        var problems: [String] = []
        var buffer = ""
        var recallIndex = 0
        var index = source.startIndex

        outer: while index < source.endIndex {
            let tail = source[index...]
            for rule in rules where tail.hasPrefix(rule.open) {
                let innerStart = source.index(index, offsetBy: rule.open.count)
                guard let close = source.range(of: rule.close, range: innerStart..<source.endIndex) else {
                    problems.append("unclosed \(rule.open)")
                    continue
                }
                let inner = String(source[innerStart..<close.lowerBound])
                if let segment = makeSegment(open: rule.open, inner: inner, recallIndex: &recallIndex, problems: &problems) {
                    if !buffer.isEmpty {
                        segments.append(.text(buffer))
                        buffer = ""
                    }
                    segments.append(segment)
                    index = close.upperBound
                    continue outer
                }
            }
            buffer.append(source[index])
            index = source.index(after: index)
        }
        if !buffer.isEmpty { segments.append(.text(buffer)) }
        return InlineScan(segments: segments, problems: problems)
    }

    private static func makeSegment(open: String, inner: String, recallIndex: inout Int, problems: inout [String]) -> InlineSegment? {
        switch open {
        case "{{":
            guard let bar = inner.lastIndex(of: "|") else {
                problems.append("term without an id: \(inner)")
                return nil
            }
            let text = String(inner[..<bar])
            let id = String(inner[inner.index(after: bar)...]).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !id.isEmpty else {
                problems.append("term with an empty text or id: \(inner)")
                return nil
            }
            return .term(text: text, id: id)
        case "[[":
            var text = inner
            var level = RecallLevel.keyFacts
            if let bar = inner.lastIndex(of: "|") {
                let tag = String(inner[inner.index(after: bar)...]).trimmingCharacters(in: .whitespaces)
                if let parsed = RecallLevel(tag: tag) {
                    level = parsed
                    text = String(inner[..<bar])
                } else {
                    problems.append("unknown recall level \"\(tag)\" (use e, k or i)")
                }
            }
            guard !text.isEmpty else { return nil }
            let number = recallIndex
            recallIndex += 1
            return .recall(text: text, level: level, index: number)
        case "**":
            return inner.isEmpty ? nil : .bold(inner)
        default:
            return nil
        }
    }
}
