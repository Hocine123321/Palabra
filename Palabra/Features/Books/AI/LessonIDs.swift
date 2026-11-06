import Foundation

/// The app, never the AI, decides lesson and page ids: they become file names and the keys of saved reading progress.
enum LessonIDs {
    /// Gives `lesson` valid, unique ids. A revision (`previous` set) keeps the lesson id and the page id at the same
    /// position, so reading progress survives; extra pages get fresh ids that no earlier page ever had.
    static func assign(_ lesson: Lesson, previous: Lesson?, takenLessonIDs: Set<String>) -> Lesson {
        var result = lesson
        if let previous {
            result.id = previous.id
            result.version = previous.version + 1
        } else {
            result.id = uniqueLessonID(from: lesson.title, taken: takenLessonIDs)
            result.version = 1
        }
        var used = Set(previous?.pages.map(\.id) ?? [])
        var next = 1
        for index in result.pages.indices {
            if let old = previous?.pages[safe: index]?.id {
                result.pages[index].id = old
                continue
            }
            while used.contains("p\(next)") { next += 1 }
            result.pages[index].id = "p\(next)"
            used.insert("p\(next)")
        }
        return result
    }

    /// `colonial-movement` from "Colonial Movement"; titles with no Latin letters or digits (Arabic) become `lesson`, then `lesson-2`, …
    static func uniqueLessonID(from title: String, taken: Set<String>) -> String {
        var slug = ""
        for scalar in title.lowercased().unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                slug.unicodeScalars.append(scalar)
            } else if !slug.hasSuffix("-") {
                slug.append("-")
            }
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.isEmpty { slug = "lesson" }
        slug = String(slug.prefix(40)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard taken.contains(slug) else { return slug }
        var number = 2
        while taken.contains("\(slug)-\(number)") { number += 1 }
        return "\(slug)-\(number)"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
