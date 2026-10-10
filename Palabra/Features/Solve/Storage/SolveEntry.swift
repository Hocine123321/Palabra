import Foundation
import SwiftData

/// A solved problem, kept so reopening it (or asking the same thing again) costs no API call.
/// Persisted names are append-only (see AGENTS.md).
@Model
final class SolveEntry {
    @Attribute(.unique) var id: UUID
    /// The normalized problem as sent to Wolfram|Alpha.
    var query: String
    /// `MathInputNormalizer.key(for:)`: the same question maps to the same key.
    var queryKey: String
    /// JSON of `SolveResult`.
    var resultData: Data
    var createdAt: Date
    var updatedAt: Date

    init(query: String, queryKey: String, resultData: Data, now: Date) {
        id = UUID()
        self.query = query
        self.queryKey = queryKey
        self.resultData = resultData
        createdAt = now
        updatedAt = now
    }

    var result: SolveResult? { try? JSONDecoder().decode(SolveResult.self, from: resultData) }
}
