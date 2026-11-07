import Foundation

/// The phone's memory of the last actions it ran for the page, so a retry after a lost reply is answered with the first
/// result instead of acting twice (adding the same words again, flagging again). Bounded: old entries fall out.
/// Memory only: after the app restarts the page's retry is judged on its merits (adds skip duplicates anyway).
final class RecentActions: @unchecked Sendable {
    private let lock = NSLock()
    private var order: [String] = []
    private var replies: [String: JSONValue] = [:]
    let limit: Int

    init(limit: Int = 200) { self.limit = limit }

    /// The stored reply for an action id the phone already ran, if any.
    func reply(for id: String) -> JSONValue? {
        lock.lock(); defer { lock.unlock() }
        return replies[id]
    }

    /// Remember the reply of an action that ran. Only successes are remembered: a refusal can be retried.
    func remember(id: String, reply: JSONValue) {
        lock.lock(); defer { lock.unlock() }
        if replies[id] == nil { order.append(id) }
        replies[id] = reply
        while order.count > limit { replies.removeValue(forKey: order.removeFirst()) }
    }
}
