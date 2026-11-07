import Foundation

/// The "Trust this computer?" question, as plain rules the tests can check: one question at a time, 60 seconds to answer,
/// each question answered once, and a request that names another phone or has a bad key never reaches the person.
struct TrustRequests: Sendable {
    static let lifetime: TimeInterval = 60
    static let maxQueued = 3

    struct Request: Equatable, Identifiable, Sendable {
        let browserId: String
        let name: String
        let browserPub: String
        let code: String            // the four digits; the person compares them with the page
        let askedAt: Date
        var id: String { browserId }
    }

    enum Intake: Equatable, Sendable { case ignored, shown(Request), queued }

    let deviceId: String
    let phonePub: String
    private(set) var current: Request?
    private(set) var queue: [Request] = []
    private var answered: Set<String> = []

    init(deviceId: String, phonePub: String) {
        self.deviceId = deviceId
        self.phonePub = phonePub
    }

    /// A request frame from the lobby. Returns what to do with it.
    mutating func receive(to: String?, browserId: String?, name: String?, pub: String?, now: Date) -> Intake {
        expire(now: now)
        guard to == deviceId, let browserId, Self.isHex(browserId, 32), let pub,
              let code = try? TrustCrypto.matchCode(phonePub: phonePub, browserPub: pub) else { return .ignored }
        if answered.contains(browserId) || current?.browserId == browserId || queue.contains(where: { $0.browserId == browserId }) { return .ignored }
        let request = Request(browserId: browserId, name: Self.cleaned(name), browserPub: pub.lowercased(), code: code, askedAt: now)
        if current == nil { current = request; return .shown(request) }
        guard queue.count < Self.maxQueued else { return .ignored }
        queue.append(request)
        return .queued
    }

    /// The person answered (or declined). Returns the request that was answered and, if another was waiting, the next one to show.
    /// A request that is not the current one, or was already answered, returns nil: nothing is granted twice.
    mutating func answer(browserId: String, now: Date) -> (answered: Request, next: Request?)? {
        expire(now: now)
        guard let current, current.browserId == browserId else { return nil }
        answered.insert(browserId)
        self.current = queue.isEmpty ? nil : queue.removeFirst()
        return (current, self.current)
    }

    /// Drops questions older than the lifetime (the page has stopped waiting). Returns true if something changed.
    @discardableResult
    mutating func expire(now: Date) -> Bool {
        var changed = false
        if let c = current, now.timeIntervalSince(c.askedAt) >= Self.lifetime {
            answered.insert(c.browserId)
            current = nil
            changed = true
        }
        let before = queue.count
        queue.removeAll { now.timeIntervalSince($0.askedAt) >= Self.lifetime }
        changed = changed || queue.count != before
        if current == nil, !queue.isEmpty { current = queue.removeFirst(); changed = true }
        return changed
    }

    /// Closing "Pair a browser" cancels every open question.
    mutating func cancelAll() {
        current = nil
        queue.removeAll()
    }

    private static func cleaned(_ name: String?) -> String {
        let text = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).filter { !$0.isNewline }
        return text.isEmpty ? "A computer" : String(text.prefix(40))
    }

    private static func isHex(_ text: String, _ count: Int) -> Bool {
        text.count == count && text.allSatisfy { $0.isHexDigit }
    }
}
