import Foundation

/// One prepared lesson, decoded from a bundled JSON file (see docs/features/books.md for the format).
/// Lessons are written outside the app; the app only reads and shows them.
struct Lesson: Codable, Equatable, Identifiable {
    var id: String
    /// Bumped by the author when the lesson is rewritten. Reading progress is keyed by page id, so it survives.
    var version: Int
    var title: String
    var summary: String?
    /// Glossary terms that `{{text|id}}` can point at. Definition cards with an `id` count too (see `glossary`).
    var terms: [String: TermDefinition]
    var pages: [LessonPage]
    /// What the author could not read or had to decide while copying the lesson from the source. Shown in the table of contents.
    var transcriptionNotes: [String]

    init(
        id: String,
        version: Int = 1,
        title: String,
        summary: String? = nil,
        terms: [String: TermDefinition] = [:],
        pages: [LessonPage],
        transcriptionNotes: [String] = []
    ) {
        self.id = id
        self.version = version
        self.title = title
        self.summary = summary
        self.terms = terms
        self.pages = pages
        self.transcriptionNotes = transcriptionNotes
    }

    private enum CodingKeys: String, CodingKey {
        case id, version, title, summary, terms, pages, transcriptionNotes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        terms = try c.decodeIfPresent([String: TermDefinition].self, forKey: .terms) ?? [:]
        pages = try c.decode([LessonPage].self, forKey: .pages)
        transcriptionNotes = try c.decodeIfPresent([String].self, forKey: .transcriptionNotes) ?? []
    }

    /// Every term a highlighted word can open: the lesson's own glossary plus every definition card that has an `id`.
    var glossary: [String: TermDefinition] {
        var result = terms
        for page in pages {
            for block in page.blocks {
                guard case .definitions(_, let items) = block else { continue }
                for item in items {
                    guard let id = item.id, result[id] == nil else { continue }
                    result[id] = TermDefinition(
                        term: InlineMarkup.plainText(item.term),
                        definition: InlineMarkup.plainText(item.definition)
                    )
                }
            }
        }
        return result
    }
}

struct TermDefinition: Codable, Equatable {
    var term: String
    var definition: String
}

struct LessonPage: Codable, Equatable, Identifiable {
    /// Unique inside the lesson, never contains "/". Reading progress is saved under it, so do not rename it later.
    var id: String
    var title: String
    /// Optional line under the title, such as the date the page was written.
    var dateLabel: String?
    var blocks: [Block]

    init(id: String, title: String, dateLabel: String? = nil, blocks: [Block]) {
        self.id = id
        self.title = title
        self.dateLabel = dateLabel
        self.blocks = blocks
    }
}

struct TimelineEvent: Codable, Equatable {
    var date: String
    var title: String
    var detail: String?
}

struct StatItem: Codable, Equatable {
    var label: String
    var value: String
    var unit: String?
    var note: String?
}

struct ComparisonRow: Codable, Equatable {
    var label: String
    var cells: [String]
}

struct FlowStage: Codable, Equatable {
    var label: String?
    var nodes: [String]
}

struct ProcessStep: Codable, Equatable {
    var title: String
    var detail: String?
}

struct DefinitionItem: Codable, Equatable {
    /// With an id, the term becomes available to `{{text|id}}` anywhere in the lesson.
    var id: String?
    var term: String
    var definition: String
}

struct ImagePanel: Codable, Equatable {
    /// Name of an image in the app's asset catalog.
    var name: String
    var caption: String?
    /// What the picture shows, for VoiceOver.
    var alt: String
    /// `"map"` or `"illustration"`; only changes the frame.
    var style: String?
}

/// One building block of a page. Unknown block types decode as `.unsupported`, so a lesson written for a newer app
/// still opens (that block shows a short notice instead).
enum Block: Codable, Equatable {
    case heading(text: String, level: Int)
    case paragraph(String)
    case list(title: String?, items: [String], ordered: Bool)
    case keyPoint(label: String?, text: String)
    case quote(text: String, source: String?)
    case timeline(title: String?, events: [TimelineEvent])
    case stats(title: String?, items: [StatItem])
    case comparison(title: String?, corner: String?, columns: [String], rows: [ComparisonRow])
    case causeEffect(title: String?, stages: [FlowStage])
    case process(title: String?, steps: [ProcessStep])
    case definitions(title: String?, items: [DefinitionItem])
    case image(ImagePanel)
    case unsupported(type: String)

    private enum Keys: String, CodingKey {
        case type, text, level, title, label, source, items, ordered, events, stats, columns, corner, rows, stages, steps, definitions
        case image, caption, alt, style
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let type = try c.decode(String.self, forKey: .type)
        let title = try c.decodeIfPresent(String.self, forKey: .title)
        switch type {
        case "heading":
            self = .heading(text: try c.decode(String.self, forKey: .text), level: try c.decodeIfPresent(Int.self, forKey: .level) ?? 2)
        case "paragraph":
            self = .paragraph(try c.decode(String.self, forKey: .text))
        case "list":
            self = .list(
                title: title,
                items: try c.decode([String].self, forKey: .items),
                ordered: try c.decodeIfPresent(Bool.self, forKey: .ordered) ?? false
            )
        case "keyPoint":
            self = .keyPoint(label: try c.decodeIfPresent(String.self, forKey: .label), text: try c.decode(String.self, forKey: .text))
        case "quote":
            self = .quote(text: try c.decode(String.self, forKey: .text), source: try c.decodeIfPresent(String.self, forKey: .source))
        case "timeline":
            self = .timeline(title: title, events: try c.decode([TimelineEvent].self, forKey: .events))
        case "stats":
            self = .stats(title: title, items: try c.decode([StatItem].self, forKey: .stats))
        case "comparison":
            self = .comparison(
                title: title,
                corner: try c.decodeIfPresent(String.self, forKey: .corner),
                columns: try c.decode([String].self, forKey: .columns),
                rows: try c.decode([ComparisonRow].self, forKey: .rows)
            )
        case "causeEffect":
            self = .causeEffect(title: title, stages: try c.decode([FlowStage].self, forKey: .stages))
        case "process":
            self = .process(title: title, steps: try c.decode([ProcessStep].self, forKey: .steps))
        case "definitions":
            self = .definitions(title: title, items: try c.decode([DefinitionItem].self, forKey: .definitions))
        case "image":
            self = .image(ImagePanel(
                name: try c.decode(String.self, forKey: .image),
                caption: try c.decodeIfPresent(String.self, forKey: .caption),
                alt: try c.decodeIfPresent(String.self, forKey: .alt) ?? "",
                style: try c.decodeIfPresent(String.self, forKey: .style)
            ))
        default:
            self = .unsupported(type: type)
        }
    }

    /// Every string in the block that goes through the inline markup (for validation and plain-text use).
    var texts: [String] {
        var out: [String] = []
        func add(_ value: String?) { if let value { out.append(value) } }
        switch self {
        case .heading(let text, _):
            add(text)
        case .paragraph(let text):
            add(text)
        case .list(let title, let items, _):
            add(title)
            out += items
        case .keyPoint(let label, let text):
            add(label)
            add(text)
        case .quote(let text, let source):
            add(text)
            add(source)
        case .timeline(let title, let events):
            add(title)
            for event in events {
                add(event.date)
                add(event.title)
                add(event.detail)
            }
        case .stats(let title, let items):
            add(title)
            for item in items {
                add(item.label)
                add(item.value)
                add(item.unit)
                add(item.note)
            }
        case .comparison(let title, let corner, let columns, let rows):
            add(title)
            add(corner)
            out += columns
            for row in rows {
                add(row.label)
                out += row.cells
            }
        case .causeEffect(let title, let stages):
            add(title)
            for stage in stages {
                add(stage.label)
                out += stage.nodes
            }
        case .process(let title, let steps):
            add(title)
            for step in steps {
                add(step.title)
                add(step.detail)
            }
        case .definitions(let title, let items):
            add(title)
            for item in items {
                add(item.term)
                add(item.definition)
            }
        case .image(let panel):
            add(panel.caption)
        case .unsupported:
            break
        }
        return out
    }
}

// MARK: - Writing a lesson back out (same keys the decoder reads, see docs/features/books.md)

extension Block {
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .heading(let text, let level):
            try c.encode("heading", forKey: .type)
            try c.encode(text, forKey: .text)
            try c.encode(level, forKey: .level)
        case .paragraph(let text):
            try c.encode("paragraph", forKey: .type)
            try c.encode(text, forKey: .text)
        case .list(let title, let items, let ordered):
            try c.encode("list", forKey: .type)
            try c.encodeIfPresent(title, forKey: .title)
            try c.encode(items, forKey: .items)
            try c.encode(ordered, forKey: .ordered)
        case .keyPoint(let label, let text):
            try c.encode("keyPoint", forKey: .type)
            try c.encodeIfPresent(label, forKey: .label)
            try c.encode(text, forKey: .text)
        case .quote(let text, let source):
            try c.encode("quote", forKey: .type)
            try c.encode(text, forKey: .text)
            try c.encodeIfPresent(source, forKey: .source)
        case .timeline(let title, let events):
            try c.encode("timeline", forKey: .type)
            try c.encodeIfPresent(title, forKey: .title)
            try c.encode(events, forKey: .events)
        case .stats(let title, let items):
            try c.encode("stats", forKey: .type)
            try c.encodeIfPresent(title, forKey: .title)
            try c.encode(items, forKey: .stats)
        case .comparison(let title, let corner, let columns, let rows):
            try c.encode("comparison", forKey: .type)
            try c.encodeIfPresent(title, forKey: .title)
            try c.encodeIfPresent(corner, forKey: .corner)
            try c.encode(columns, forKey: .columns)
            try c.encode(rows, forKey: .rows)
        case .causeEffect(let title, let stages):
            try c.encode("causeEffect", forKey: .type)
            try c.encodeIfPresent(title, forKey: .title)
            try c.encode(stages, forKey: .stages)
        case .process(let title, let steps):
            try c.encode("process", forKey: .type)
            try c.encodeIfPresent(title, forKey: .title)
            try c.encode(steps, forKey: .steps)
        case .definitions(let title, let items):
            try c.encode("definitions", forKey: .type)
            try c.encodeIfPresent(title, forKey: .title)
            try c.encode(items, forKey: .definitions)
        case .image(let panel):
            try c.encode("image", forKey: .type)
            try c.encode(panel.name, forKey: .image)
            try c.encodeIfPresent(panel.caption, forKey: .caption)
            try c.encode(panel.alt, forKey: .alt)
            try c.encodeIfPresent(panel.style, forKey: .style)
        case .unsupported(let type):
            try c.encode(type, forKey: .type)
        }
    }
}

enum LessonCoding {
    /// A lesson as the JSON file the loader reads: readable, stable key order.
    static func encode(_ lesson: Lesson) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(lesson)
    }

    static func decode(_ data: Data) throws -> Lesson {
        try JSONDecoder().decode(Lesson.self, from: data)
    }
}
