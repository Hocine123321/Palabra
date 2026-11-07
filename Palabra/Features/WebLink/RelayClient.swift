import Foundation

/// The phone's outgoing connection to the relay. It sends and receives opaque binary frames; the encryption is
/// `LinkCrypto.Session`'s job, so the relay (and anything between) only ever sees bytes.
/// The link exists only while the app is in the foreground: the caller connects on becoming active and
/// disconnects when leaving it.
final class RelayClient: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    enum State: Equatable, Sendable { case disconnected, connecting, connected, failed(String) }

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
        task?.cancel(with: .goingAway, reason: nil)
        let task = session.webSocketTask(with: relayURL.appendingPathComponent("r").appendingPathComponent(roomID))
        self.task = task
        onState?(.connecting)
        task.resume()      // `.connected` is reported by the delegate once the handshake really completes
        listen(task, generation: mine)
    }

    func disconnect() {
        lock.lock(); generation += 1; lock.unlock()
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
        if isCurrent { onState?(.connected) }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard webSocketTask === task else { return }
        // 4001 = the room already has two ends. Say so instead of looking like a network problem.
        onState?(closeCode.rawValue == 4001 ? .failed("Another browser is already linked") : .disconnected)
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
            case .success:
                self.listen(task, generation: mine) // the relay only forwards binary frames; ignore anything else
            case .failure(let error):
                self.onState?(.failed(error.localizedDescription))
            }
        }
    }
}
