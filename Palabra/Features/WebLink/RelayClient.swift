import Foundation

/// The phone's outgoing connection to the relay. It sends and receives opaque binary frames; the encryption is
/// `LinkCrypto.Session`'s job, so the relay (and anything between) only ever sees bytes.
/// The link exists only while the app is in the foreground: the caller connects on becoming active and
/// disconnects when leaving it.
final class RelayClient: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    enum State: Equatable, Sendable { case disconnected, connecting, connected, failed(String) }

    /// What the relay says about the browser's seat, in its own text notices ("peer:here" / "peer:gone").
    /// Peers can only send binary frames, so these cannot be forged by the other end.
    enum Presence: Equatable, Sendable { case here, gone }

    /// The close code the relay uses when a newer connection took this end's seat.
    static let replacedCode = 4005
    /// A quiet link is checked this often. If the check gets no answer the socket is dead and the connection is rebuilt.
    static let pingInterval: TimeInterval = 15
    static let pingTimeout: TimeInterval = 10

    private let relayURL: URL
    private let roomID: String
    /// The room this client joins, for callers that need to know whether a connection already covers it.
    var roomIDValue: String { roomID }
    private var task: URLSessionWebSocketTask?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    private let lock = NSLock()
    private var generation = 0

    var onFrame: (@Sendable (Data) -> Void)?
    var onState: (@Sendable (State) -> Void)?
    var onPresence: (@Sendable (Presence) -> Void)?
    private var heartbeat: Task<Void, Never>?       // guarded by `lock`

    /// `relayURL` is the Worker's address, for example `wss://palabra-relay.example.workers.dev`.
    init?(relayURL: String, roomID: String) {
        guard let url = URL(string: relayURL), ["wss", "ws"].contains(url.scheme),
              roomID.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil else { return nil }
        self.relayURL = url
        self.roomID = roomID
    }

    func connect() {
        lock.lock()
        generation += 1
        let mine = generation
        lock.unlock()
        setHeartbeat(nil)
        task?.cancel(with: .goingAway, reason: nil)
        let task = session.webSocketTask(with: Self.endpoint(relay: relayURL, roomID: roomID))
        self.task = task
        onState?(.connecting)
        task.resume()      // `.connected` is reported by the delegate once the handshake really completes
        listen(task, generation: mine)
    }

    /// The phone always sits in the "app" seat, so a reconnect replaces its own earlier (possibly dead) socket instead of being refused.
    static func endpoint(relay: URL, roomID: String) -> URL {
        var parts = URLComponents(url: relay.appendingPathComponent("r").appendingPathComponent(roomID), resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "role", value: "app")]
        return parts?.url ?? relay
    }

    func disconnect() {
        lock.lock(); generation += 1; lock.unlock()
        setHeartbeat(nil)
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        onState?(.disconnected)
    }

    func send(_ frame: Data, completion: (@Sendable (Error?) -> Void)? = nil) {
        guard let task else { completion?(URLError(.notConnectedToInternet)); return }
        task.send(.data(frame)) { completion?($0) }
    }

    // MARK: URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        lock.lock(); let isCurrent = webSocketTask === task; lock.unlock()
        if isCurrent { onState?(.connected); startHeartbeat(webSocketTask) }
    }

    /// A socket the network killed without a word never reports an error. Ping it; no pong means it is dead, so say so and the
    /// controller rebuilds the connection (which is safe now: the new socket replaces the old one in the room).
    private func startHeartbeat(_ task: URLSessionWebSocketTask) {
        setHeartbeat(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.pingInterval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                let alive = await Self.pong(task, within: Self.pingTimeout)
                self.lock.lock(); let isCurrent = task === self.task; self.lock.unlock()
                guard isCurrent, !Task.isCancelled else { return }
                if !alive {
                    task.cancel(with: .goingAway, reason: nil)
                    self.onState?(.failed("The connection went quiet"))
                    return
                }
            }
        })
    }

    private func setHeartbeat(_ new: Task<Void, Never>?) {
        lock.lock(); let old = heartbeat; heartbeat = new; lock.unlock()
        old?.cancel()
    }

    private static func pong(_ task: URLSessionWebSocketTask, within seconds: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            let once = Once()
            task.sendPing { error in if once.first() { continuation.resume(returning: error == nil) } }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { if once.first() { continuation.resume(returning: false) } }
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock(); private var done = false
        func first() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard webSocketTask === task else { return }
        setHeartbeat(nil)
        switch closeCode.rawValue {
        case 4001: onState?(.failed("Another browser is already linked"))   // only an older relay without seats says this
        case Self.replacedCode: onState?(.failed("Replaced by a newer connection"))
        default: onState?(.disconnected)
        }
    }

    private func listen(_ task: URLSessionWebSocketTask, generation mine: Int) {
        task.receive { [weak self] result in
            guard let self else { return }
            self.lock.lock(); let current = self.generation; self.lock.unlock()
            guard mine == current else { return } // an old connection's callback
            switch result {
            case .success(.data(let data)):
                self.onFrame?(data)
                self.listen(task, generation: mine)
            case .success(.string(let text)):
                if text == "peer:here" { self.onPresence?(.here) } else if text == "peer:gone" { self.onPresence?(.gone) }
                self.listen(task, generation: mine)
            case .success:
                self.listen(task, generation: mine)
            case .failure(let error):
                self.onState?(.failed(error.localizedDescription))
            }
        }
    }
}
