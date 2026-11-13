import Foundation

enum MirrorClientError: Error, Equatable {
    case http(status: Int, code: String)
    case offline
    case badResponse
}

/// The Worker's head sequence number and key epoch (0 for a Worker that predates rotation).
struct MirrorState: Equatable {
    let seq: Int
    let epoch: Int
}

struct PutItem: Equatable {
    let id: String
    let sealed: String
    let deleted: Bool
}

/// The phone's side of the Worker's REST API (docs/features/mirroring.md). Bodies and tokens are never logged.
struct MirrorClient {
    let origin: URL
    let session: URLSession

    init(origin: URL, session: URLSession = .shared) {
        self.origin = origin
        self.session = session
    }

    // MARK: Calls

    func createMirror(deviceID: String, ownerTokenHash: String) async throws -> String {
        let json = try await send("POST", "/api/mirrors", body: ["deviceId": deviceID, "ownerTokenHash": ownerTokenHash])
        guard let id = json["mirrorId"] as? String, !id.isEmpty else { throw MirrorClientError.badResponse }
        return id
    }

    func pairJoin(pairID: String, phonePublic: Data) async throws {
        _ = try await send("POST", "/api/pair/\(seg(pairID))/join", body: ["phonePub": Base64URL.encode(phonePublic)])
    }

    func pairReply(pairID: String, sealed: Data) async throws {
        _ = try await send("POST", "/api/pair/\(seg(pairID))/reply", body: ["sealed": Base64URL.encode(sealed)])
    }

    func pairCancel(pairID: String) async throws {
        _ = try await send("POST", "/api/pair/\(seg(pairID))/cancel")
    }

    func addDevice(mirrorID: String, bearer: String, deviceID: String, tokenHash: String) async throws {
        _ = try await send("POST", "/api/m/\(seg(mirrorID))/devices", bearer: bearer, body: ["deviceId": deviceID, "tokenHash": tokenHash])
    }

    func removeDevice(mirrorID: String, bearer: String, deviceID: String) async throws {
        _ = try await send("DELETE", "/api/m/\(seg(mirrorID))/devices/\(seg(deviceID))", bearer: bearer)
    }

    /// Returns the mirror's new sequence number.
    func putItems(mirrorID: String, bearer: String, items: [PutItem]) async throws -> Int {
        let list: [[String: Any]] = items.map { item in
            item.deleted ? ["id": item.id, "sealed": "", "deleted": true] : ["id": item.id, "sealed": item.sealed]
        }
        let json = try await send("PUT", "/api/m/\(seg(mirrorID))/items", bearer: bearer, body: ["items": list])
        guard let seq = json["seq"] as? Int else { throw MirrorClientError.badResponse }
        return seq
    }

    func state(mirrorID: String, bearer: String) async throws -> MirrorState {
        let json = try await send("GET", "/api/m/\(seg(mirrorID))/state", bearer: bearer)
        guard let seq = json["seq"] as? Int else { throw MirrorClientError.badResponse }
        return MirrorState(seq: seq, epoch: json["epoch"] as? Int ?? 0)
    }

    /// Removes `remove` (and every computer without a blob), deletes every stored item and moves the mirror to `epoch`, in one
    /// step on the Worker. `blobs` maps a device id to its sealed new key. Returns the new epoch.
    func rotate(mirrorID: String, bearer: String, epoch: Int, remove: String?, blobs: [String: String]) async throws -> Int {
        let body: [String: Any] = ["epoch": epoch, "remove": remove ?? NSNull(), "blobs": blobs]
        let json = try await send("POST", "/api/m/\(seg(mirrorID))/rotate", bearer: bearer, body: body)
        guard let confirmed = json["epoch"] as? Int else { throw MirrorClientError.badResponse }
        return confirmed
    }

    // MARK: Transport

    private func seg(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func url(for path: String) throws -> URL {
        guard var components = URLComponents(url: origin, resolvingAgainstBaseURL: false) else { throw MirrorClientError.badResponse }
        var prefix = components.path
        while prefix.hasSuffix("/") { prefix.removeLast() }
        components.path = prefix + path
        guard let url = components.url else { throw MirrorClientError.badResponse }
        return url
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .timedOut, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed,
    ]

    private func send(_ method: String, _ path: String, bearer: String? = nil, body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: try url(for: path))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw Self.offlineCodes.contains(error.code) ? MirrorClientError.offline : MirrorClientError.badResponse
        }
        guard let http = response as? HTTPURLResponse else { throw MirrorClientError.badResponse }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(http.statusCode) else {
            throw MirrorClientError.http(status: http.statusCode, code: (json?["error"] as? String) ?? "unknown")
        }
        guard let json else { throw MirrorClientError.badResponse }
        return json
    }
}
