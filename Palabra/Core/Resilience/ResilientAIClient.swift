import Foundation

/// Wraps any `AIClient` and adds the app's self-healing behavior, so every screen gets it
/// without its own retry code:
///
/// - retries transient failures automatically, with growing waits;
/// - waits for the network instead of counting an offline failure as an attempt;
/// - switches to the fallback API key when the first one keeps failing;
/// - when nothing automatic is left, asks the person to stop, retry, or retry patiently;
/// - records what happened so failures are never invisible.
///
/// Call sites still pass the primary key. This client substitutes the fallback key when
/// needed, so no screen has to know a fallback exists.
final class ResilientAIClient: AIClient, @unchecked Sendable {
    private let base: AIClient
    private let center: ResilienceCenter
    private let fallbackKey: @Sendable () -> String?
    private let policyProvider: @Sendable () async -> RetryPolicy
    private let connectivity: ConnectivityWaiting
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let now: @Sendable () -> Date
    /// Background work (auto-pronunciation, auto-organize) must never pop up a question.
    private let interactive: Bool

    init(
        base: AIClient,
        center: ResilienceCenter,
        fallbackKey: @escaping @Sendable () -> String?,
        policy: @escaping @Sendable () async -> RetryPolicy,
        connectivity: ConnectivityWaiting = NetworkMonitor(),
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
        now: @escaping @Sendable () -> Date = { Date() },
        interactive: Bool = true
    ) {
        self.base = base
        self.center = center
        self.fallbackKey = fallbackKey
        self.policyProvider = policy
        self.connectivity = connectivity
        self.sleep = sleep
        self.now = now
        self.interactive = interactive
    }

    /// A variant for background tasks: same retries and key switching, but it never asks.
    func quiet() -> ResilientAIClient {
        ResilientAIClient(base: base, center: center, fallbackKey: fallbackKey, policy: policyProvider,
                          connectivity: connectivity, sleep: sleep, now: now, interactive: false)
    }

    // MARK: AIClient

    func listModels(apiKey: String) async -> Result<[AIModel], AIError> {
        await run("Loading models", primary: apiKey) { key in await self.base.listModels(apiKey: key) }
    }

    func generateWord(_ input: String, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<WordContent, AIError> {
        await run("Generating \"\(input)\"", primary: apiKey) { key in await self.base.generateWord(input, apiKey: key, model: model, language: language) }
    }

    func sendChat(apiKey: String, model: AIModel, word: WordContent, history: [ChatMessage], newMessage: String, language: SupportedLanguage) async -> Result<String, AIError> {
        await run("Chat reply", primary: apiKey) { key in await self.base.sendChat(apiKey: key, model: model, word: word, history: history, newMessage: newMessage, language: language) }
    }

    func synthesizeSpeech(_ text: String, apiKey: String, model: AIModel) async -> Result<Data, AIError> {
        await run("Pronunciation", primary: apiKey) { key in await self.base.synthesizeSpeech(text, apiKey: key, model: model) }
    }

    func generateJSON(prompt: String, systemInstruction: String, schema: [String: Any]?, apiKey: String, model: AIModel, temperature: Double) async -> Result<String, AIError> {
        await run("AI request", primary: apiKey) { key in await self.base.generateJSON(prompt: prompt, systemInstruction: systemInstruction, schema: schema, apiKey: key, model: model, temperature: temperature) }
    }

    func organizeWords(_ words: [OrganizerWordInput], existingCategories: [String], settings: OrganizerSettings, apiKey: String, model: AIModel, language: SupportedLanguage) async -> Result<OrganizerBatchResult, AIError> {
        await run("Organizing words", primary: apiKey) { key in await self.base.organizeWords(words, existingCategories: existingCategories, settings: settings, apiKey: key, model: model, language: language) }
    }

    // MARK: the loop

    /// Runs `operation`, reacting to each failure according to `ErrorStrategy`.
    private func run<T: Sendable>(_ what: String, primary: String, _ operation: @escaping @Sendable (String) async -> Result<T, AIError>) async -> Result<T, AIError> {
        let policy = await policyProvider()
        // Feature off: behave exactly like the plain client.
        guard policy.autoRetryEnabled else { return await operation(primary) }

        var patientRound = 0
        var lastError: AIError = .unknown(nil, "")

        while true {
            if Task.isCancelled { await center.setRetrying(nil); return .failure(lastError == .unknown(nil, "") ? .timeout : lastError) }
            let fallback = fallbackKey()
            let hasFallback = fallback != nil
            let health = await center.health
            guard let slot = health.slotToUse(hasFallback: hasFallback, now: now()) else {
                // Both keys are benched: nothing to try until one recovers.
                let error = lastError == .unknown(nil, "") ? AIError.rateLimited : lastError
                switch await askOrGiveUp(error: error, attempts: 0, what: what, canSwitchKey: false) {
                case .stop: await finish(what, error, "Stopped"); return .failure(error)
                case .retryNow, .retryPatiently:
                    await center.updateHealth { $0.reset(.primary); $0.reset(.fallback) }
                    continue
                }
            }
            let key = slot == .primary ? primary : (fallback ?? primary)

            var failedAttempts = 0
            attemptLoop: while true {
                let result = await operation(key)
                switch result {
                case .success:
                    await center.updateHealth { $0.recordSuccess(slot) }
                    await center.setRetrying(nil)
                    await center.setOffline(false)
                    return result
                case .failure(let error):
                    lastError = error
                    await center.updateHealth { _ = $0.recordFailure(slot, error: error, now: self.now()) }
                    let usable = slot == .primary && hasFallback
                    let action = ErrorStrategy.next(after: error, failedAttempts: failedAttempts, policy: policy, hasFallback: usable)
                    switch action {
                    case .giveUp:
                        await finish(what, error, "Not retryable")
                        return .failure(error)
                    case .waitForNetwork:
                        await center.setOffline(true)
                        await center.setRetrying(nil)
                        let back = await connectivity.waitForConnection(timeout: 45)
                        await center.setOffline(false)
                        if !back {
                            switch await askOrGiveUp(error: error, attempts: failedAttempts, what: what, canSwitchKey: false) {
                            case .stop: await finish(what, error, "Stopped while offline"); return .failure(error)
                            default: continue attemptLoop
                            }
                        }
                        // Being offline doesn't count as a failed attempt.
                        continue attemptLoop
                    case .retry(let after):
                        failedAttempts += 1
                        let total = ErrorStrategy.maxAttempts(for: error, policy: policy)
                        await countdown(after, error: error, attempt: failedAttempts, of: total, usingFallback: slot == .fallback)
                        if Task.isCancelled { await center.setRetrying(nil); return .failure(error) }
                        continue attemptLoop
                    case .switchKey:
                        await center.setRetrying(nil)
                        await center.record(what: what, error: error, outcome: "Switched to backup key")
                        await center.post("Your main key failed, so the backup key is being used.", warning: true)
                        break attemptLoop   // re-enter outer loop; health now benches the failed key
                    case .askUser:
                        await center.setRetrying(nil)
                        let choice = await askOrGiveUp(error: error, attempts: failedAttempts, what: what, canSwitchKey: usable)
                        switch choice {
                        case .stop:
                            await finish(what, error, "Stopped by you")
                            return .failure(error)
                        case .retryNow:
                            failedAttempts = 0
                            continue attemptLoop
                        case .retryPatiently:
                            patientRound += 1
                            let wait = policy.patientDelay(forAttempt: patientRound - 1)
                            await countdown(wait, error: error, attempt: patientRound, of: patientRound, usingFallback: slot == .fallback)
                            failedAttempts = 0
                            continue attemptLoop
                        }
                    }
                }
            }
        }
    }

    /// Non-interactive (background) work never asks: it stops quietly, and the failure is logged.
    private func askOrGiveUp(error: AIError, attempts: Int, what: String, canSwitchKey: Bool) async -> RetryDecision {
        guard interactive, !Task.isCancelled else { return .stop }
        return await center.ask(ResilienceCenter.Decision(error: error, attempts: attempts, canSwitchKey: canSwitchKey, what: what))
    }

    private func finish(_ what: String, _ error: AIError, _ outcome: String) async {
        await center.setRetrying(nil)
        await center.record(what: what, error: error, outcome: outcome, now: now())
    }

    /// Waits `seconds`, updating the visible countdown once a second.
    private func countdown(_ seconds: TimeInterval, error: AIError, attempt: Int, of total: Int, usingFallback: Bool) async {
        var left = Int(seconds.rounded(.up))
        while left > 0 {
            await center.setRetrying(.init(reason: error, attempt: attempt, of: total, secondsLeft: left, usingFallbackKey: usingFallback))
            await sleep(1)
            if Task.isCancelled { return }
            left -= 1
        }
        await center.setRetrying(.init(reason: error, attempt: attempt, of: total, secondsLeft: 0, usingFallbackKey: usingFallback))
    }
}
