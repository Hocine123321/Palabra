import Foundation

/// What the person wants to get: left to the AI, a page of blocks (table, chart, roadmap, checklist) or an interactive app.
enum ArtifactFormat: String, CaseIterable, Sendable {
    case auto, page, app

    /// A line placed before the request when the person chose a format; nothing for `auto`.
    var requestPrefix: String {
        switch self {
        case .auto: return ""
        case .page: return "FORMAT: build this as kind \"spec\" (a page of blocks), not an interactive app.\n\n"
        case .app: return "FORMAT: build this as kind \"app\" (an interactive app).\n\n"
        }
    }

    /// The request as sent to the AI. The prefix goes first so the request's own length cap never cuts it.
    func apply(to request: String) -> String { requestPrefix + request }
}

/// A starting point on the create page. `title`, `subtitle` are localization keys; `prompt` is what lands in the editor.
struct ArtifactIdea: Identifiable, Equatable, Sendable {
    let id: String
    let symbol: String
    let title: String
    let subtitle: String
    let prompt: String
    let format: ArtifactFormat

    static let all: [ArtifactIdea] = [
        ArtifactIdea(id: "progress", symbol: "chart.bar.fill", title: "Progress chart", subtitle: "Words you added each week",
                     prompt: "A chart of how many words I added each week, with a short note on my pace.", format: .page),
        ArtifactIdea(id: "roadmap", symbol: "map.fill", title: "Study roadmap", subtitle: "A plan you can follow",
                     prompt: "A four-week roadmap to get from my current level to holding a simple conversation in Spanish.", format: .page),
        ArtifactIdea(id: "checklist", symbol: "checklist", title: "Daily checklist", subtitle: "Tick things off each day",
                     prompt: "A daily Spanish study checklist I can tick off: review cards, add words, read, listen.", format: .page),
        ArtifactIdea(id: "table", symbol: "tablecells.fill", title: "Word table", subtitle: "Your latest words",
                     prompt: "A table of my most recent words with their translations.", format: .page),
        ArtifactIdea(id: "verbs", symbol: "text.book.closed.fill", title: "Verb cheat sheet", subtitle: "Present tense essentials",
                     prompt: "A conjugation cheat sheet for ser, estar, tener and ir in the present tense, with one example each.", format: .page),
        ArtifactIdea(id: "game", symbol: "gamecontroller.fill", title: "Practice game", subtitle: "Quiz yourself on your words",
                     prompt: "A practice app that quizzes me on words from my library with instant feedback and a running score.", format: .app),
    ]
}

/// Quick changes offered under a draft (and on the update screen). Each is a request on its own.
enum ArtifactQuickChange {
    static let all: [String] = ["Make it shorter", "Add more detail", "Use simpler words", "Make it more colorful"]
    /// The text sent for a chip: English, like every prompt.
    static func request(for key: String) -> String {
        switch key {
        case "Make it shorter": return "Make it shorter and more compact."
        case "Add more detail": return "Add more detail and one more useful section."
        case "Use simpler words": return "Use simpler words and shorter sentences."
        default: return "Make it more visual and colorful, using the theme colors."
        }
    }
}
