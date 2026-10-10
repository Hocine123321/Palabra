import Foundation
import Observation

/// One review session over a fixed queue. Again/Hard answers that come due within
/// `requeueWindow` go to the back of the queue so they are seen again this session.
@MainActor
@Observable
final class ReviewViewModel {
    private(set) var queue: [Card]
    private(set) var isFlipped = false
    private(set) var answered = 0
    /// Answers that were not "Again".
    private(set) var correct = 0

    private let repository: CardRepository
    private let scheduler = SRSScheduler()
    private let now: () -> Date
    private let requeueWindow: TimeInterval = 15 * 60

    init(queue: [Card], repository: CardRepository, now: @escaping () -> Date = Date.init) {
        self.queue = queue
        self.repository = repository
        self.now = now
    }

    var current: Card? { queue.first }
    var remaining: Int { queue.count }
    var isFinished: Bool { queue.isEmpty }

    /// 0...1 over this session; a card that comes back counts again, so the bar never jumps backwards.
    var progress: Double {
        let total = answered + remaining
        return total == 0 ? 1 : Double(answered) / Double(total)
    }

    /// Share of answers that were not "Again", as a whole percent; nil before the first answer.
    var accuracyPercent: Int? {
        answered == 0 ? nil : Int((Double(correct) / Double(answered) * 100).rounded())
    }

    func flip() {
        guard current != nil else { return }
        isFlipped = true
    }

    /// Label for a grade button (time until the card is next due if that grade is chosen).
    func intervalLabel(for grade: SRSGrade) -> String {
        guard let card = current else { return "" }
        let delay = scheduler.previewDelays(card.srs, now: now())[grade] ?? 0
        return IntervalLabel.text(seconds: delay)
    }

    func grade(_ grade: SRSGrade) {
        guard let card = queue.first, isFlipped else { return }
        let moment = now()
        let updated = repository.record(cardID: card.id, grade: grade, now: moment)
        queue.removeFirst()
        answered += 1
        if grade != .again { correct += 1 }
        isFlipped = false
        if let updated, updated.due <= moment.addingTimeInterval(requeueWindow) {
            queue.append(card)
        }
    }
}
