import Foundation

enum BridgeLimits {
    static let maxMessageBytes = 262_144
    static let defaultTimeout: TimeInterval = 30
    static let aiTimeout: TimeInterval = 120
}

/// What the web view gets back: `{ok:true,value}` or `{ok:false,error:{code,message}}`.
enum BridgeReply: Equatable {
    case ok(JSONValue)
    case error(code: String, message: String)

    var json: JSONValue {
        switch self {
        case .ok(let value):
            return .object(["ok": .bool(true), "value": value])
        case .error(let code, let message):
            return .object(["ok": .bool(false), "error": .object(["code": .string(code), "message": .string(message)])])
        }
    }
}

/// The bridge's logic as a pure function (message in, reply out), so it is testable without a `WKWebView`.
struct BridgeDispatcher: Sendable {
    let registry: CapabilityRegistry
    let session: ArtifactSession
    /// Read on every call, so a grant change takes effect immediately.
    let granted: @Sendable () -> Set<String>
    let onError: @Sendable (String) -> Void
    let timeout: @Sendable (String) -> TimeInterval

    init(
        registry: CapabilityRegistry,
        session: ArtifactSession,
        granted: @escaping @Sendable () -> Set<String>,
        onError: @escaping @Sendable (String) -> Void = { _ in },
        timeout: @escaping @Sendable (String) -> TimeInterval = { $0 == "ai.generate" ? BridgeLimits.aiTimeout : BridgeLimits.defaultTimeout }
    ) {
        self.registry = registry
        self.session = session
        self.granted = granted
        self.onError = onError
        self.timeout = timeout
    }

    func handle(body: JSONValue, byteCount: Int, isMainFrame: Bool) async -> BridgeReply {
        guard isMainFrame else { return fail("badMessage", "Calls are only accepted from the main page.", name: nil) }
        guard byteCount <= BridgeLimits.maxMessageBytes else { return fail("badMessage", "The message is too large.", name: nil) }
        guard case .object(let object) = body, let name = object["name"]?.stringValue, !name.isEmpty else {
            return fail("badMessage", "A call needs a name and args.", name: nil)
        }
        let args: JSONValue = {
            guard let raw = object["args"], raw != .null else { return .object([:]) }
            return raw
        }()

        let registry = self.registry
        let session = self.session
        let grant = granted()
        let outcome = await race(seconds: timeout(name)) { await registry.call(name: name, args: args, session: session, granted: grant) }
        switch outcome {
        case nil:
            return fail("timeout", "The call took too long.", name: name)
        case .success(let value)?:
            return .ok(value)
        case .failure(let error)?:
            switch error {
            case .unknown: return fail("unknown", "There is no capability with this name.", name: name)
            case .notGranted: return fail("notGranted", "The person has not allowed this.", name: name)
            case .badArgs(let message): return fail("badArgs", message, name: name)
            case .failed(let message): return fail("failed", message, name: name)
            case .rateLimited: return fail("rateLimited", "Too many AI calls. Wait a moment and try again.", name: name)
            }
        }
    }

    private func fail(_ code: String, _ message: String, name: String?) -> BridgeReply {
        onError("\(name ?? "message"): \(message) (\(code))")
        return .error(code: code, message: message)
    }
}

/// Runs `work` against a timer. The first to finish wins; a late result is discarded
/// (the work is cancelled, but a handler that ignores cancellation just finishes unseen).
private func race<T: Sendable>(seconds: TimeInterval, _ work: @escaping @Sendable () async -> T) async -> T? {
    await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
        let once = Once(continuation)
        let job = Task { once.finish(await work()) }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
            if once.finish(nil) { job.cancel() }
        }
    }
}

private final class Once<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?

    init(_ continuation: CheckedContinuation<T?, Never>) { self.continuation = continuation }

    /// Resumes at most once; returns whether this call was the one that resumed.
    @discardableResult
    func finish(_ value: T?) -> Bool {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
        return pending != nil
    }
}
