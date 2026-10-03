import Foundation
import Observation

/// Drains `AppEnvironment.wordQueue`: while there is a pending item, waits
/// for connectivity if needed, asks the AI quietly (no retry dialog — see
/// `AppEnvironment.backgroundAI`), and saves each result exactly like
/// `AddWordFlow.save()` would (via `WordWriter`). One item at a time,
/// oldest first, so a big queue can't flood the API at once.
///
/// `drain(environment:)` is cheap to call repeatedly — on app launch, on
/// returning to the foreground, right after a word is queued, and from a
/// manual Retry — a call while already draining is a no-op.
///
/// Known limitation: this only runs while the app is in the foreground.
/// There is no iOS background-execution hookup, so a queue left while the
/// app is backgrounded or force-quit resumes draining the next time the
/// app is opened, not before.
@MainActor
@Observable
final class WordQueueProcessor {
    private(set) var isDraining = false
    private var task: Task<Void, Never>?

    /// How long one pass waits for the network before re-checking the
    /// queue; kept short so a relaunch/foreground pass is noticed quickly.
    private let connectivityPollTimeout: TimeInterval
    /// Backoff before retrying an item that failed for a reason other than
    /// being offline (the AI client's own retries already happened once
    /// per attempt; this is the pause between those outer attempts).
    private let retryDelay: TimeInterval
    /// Outer attempts (beyond the AI client's own internal retries) before
    /// giving up on a retryable error and marking the item `.failed`.
    private let maxAttempts: Int
    private let sleep: @Sendable (TimeInterval) async -> Void

    init(
        connectivityPollTimeout: TimeInterval = 20,
        retryDelay: TimeInterval = 30,
        maxAttempts: Int = 5,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    ) {
        self.connectivityPollTimeout = connectivityPollTimeout
        self.retryDelay = retryDelay
        self.maxAttempts = maxAttempts
        self.sleep = sleep
    }

    func drain(environment: AppEnvironment) {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.run(environment: environment)
            self?.task = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isDraining = false
    }

    private func run(environment: AppEnvironment) async {
        isDraining = true
        defer { isDraining = false }
        // Nothing can genuinely still be in flight at the start of a fresh drain
        // (see the protocol doc) — recover anything orphaned by a previous launch.
        environment.wordQueue.resetStuckProcessing()
        while !Task.isCancelled {
            guard let item = environment.wordQueue.nextPending() else { return }
            // An instant snapshot, not `ConnectivityWaiting.waitForConnection`: that
            // method is for a request already in flight, not for deciding whether to
            // start one. Polling our own way also means a single `sleep` injection
            // point covers both this and the retry backoff below, for tests.
            guard environment.connectivity.isConnected else {
                await sleep(connectivityPollTimeout)
                continue
            }
            await process(item, environment: environment)
        }
    }

    private func process(_ item: WordQueueItem, environment: AppEnvironment) async {
        guard environment.hasAPIKey, let apiKey = environment.apiKey else {
            environment.wordQueue.markFailed(id: item.id, lastError: AIError.missingAPIKey.userMessage)
            return
        }
        guard let model = environment.selectedModel else {
            let error: AIError = environment.selectedModelID == nil ? .noModelSelected : .modelUnavailable(environment.selectedModelID ?? "")
            environment.wordQueue.markFailed(id: item.id, lastError: error.userMessage)
            return
        }
        environment.wordQueue.markProcessing(id: item.id)
        let result = await environment.backgroundAI.generateWord(item.inputWord, apiKey: apiKey, model: model, language: item.language)
        if Task.isCancelled { return }
        switch result {
        case .success(let content):
            let saved = WordWriter.commit(content: content, mode: item.mode, environment: environment)
            environment.wordQueue.remove(id: item.id)
            if let saved {
                environment.resilience.post("Added \"\(saved.spanish)\" now that you're back online.")
            }
        case .failure(let error):
            if error == .offline {
                // Doesn't count as a failed attempt — the outer loop waits for the network.
                environment.wordQueue.markPending(id: item.id, attempts: item.attempts, lastError: nil)
                return
            }
            let attempts = item.attempts + 1
            if error.isRetryable, attempts < maxAttempts {
                environment.wordQueue.markPending(id: item.id, attempts: attempts, lastError: error.userMessage)
                await sleep(retryDelay)
            } else {
                environment.wordQueue.markFailed(id: item.id, lastError: error.userMessage)
            }
        }
    }
}
