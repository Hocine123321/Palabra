import Foundation
import Network

/// A tiny HTTP server on the phone, alive only while the "Pair a browser" screen is open. The direct local
/// connection from the page to this listener is the proof of "same Wi-Fi": a device on another network cannot
/// reach a private address. It speaks just enough HTTP for `fetch()` from a page, including the CORS preflight.
final class LocalPairingListener: @unchecked Sendable {
    static let port: NWEndpoint.Port = 47615

    private let service: PairingService
    private let queue = DispatchQueue(label: "dev.palabra.weblink.pairing")
    private var listener: NWListener?

    init(service: PairingService) { self.service = service }

    var onState: (@Sendable (NWListener.State) -> Void)?

    func start() throws {
        stop()
        let params = NWParameters.tcp
        params.requiredInterfaceType = .wifi   // never answer on cellular
        let listener = try NWListener(using: params, on: Self.port)
        listener.stateUpdateHandler = { [weak self] in self?.onState?($0) }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: Connections

    private func accept(_ connection: NWConnection) {
        // Only private (same-network) peers. Anything else is dropped before a byte is read.
        guard Self.isLocal(connection.endpoint) else { connection.cancel(); return }
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, done, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if buffer.count > HTTPRequest.maxBytes || error != nil { return connection.cancel() }
            switch HTTPRequest.parse(buffer) {
            case .incomplete where !done:
                self.receive(connection, buffer: buffer)
            case .request(let request):
                self.send(HTTPResponse.make(for: request, service: self.service), on: connection)
            default:
                self.send(HTTPResponse.status(400), on: connection)
            }
        }
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    static func isLocal(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address): return PrivateAddress.isPrivate(ipv4: address.rawValue)
        case .ipv6(let address): return PrivateAddress.isPrivate(ipv6: address.rawValue)
        default: return false
        }
    }
}

/// Which addresses count as "this network".
enum PrivateAddress {
    static func isPrivate(ipv4 b: Data) -> Bool {
        guard b.count == 4 else { return false }
        switch (b[0], b[1]) {
        case (10, _), (192, 168), (127, _), (169, 254): return true
        case (172, 16...31): return true
        default: return false
        }
    }

    static func isPrivate(ipv6 b: Data) -> Bool {
        guard b.count == 16 else { return false }
        if b.dropLast().allSatisfy({ $0 == 0 }) && b.last == 1 { return true }       // ::1
        if b[0] == 0xfe && (b[1] & 0xc0) == 0x80 { return true }                      // fe80::/10 link-local
        if (b[0] & 0xfe) == 0xfc { return true }                                      // fc00::/7 unique local
        if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xff && b[11] == 0xff {       // ::ffff:a.b.c.d
            return isPrivate(ipv4: b.suffix(4))
        }
        return false
    }
}
