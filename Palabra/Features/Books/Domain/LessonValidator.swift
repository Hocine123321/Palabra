import Foundation

/// Checks a lesson the way an author would want it checked. The loader reports these (it still shows the lesson),
/// the unit tests fail on any problem in the bundled lessons, and `scripts/validate-lessons.py` applies the same rules in CI.
enum LessonValidator {
    static func problems(in lesson: Lesson) -> [String] {
        var out: [String] = []
        if lesson.id.isEmpty || lesson.id.contains("/") { out.append("lesson id must not be empty or contain \"/\"") }
        if lesson.title.isEmpty { out.append("lesson has no title") }
        if lesson.pages.isEmpty { out.append("lesson has no pages") }

        let glossary = lesson.glossary
        var seenPages = Set<String>()
        for page in lesson.pages {
            let at = "page \(page.id)"
            if page.id.isEmpty || page.id.contains("/") { out.append("\(at): page id must not be empty or contain \"/\"") }
            if !seenPages.insert(page.id).inserted { out.append("\(at): duplicate page id") }
            if page.title.isEmpty { out.append("\(at): no title") }
            if page.blocks.isEmpty { out.append("\(at): no blocks") }
            for (number, block) in page.blocks.enumerated() {
                let location = "\(at), block \(number + 1)"
                out += structureProblems(block).map { "\(location): \($0)" }
                for text in block.texts {
                    let scan = InlineMarkup.scan(text)
                    out += scan.problems.map { "\(location): \($0)" }
                    for segment in scan.segments {
                        if case .term(_, let id) = segment, glossary[id] == nil {
                            out.append("\(location): unknown term id \"\(id)\"")
                        }
                    }
                }
            }
        }
        return out
    }

    private static func structureProblems(_ block: Block) -> [String] {
        switch block {
        case .heading(let text, let level):
            var out: [String] = []
            if text.isEmpty { out.append("empty heading") }
            if !(1...3).contains(level) { out.append("heading level must be 1, 2 or 3") }
            return out
        case .paragraph(let text):
            return text.isEmpty ? ["empty paragraph"] : []
        case .list(_, let items, _):
            return items.isEmpty ? ["list has no items"] : []
        case .keyPoint(_, let text):
            return text.isEmpty ? ["empty key point"] : []
        case .quote(let text, _):
            return text.isEmpty ? ["empty quote"] : []
        case .timeline(_, let events):
            return events.isEmpty ? ["timeline has no events"] : []
        case .stats(_, let items):
            return items.isEmpty ? ["stats has no items"] : []
        case .comparison(_, _, let columns, let rows):
            var out: [String] = []
            if columns.isEmpty { out.append("comparison has no columns") }
            if rows.isEmpty { out.append("comparison has no rows") }
            for row in rows where row.cells.count != columns.count {
                out.append("comparison row \"\(InlineMarkup.plainText(row.label))\" has \(row.cells.count) cells for \(columns.count) columns")
            }
            return out
        case .causeEffect(_, let stages):
            var out: [String] = []
            if stages.count < 2 { out.append("cause-and-effect needs at least two stages") }
            if stages.contains(where: { $0.nodes.isEmpty }) { out.append("a stage has no nodes") }
            return out
        case .process(_, let steps):
            return steps.isEmpty ? ["process has no steps"] : []
        case .definitions(_, let items):
            return items.isEmpty ? ["definitions has no items"] : []
        case .image(let panel):
            var out: [String] = []
            if panel.name.isEmpty { out.append("image has no name") }
            if panel.alt.isEmpty { out.append("image \"\(panel.name)\" has no alt text") }
            return out
        case .unsupported(let type):
            return ["unknown block type \"\(type)\""]
        }
    }
}
