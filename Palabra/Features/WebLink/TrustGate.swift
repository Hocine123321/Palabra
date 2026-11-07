import Foundation

/// Decides whether the browser on the other end may be answered. Two kinds of browser exist:
/// one that paired with the six digit code (it presents nothing, and keeps working exactly as before), and one the person chose to trust
/// (it presents its token in a `hello`). A trusted browser that was removed from the list presents a token nobody knows any more,
/// so removing one computer cuts that computer off without touching the others.
struct TrustGate: Equatable, Sendable {
    enum Verdict: Equatable, Sendable { case allowed, revoked }

    /// True once a browser presented a token that was on the list at that moment.
    private(set) var vouched = false
    /// The token the browser presented, kept for this connection only so a later removal can be noticed.
    private var token: Data?
    /// A hello with an unknown token. The connection stays refused until a new hello (a new connection) starts over.
    private var refused = false

    /// A new connection starts with nothing known about the browser.
    mutating func reset() { vouched = false; token = nil; refused = false }

    /// The browser's `hello`. An unknown token is refused at once and stays refused for the rest of the connection.
    mutating func hello(token: Data?, trusted: TrustedBrowsers) -> Verdict {
        guard let token else { return .allowed }          // the code path presents nothing
        self.token = token
        vouched = trusted.isTrusted(token: token)
        refused = !vouched
        return vouched ? .allowed : .revoked
    }

    /// Whether an ordinary request may be answered. A browser that presented a bad token never is. A computer that was
    /// removed while connected is cut off on its next request (`trusted` is read fresh each time).
    func verdict(trusted: TrustedBrowsers) -> Verdict {
        if refused { return .revoked }
        guard let token else { return .allowed }          // paired with the code: nothing to check
        return trusted.isTrusted(token: token) ? .allowed : .revoked     // an unknown token is never vouched, and a removed one stops here
    }
}
