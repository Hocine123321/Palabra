import Foundation
import SwiftData

/// One add-word or regenerate request made while offline, waiting to be
/// sent to the AI once the connection returns. Persisted (unlike
/// `AddWordFlow`, which is session-only) so the queue survives the app
/// being relaunched — e.g. words typed in airplane mode on a flight.
@Model
final class WordQueueItem {
    enum Status: String, Codable {
        case pending
        case processing
        /// Failed for a reason being online again won't fix (a setup
        /// problem, or an error that isn't retryable). Stays until the
        /// person retries or removes it.
        case failed
    }

    @Attribute(.unique) var id: UUID
    var inputWord: String
    /// Set only for a regenerate request; `nil` means a new word.
    var existingWordID: UUID?
    var existingCreatedAt: Date?
    /// The AI-output language in effect when this was queued, so a later
    /// change in Settings doesn't change what gets generated.
    var languageRaw: String
    var createdAt: Date
    var statusRaw: String
    /// Failed attempts since the last time this item was last `.pending`
    /// for a reason other than being offline — being offline doesn't count.
    var attempts: Int
    /// Set when `status == .failed`, cleared otherwise.
    var lastErrorMessage: String?

    init(inputWord: String, mode: AddWordFlow.Mode, language: SupportedLanguage, createdAt: Date = Date()) {
        id = UUID()
        self.inputWord = inputWord
        switch mode {
        case .new:
            existingWordID = nil
            existingCreatedAt = nil
        case .regenerate(let existingID, let existingCreatedAt):
            existingWordID = existingID
            self.existingCreatedAt = existingCreatedAt
        }
        languageRaw = language.rawValue
        self.createdAt = createdAt
        statusRaw = Status.pending.rawValue
        attempts = 0
        lastErrorMessage = nil
    }

    var status: Status {
        get { Status(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var language: SupportedLanguage {
        SupportedLanguage(rawValue: languageRaw) ?? .english
    }

    var mode: AddWordFlow.Mode {
        if let existingWordID, let existingCreatedAt {
            return .regenerate(existingID: existingWordID, existingCreatedAt: existingCreatedAt)
        }
        return .new
    }
}
