import Foundation

/// One entry from Google's `models.list`, filtered to models that support `generateContent`.
struct AIModel: Identifiable, Codable, Equatable, Sendable {
    var id: String // e.g. "models/gemini-2.5-flash"
    var displayName: String
    var description: String?
    var inputTokenLimit: Int?
    var outputTokenLimit: Int?
}
