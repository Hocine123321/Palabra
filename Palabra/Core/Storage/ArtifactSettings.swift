import Foundation

/// How big an artifact the AI may write, in KB. The hard ceiling is what storage accepts.
enum ArtifactOutputBudget {
    static let minKB = 8
    static let maxKB = 128
    static let stepKB = 4
    /// The user's decision: the default maximum output is 128 KB (131,072 bytes). It is a ceiling, not a target.
    static let defaultKB = 128
    /// Roughly how many UTF-8 bytes of HTML or JSON one output token holds (code is dense: about 3).
    static let bytesPerToken = 3.0
    /// Headroom for the envelope (title, requests, markers) and for the model going over the stated size.
    static let tokenHeadroom = 1_024

    static func clampedKB(_ kb: Int) -> Int { min(maxKB, max(minKB, kb)) }

    static func bytes(forKB kb: Int) -> Int { clampedKB(kb) * 1024 }

    /// The output tokens a reply of `kb` KB needs.
    static func tokens(forKB kb: Int) -> Int {
        Int((Double(bytes(forKB: kb)) / bytesPerToken).rounded(.up)) + tokenHeadroom
    }

    /// The largest size (KB) a model that can write `tokenLimit` tokens can reach.
    static func reachableKB(tokenLimit: Int) -> Int {
        let usable = max(0, tokenLimit - tokenHeadroom)
        return Int((Double(usable) * bytesPerToken / 1024).rounded(.down))
    }

    /// `@TaskLocal` carrier: `GeminiClient` reads it so the `AIClient` protocol (and its mocks) stay unchanged.
    @TaskLocal static var requestedTokens: Int?
}

/// Preferences for the Artifacts feature. Plain value type, stored as a JSON blob under one UserDefaults key.
struct ArtifactSettings: Codable, Equatable, Sendable {
    enum DefaultFormat: String, Codable, CaseIterable, Sendable {
        case auto, page, app
    }

    /// The most the AI is asked to write for one artifact, in KB (8...128).
    var maxOutputKB: Int = ArtifactOutputBudget.defaultKB
    /// Whether interactive "app" artifacts may be created. Saved apps keep running either way.
    var allowAppArtifacts: Bool = true
    /// The Format the draft screen starts on.
    var defaultFormat: DefaultFormat = .auto

    static let `default` = ArtifactSettings()

    init() {}

    /// Tolerant: missing keys and unknown values fall back to defaults instead of resetting everything.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ArtifactSettings()
        maxOutputKB = ArtifactOutputBudget.clampedKB((try? c.decodeIfPresent(Int.self, forKey: .maxOutputKB)) ?? d.maxOutputKB)
        allowAppArtifacts = (try? c.decodeIfPresent(Bool.self, forKey: .allowAppArtifacts)) ?? d.allowAppArtifacts
        defaultFormat = (try? c.decodeIfPresent(DefaultFormat.self, forKey: .defaultFormat)) ?? d.defaultFormat
    }

    var outputBytes: Int { ArtifactOutputBudget.bytes(forKB: maxOutputKB) }
    var outputTokens: Int { ArtifactOutputBudget.tokens(forKB: maxOutputKB) }
}
