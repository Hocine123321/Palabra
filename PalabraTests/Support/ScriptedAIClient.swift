import Foundation
@testable import Palabra

/// An `AIClient` whose `listModels` replies come from a script, and which records the API
/// key each call used, so tests can prove which key served which request.
final class ScriptedAIClient: AIClient, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [Result<[AIModel], AIError>]
    private var keys: [String] = []
    /// Used once the script runs out.
    var fallbackResult: Result<[AIModel], AIError> = .success([])

    init(_ script: [Result<[AIModel], AIError>]) { self.script = script }

    var keysUsed: [String] { lock.lock(); defer { lock.unlock() }; return keys }
    var callCount: Int { keysUsed.count }

    func listModels(apiKey: String) async -> Result<[AIModel], AIError> {
        lock.lock(); defer { lock.unlock() }
        keys.append(apiKey)
        return script.isEmpty ? fallbackResult : script.removeFirst()
    }

    func generateWord(_ input: String, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<WordContent, AIError> { .failure(.malformedResponse) }
    func sendChat(apiKey: String, model: AIModel, word: WordContent, history: [ChatMessage], newMessage: String, language: SupportedLanguage) async -> Result<String, AIError> { .failure(.malformedResponse) }
    func synthesizeSpeech(_ text: String, apiKey: String, model: AIModel) async -> Result<Data, AIError> { .failure(.malformedResponse) }
    func generateJSON(prompt: String, systemInstruction: String, schema: [String: Any]?, apiKey: String, model: AIModel, temperature: Double) async -> Result<String, AIError> { .failure(.malformedResponse) }
    func organizeWords(_ words: [OrganizerWordInput], existingCategories: [String], settings: OrganizerSettings, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<OrganizerBatchResult, AIError> { .failure(.malformedResponse) }
}

/// Connectivity that returns at once, so offline tests don't wait.
struct InstantConnectivity: ConnectivityWaiting {
    /// What `waitForConnection` reports.
    var comesBack = true
    /// What the instant `isConnected` snapshot reports; independent of
    /// `comesBack` since the two are read in different places (a pre-check
    /// before starting a request vs. a wait after one failed).
    var isConnected = true
    func waitForConnection(timeout: TimeInterval) async -> Bool { comesBack }
}

/// Collects the waits the client asked for, without actually waiting.
final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var total: TimeInterval = 0
    func add(_ s: TimeInterval) { lock.lock(); total += s; lock.unlock() }
    var seconds: TimeInterval { lock.lock(); defer { lock.unlock() }; return total }
}
