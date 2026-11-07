import Foundation

extension BookShelf {
    /// Applies an edit to a stored lesson and saves it where it already is in the catalogue. An edit that changes nothing
    /// succeeds without writing. Returns false, changing nothing, when the lesson is not editable or the result would not
    /// pass `LessonValidator`.
    @discardableResult
    func editLesson(id: String, _ change: (Lesson) -> Lesson) -> Bool {
        guard let lesson = lesson(id: id), let place = lessonStore?.location(ofLesson: id) else { return false }
        let changed = change(lesson)
        guard changed != lesson else { return true }
        guard LessonValidator.problems(in: changed).isEmpty else { return false }
        do {
            try saveLesson(changed, bookID: place.bookID, chapterID: place.chapterID)
            return true
        } catch {
            return false
        }
    }
}
