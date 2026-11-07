import Foundation

/// A block flattened into plain editable fields, so one form can edit every block type. `block()` turns it back; empty
/// optional fields become nil, and rows left completely blank are dropped.
struct BlockDraft: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case heading, paragraph, list, keyPoint, quote, timeline, stats, comparison, causeEffect, process, definitions
        var id: String { rawValue }
    }

    var kind: Kind
    var title = ""
    var text = ""
    var label = ""
    var source = ""
    var corner = ""
    var level = 2
    var ordered = false
    var items: [String] = []
    var events: [TimelineEvent] = []
    var stats: [StatItem] = []
    var columns: [String] = []
    var rows: [ComparisonRow] = []
    var stages: [FlowStage] = []
    var steps: [ProcessStep] = []
    var definitions: [DefinitionItem] = []

    /// A blank block of a kind, with one empty row where the kind has rows, ready to fill in.
    init(kind: Kind) {
        self.kind = kind
        switch kind {
        case .list: items = [""]
        case .timeline: events = [TimelineEvent(date: "", title: "", detail: nil)]
        case .stats: stats = [StatItem(label: "", value: "", unit: nil, note: nil)]
        case .comparison: columns = ["", ""]; rows = [ComparisonRow(label: "", cells: ["", ""])]
        case .causeEffect: stages = [FlowStage(label: nil, nodes: [""]), FlowStage(label: nil, nodes: [""])]
        case .process: steps = [ProcessStep(title: "", detail: nil)]
        case .definitions: definitions = [DefinitionItem(id: nil, term: "", definition: "")]
        case .heading, .paragraph, .keyPoint, .quote: break
        }
    }

    /// `nil` for blocks that have no form (images, unknown types): those can only be moved or deleted.
    init?(_ block: Block) {
        switch block {
        case .heading(let text, let level): self.init(kind: .heading); self.text = text; self.level = level
        case .paragraph(let text): self.init(kind: .paragraph); self.text = text
        case .list(let title, let items, let ordered): self.init(kind: .list); self.title = title ?? ""; self.items = items; self.ordered = ordered
        case .keyPoint(let label, let text): self.init(kind: .keyPoint); self.label = label ?? ""; self.text = text
        case .quote(let text, let source): self.init(kind: .quote); self.text = text; self.source = source ?? ""
        case .timeline(let title, let events): self.init(kind: .timeline); self.title = title ?? ""; self.events = events
        case .stats(let title, let items): self.init(kind: .stats); self.title = title ?? ""; self.stats = items
        case .comparison(let title, let corner, let columns, let rows):
            self.init(kind: .comparison); self.title = title ?? ""; self.corner = corner ?? ""; self.columns = columns; self.rows = rows
        case .causeEffect(let title, let stages): self.init(kind: .causeEffect); self.title = title ?? ""; self.stages = stages
        case .process(let title, let steps): self.init(kind: .process); self.title = title ?? ""; self.steps = steps
        case .definitions(let title, let items): self.init(kind: .definitions); self.title = title ?? ""; self.definitions = items
        case .image, .unsupported: return nil
        }
    }

    /// The finished block, or nil when a required field is still empty (the form disables Save until it is not).
    func block() -> Block? {
        func opt(_ value: String) -> String? { value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value }
        func filled(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        switch kind {
        case .heading: return filled(text) ? .heading(text: text, level: min(max(level, 1), 3)) : nil
        case .paragraph: return filled(text) ? .paragraph(text) : nil
        case .list:
            let kept = items.filter(filled)
            return kept.isEmpty ? nil : .list(title: opt(title), items: kept, ordered: ordered)
        case .keyPoint: return filled(text) ? .keyPoint(label: opt(label), text: text) : nil
        case .quote: return filled(text) ? .quote(text: text, source: opt(source)) : nil
        case .timeline:
            let kept = events.filter { filled($0.date) || filled($0.title) }.map { TimelineEvent(date: $0.date, title: $0.title, detail: $0.detail.flatMap(opt)) }
            return kept.isEmpty ? nil : .timeline(title: opt(title), events: kept)
        case .stats:
            let kept = stats.filter { filled($0.label) || filled($0.value) }.map {
                StatItem(label: $0.label, value: $0.value, unit: $0.unit.flatMap(opt), note: $0.note.flatMap(opt))
            }
            return kept.isEmpty ? nil : .stats(title: opt(title), items: kept)
        case .comparison:
            let kept = rows.filter { filled($0.label) || $0.cells.contains(where: filled) }.map {
                ComparisonRow(label: $0.label, cells: Array(($0.cells + Array(repeating: "", count: max(0, columns.count - $0.cells.count))).prefix(columns.count)))
            }
            return columns.isEmpty || kept.isEmpty ? nil : .comparison(title: opt(title), corner: opt(corner), columns: columns, rows: kept)
        case .causeEffect:
            let kept = stages.map { FlowStage(label: $0.label.flatMap(opt), nodes: $0.nodes.filter(filled)) }.filter { !$0.nodes.isEmpty }
            return kept.count < 2 ? nil : .causeEffect(title: opt(title), stages: kept)
        case .process:
            let kept = steps.filter { filled($0.title) }.map { ProcessStep(title: $0.title, detail: $0.detail.flatMap(opt)) }
            return kept.isEmpty ? nil : .process(title: opt(title), steps: kept)
        case .definitions:
            let kept = definitions.filter { filled($0.term) && filled($0.definition) }.map {
                DefinitionItem(id: $0.id.flatMap(opt), term: $0.term, definition: $0.definition)
            }
            return kept.isEmpty ? nil : .definitions(title: opt(title), items: kept)
        }
    }
}
