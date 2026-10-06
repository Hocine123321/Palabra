import Foundation

enum CapabilityClass: Sendable {
    /// Reads app data.
    case read
    /// Changes app data.
    case write
    /// Spends AI quota.
    case ai
    /// The artifact's own storage; never touches app data, so always granted.
    case local

    var label: String {
        switch self {
        case .read: return "read"
        case .write: return "write"
        case .ai: return "ai"
        case .local: return "local"
        }
    }
}

/// Where a call comes from. `artifactID == nil` is an unsaved draft; `dryRun` is the preview.
struct ArtifactSession: Sendable {
    let artifactID: UUID?
    let dryRun: Bool
}

enum CapabilityError: Error, Equatable {
    case unknown
    case notGranted
    case badArgs(String)
    case failed(String)
    case rateLimited
}

/// One thing an artifact may ask the app to do. Registered once; both the dispatcher and the
/// AI manual are generated from it, so a new capability is learnable with no prompt edits.
struct Capability: Sendable {
    let name: String
    let kind: CapabilityClass
    /// Plain language: goes into the AI manual (and later the approval sheet).
    let summary: String
    /// Object mapping each argument to a human description.
    let argsSchema: JSONValue
    let returnsSummary: String
    /// Required for `.write`: returned instead of running the handler in a dry run.
    let dryRunValue: JSONValue?
    let handler: @Sendable (JSONValue, ArtifactSession) async -> Result<JSONValue, CapabilityError>

    init(
        name: String,
        kind: CapabilityClass,
        summary: String,
        argsSchema: JSONValue = .object([:]),
        returnsSummary: String,
        dryRunValue: JSONValue? = nil,
        handler: @escaping @Sendable (JSONValue, ArtifactSession) async -> Result<JSONValue, CapabilityError>
    ) {
        self.name = name
        self.kind = kind
        self.summary = summary
        self.argsSchema = argsSchema
        self.returnsSummary = returnsSummary
        self.dryRunValue = dryRunValue
        self.handler = handler
    }
}
