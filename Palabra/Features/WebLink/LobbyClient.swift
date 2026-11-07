import Foundation

/// The phone's connection to the relay's lobby, where it announces itself so a browser on the same network can find it.
/// Text frames only. Open only while "Pair a browser" is on screen. It carries a display name and public keys, never a secret.
final class LobbyClient: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    enum State: Equatable, Sendable { case disconnected, connecting, connected, failed(String) }

    private let url: URL
    private var task: URLSessionWebSocketTask?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    private let lock = NSLock()
    private var generation = 0

    var onFrame: (@Sendable ([String: Any]) -> Void)?
    var onState: (@Sendable (State) -> Void)?

    /// `relayURL` is the Worker's address, for example `wss://palabra-relay.example.workers.dev`.
    init?(relayURL: String) {
        guard let base = URL(string: relayURL), ["wss", "ws"].contains(base.scheme) else { return nil }
        self.url = base.appendingPathComponent("lobby")
    }

    func connect() {
        lock.lock(); generation += 1; let mine = generation; lock.unlock()
        task?.cancel(with: .goingAway, reason: nil)
        let task = session.webSocketTask(with: url)
        self.task = task
        onState?(.connecting)
        task.resume()
        listen(task, generation: mine)
    }

    func disconnect() {
        lock.lock(); generation += 1; lock.unlock()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        onState?(.disconnected)
    }

    /// Frames are small JSON objects; anything that cannot be encoded is not sent.
    func send(_ frame: [String: Any]) {
        guard let task, JSONSerialization.isValidJSONObject(frame),
              let data = try? JSONSerialization.data(withJSONObject: frame), data.count <= 2048,
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { _ in }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        lock.lock(); let isCurrent = webSocketTask === task; lock.unlock()
        if isCurrent { onState?(.connected) }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard webSocketTask === task else { return }
        onState?(.disconnected)
    }

    private func listen(_ task: URLSessionWebSocketTask, generation mine: Int) {
        task.receive { [weak self] result in
            guard let self else { return }
            self.lock.lock(); let current = self.generation; self.lock.unlock()
            guard mine == current else { return }
            switch result {
            case .success(.string(let text)):
                if text.count <= 2048, let data = text.data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { self.onFrame?(object) }
                self.listen(task, generation: mine)
            case .success:
                self.listen(task, generation: mine)     // the lobby speaks text; ignore anything else
            case .failure(let error):
                self.onState?(.failed(error.localizedDescription))
            }
        }
    }
}
