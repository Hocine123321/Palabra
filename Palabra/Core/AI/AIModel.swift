import Foundation

/// One entry from Google's `models.list`, filtered to models that support `generateContent`.
struct AIModel: Identifiable, Codable, Equatable, Sendable {
    var id: String // e.g. "models/gemini-2.5-flash"
    var displayName: String
    var description: String?
    var inputTokenLimit: Int?
    var outputTokenLimit: Int?
    /// Who serves it. Nil means Gemini (models saved before providers existed have no value).
    var provider: AIProvider?
    /// Whether it can read a photo. Nil means unknown (treated as yes: the request itself decides).
    var acceptsImages: Bool?
}
