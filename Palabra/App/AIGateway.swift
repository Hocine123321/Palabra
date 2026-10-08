import Foundation

/// How `ai.generate` reaches the AI. `AppEnvironment.init` cannot hand `self` to the registry,
/// so the registry holds this seam and the environment fills `run` in once it is fully built.
final class AIGateway: @unchecked Sendable {
    typealias Run = @Sendable (_ prompt: String, _ schema: JSONValue?, _ temperature: Double) async -> Result<String, AIError>

    private let lock = NSLock()
    private var _run: Run?

    var run: Run? {
        get { lock.lock(); defer { lock.unlock() }; return _run }
        set { lock.lock(); defer { lock.unlock() }; _run = newValue }
    }

    /// The fixed instruction `ai.generate` runs under: the artifact's prompt is the only variable part.
    static let systemInstruction = """
    You are the AI inside Palabra, an app that helps one person learn Spanish. Answer the request in the prompt and nothing else. Keep Spanish words and phrases in Spanish.
    """
}
