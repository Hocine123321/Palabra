import SwiftUI

@MainActor
@Observable
final class Router {
    enum Destination: Hashable {
        case settings
        case wordDetail(UUID)
        case studyPlanner
        case flashcardReview(subject: String?)
        case quizGenerator
    }

    var path = NavigationPath()

    func openSettings() { path.append(Destination.settings) }
    func openWord(_ id: UUID) { path.append(Destination.wordDetail(id)) }
    func openStudyPlanner() { path.append(Destination.studyPlanner) }
    func openFlashcardReview(subject: String?) { path.append(Destination.flashcardReview(subject: subject)) }
    func openQuizGenerator() { path.append(Destination.quizGenerator) }
}
