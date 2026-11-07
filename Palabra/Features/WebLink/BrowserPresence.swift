import Foundation

/// Whether the browser is in the room, as the relay last said. The relay's "peer:here" and the socket's "connected" report travel on
/// different callbacks and can reach the controller in either order. If the notice comes first and is only acted on as it passes,
/// it is lost and the phone waits for a browser that is already there. So the notice is remembered, and "connected" reads it.
struct BrowserPresence: Equatable, Sendable {
    enum Link: Equatable, Sendable { case waitingForBrowser, linked }

    private(set) var browserHere = false
    private(set) var connected = false

    /// What the phone should show now.
    var link: Link { connected && browserHere ? .linked : .waitingForBrowser }

    mutating func relayConnected() { connected = true }
    /// The connection ended (dropped, failed, or closed on purpose): the next one will say again who is in the room.
    mutating func relayLost() { connected = false; browserHere = false }
    mutating func notice(browserHere here: Bool) { browserHere = here }
}
