import Foundation

enum PairingLinkError: Error, Equatable {
    case notALink
    case insecureOrigin
    case missingField(String)
    case badField(String)
}

/// What the QR code on the computer carries: `https://<worker>/#p=<pairId>&k=<browserPub>&n=<nonce>`.
/// Anything odd is refused here, before the phone sends a single request.
struct PairingLink: Equatable {
    let origin: URL
    let pairID: String
    let browserPublic: Data
    let nonce: Data

    static func parse(_ text: String) -> Result<PairingLink, PairingLinkError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed), let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty else { return .failure(.notALink) }
        guard scheme == "https" || scheme == "http" else { return .failure(.notALink) }
        let isLocal = host == "localhost" || host == "127.0.0.1"
        guard scheme == "https" || isLocal, components.user == nil, components.password == nil else { return .failure(.insecureOrigin) }

        var origin = URLComponents()
        origin.scheme = scheme
        origin.host = host
        origin.port = components.port
        guard let originURL = origin.url else { return .failure(.notALink) }

        var fields: [String: [String]] = [:]
        for pair in (components.fragment ?? "").split(separator: "&", omittingEmptySubsequences: true) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let name = parts.first else { continue }
            fields[String(name), default: []].append(parts.count > 1 ? String(parts[1]) : "")
        }
        func single(_ name: String) -> Result<String, PairingLinkError> {
            guard let values = fields[name] else { return .failure(.missingField(name)) }
            guard values.count == 1 else { return .failure(.badField(name)) }
            return .success(values[0])
        }

        let pairID: String
        switch single("p") {
        case .failure(let error): return .failure(error)
        case .success(let value):
            guard value.count == 22, Base64URL.decode(value)?.count == 16 else { return .failure(.badField("p")) }
            pairID = value
        }
        let browserPublic: Data
        switch single("k") {
        case .failure(let error): return .failure(error)
        case .success(let value):
            guard let data = Base64URL.decode(value), data.count == 65, data.first == 4 else { return .failure(.badField("k")) }
            browserPublic = data
        }
        let nonce: Data
        switch single("n") {
        case .failure(let error): return .failure(error)
        case .success(let value):
            guard let data = Base64URL.decode(value), data.count == 16 else { return .failure(.badField("n")) }
            nonce = data
        }
        return .success(PairingLink(origin: originURL, pairID: pairID, browserPublic: browserPublic, nonce: nonce))
    }
}
