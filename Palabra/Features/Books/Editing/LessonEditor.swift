import Foundation

/// Edits to a lesson as plain value operations. Each returns a new lesson, or the lesson unchanged when the edit would
/// leave it invalid (the last block of a page, the last page of a lesson, an empty title), so an edit can never break a lesson.
/// Page ids never change, so saved reading progress survives every edit.
enum LessonEditor {
    static func replaceBlock(_ lesson: Lesson, pageID: String, index: Int, with block: Block) -> Lesson {
        editPage(lesson, pageID) { page in
            guard page.blocks.indices.contains(index) else { return }
            page.blocks[index] = block
        }
    }

    static func insertBlock(_ lesson: Lesson, pageID: String, at index: Int, block: Block) -> Lesson {
        editPage(lesson, pageID) { page in
            page.blocks.insert(block, at: min(max(index, 0), page.blocks.count))
        }
    }

    /// The last block of a page cannot be deleted (delete the page instead).
    static func deleteBlock(_ lesson: Lesson, pageID: String, index: Int) -> Lesson {
        editPage(lesson, pageID) { page in
            guard page.blocks.count > 1, page.blocks.indices.contains(index) else { return }
            page.blocks.remove(at: index)
        }
    }

    static func moveBlock(_ lesson: Lesson, pageID: String, from: Int, to: Int) -> Lesson {
        editPage(lesson, pageID) { page in
            guard page.blocks.indices.contains(from), page.blocks.indices.contains(to), from != to else { return }
            page.blocks.insert(page.blocks.remove(at: from), at: to)
        }
    }

    static func setPageTitle(_ lesson: Lesson, pageID: String, title: String) -> Lesson {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return lesson }
        return editPage(lesson, pageID) { $0.title = trimmed }
    }

    static func setDateLabel(_ lesson: Lesson, pageID: String, label: String?) -> Lesson {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        return editPage(lesson, pageID) { $0.dateLabel = (trimmed?.isEmpty ?? true) ? nil : trimmed }
    }

    static func renameLesson(_ lesson: Lesson, title: String) -> Lesson {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return lesson }
        var result = lesson
        result.title = trimmed
        return result
    }

    /// A new page with a placeholder paragraph, after `pageID` (or at the end). Its id is never one the lesson has used:
    /// one more than the largest `p<number>` id present.
    static func addPage(_ lesson: Lesson, after pageID: String?, title: String) -> (lesson: Lesson, pageID: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let highest = lesson.pages.compactMap { page -> Int? in
            guard page.id.hasPrefix("p") else { return nil }
            return Int(page.id.dropFirst())
        }.max() ?? lesson.pages.count
        let id = "p\(highest + 1)"
        var result = lesson
        let page = LessonPage(id: id, title: trimmed.isEmpty ? "…" : trimmed, blocks: [.paragraph("…")])
        if let pageID, let at = result.pages.firstIndex(where: { $0.id == pageID }) {
            result.pages.insert(page, at: at + 1)
        } else {
            result.pages.append(page)
        }
        return (result, id)
    }

    /// The last page of a lesson cannot be deleted (delete the lesson instead).
    static func deletePage(_ lesson: Lesson, pageID: String) -> Lesson {
        guard lesson.pages.count > 1, let at = lesson.pages.firstIndex(where: { $0.id == pageID }) else { return lesson }
        var result = lesson
        result.pages.remove(at: at)
        return result
    }

    static func movePage(_ lesson: Lesson, pageID: String, by offset: Int) -> Lesson {
        guard let from = lesson.pages.firstIndex(where: { $0.id == pageID }) else { return lesson }
        let to = from + offset
        guard lesson.pages.indices.contains(to), to != from else { return lesson }
        var result = lesson
        result.pages.insert(result.pages.remove(at: from), at: to)
        return result
    }

    private static func editPage(_ lesson: Lesson, _ pageID: String, _ change: (inout LessonPage) -> Void) -> Lesson {
        guard let at = lesson.pages.firstIndex(where: { $0.id == pageID }) else { return lesson }
        var result = lesson
        change(&result.pages[at])
        return result
    }
}
