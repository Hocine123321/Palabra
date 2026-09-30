import Foundation
import Network

/// Lets a request that failed because the phone is offline wait for the connection to
/// return, instead of burning its retries while there is no network at all.
protocol ConnectivityWaiting: Sendable {
    /// Returns true when the network is back, false if `timeout` passed first.
    func waitForConnection(timeout: TimeInterval) async -> Bool
}

final class NetworkMonitor: ConnectivityWaiting, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "dev.palabra.network")
    private let lock = NSLock()
    private var satisfied = true

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock(); self.satisfied = path.status == .satisfied; self.lock.unlock()
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }

    var isConnected: Bool { lock.lock(); defer { lock.unlock() }; return satisfied }

    func waitForConnection(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isConnected { return true }
            if Task.isCancelled { return false }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return isConnected
    }
}
