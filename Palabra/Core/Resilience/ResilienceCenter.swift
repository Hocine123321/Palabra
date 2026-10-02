import Foundation
import Observation

/// What the person chose when automatic retries ran out.
enum RetryDecision: Equatable, Sendable {
    case stop
    case retryNow
    /// Try again, waiting much longer between each attempt.
    case retryPatiently
}

/// The app's shared, observable view of AI trouble: what is being retried right now, what
/// needs a decision, and which key is in use. Views read it; `ResilientAIClient` writes it.
@MainActor
@Observable
final class ResilienceCenter {
    /// A retry the app is doing on its own, shown as a quiet status.
    struct Retrying: Equatable {
        var reason: AIError
        var attempt: Int
        var of: Int
        var secondsLeft: Int
        var usingFallbackKey: Bool
    }

    /// A question waiting for the person: automatic retries did not work.
    struct Decision: Identifiable, Equatable {
        let id = UUID()
        var error: AIError
        var attempts: Int
        var canSwitchKey: Bool
        var what: String
    }

    /// A short, non-blocking notice ("Switched to your backup key").
    struct Notice: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var isWarning: Bool
    }

    /// Each in-flight request reports its own retry, so concurrent requests can't erase
    /// each other's status. The UI shows the one with the longest wait left.
    private(set) var retryingByRequest: [UUID: Retrying] = [:]
    var retrying: Retrying? {
        retryingByRequest.values.max { $0.secondsLeft < $1.secondsLeft }
    }
    private(set) var pendingDecision: Decision?
    private(set) var notice: Notice?
    private(set) var isOffline = false
    /// Which key is being used right now (for the Settings status line).
    private(set) var activeSlot: KeyHealth.Slot = .primary
    private(set) var health = KeyHealth()
    /// Recent problems, newest first, so "silent" failures are visible somewhere.
    private(set) var log: [LogEntry] = []

    struct LogEntry: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let what: String
        let error: AIError
        let outcome: String
    }

    /// Every request currently waiting on the person. All get the same answer.
    @ObservationIgnored private var waiters: [UUID: CheckedContinuation<RetryDecision, Never>] = [:]
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    static let maxLogEntries = 30

    // MARK: state the client reports

    func setRetrying(_ value: Retrying?, request: UUID) {
        if let value { retryingByRequest[request] = value } else { retryingByRequest[request] = nil }
    }
    func setOffline(_ value: Bool) { isOffline = value }
    func updateHealth(_ transform: (inout KeyHealth) -> Void) {
        transform(&health)
        activeSlot = health.active
    }

    func post(_ text: String, warning: Bool = false, duration: TimeInterval = 6) {
        notice = Notice(text: text, isWarning: warning)
        noticeTask?.cancel()
        let id = notice?.id
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if self?.notice?.id == id { self?.notice = nil }
        }
    }

    func dismissNotice() { notice = nil }

    func record(what: String, error: AIError, outcome: String, now: Date = Date()) {
        log.insert(LogEntry(date: now, what: what, error: error, outcome: outcome), at: 0)
        if log.count > Self.maxLogEntries { log.removeLast(log.count - Self.maxLogEntries) }
    }

    func clearLog() { log = [] }

    // MARK: asking the person

    /// Suspends the calling request until the person answers. Only one question is shown at
    /// a time; concurrent requests join it and all receive the same answer.
    func ask(_ decision: Decision) async -> RetryDecision {
        if Task.isCancelled { return .stop }
        if pendingDecision == nil { pendingDecision = decision }
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<RetryDecision, Never>) in
                waiters[waiterID] = c
            }
        } onCancel: {
            // The screen that asked went away: stop waiting, and drop the card if nobody else needs it.
            Task { @MainActor [weak self] in self?.abandon(waiterID) }
        }
    }

    private func abandon(_ id: UUID) {
        guard let c = waiters.removeValue(forKey: id) else { return }
        c.resume(returning: .stop)
        if waiters.isEmpty { pendingDecision = nil }
    }

    func answer(_ choice: RetryDecision) {
        let all = waiters.values
        waiters = [:]
        pendingDecision = nil
        for c in all { c.resume(returning: choice) }
    }

    /// Resolves anything still waiting as "stop", e.g. when the screen that asked goes away.
    func cancelAll() { answer(.stop) }
}
