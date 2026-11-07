import Foundation

/// Just enough HTTP for the pairing hop. Pure, so it is unit tested without a socket.
struct HTTPRequest: Equatable {
    static let maxBytes = 4_096
    let method: String
    let path: String
    let origin: String?
    let body: Data

    enum Parsed: Equatable { case incomplete, invalid, request(HTTPRequest) }

    static func parse(_ data: Data) -> Parsed {
        guard let split = data.range(of: Data("\r\n\r\n".utf8)) else { return data.count >= maxBytes ? .invalid : .incomplete }
        guard let head = String(data: data[..<split.lowerBound], encoding: .utf8) else { return .invalid }
        var lines = head.components(separatedBy: "\r\n")
        let start = lines.removeFirst().split(separator: " ")
        guard start.count == 3, start[2].hasPrefix("HTTP/1.") else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0, length <= 1_024 else { return .invalid }
        let body = data[split.upperBound...]
        if body.count < length { return .incomplete }
        return .request(HTTPRequest(method: String(start[0]), path: String(start[1]), origin: headers["origin"], body: Data(body.prefix(length))))
    }
}

enum HTTPResponse {
    static func status(_ code: Int, json: [String: Any]? = nil, origin: String? = nil) -> Data {
        let reason = [200: "OK", 204: "No Content", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed", 423: "Locked"][code] ?? "Error"
        let body = json.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) } ?? Data()
        var head = "HTTP/1.1 \(code) \(reason)\r\nConnection: close\r\nCache-Control: no-store\r\n"
        // A page opened from file:// sends "Origin: null"; any origin may ask, because the code (not the origin) is the gate.
        head += "Access-Control-Allow-Origin: \(origin ?? "*")\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
        head += "Access-Control-Allow-Headers: content-type\r\nAccess-Control-Allow-Private-Network: true\r\nVary: Origin\r\n"
        if !body.isEmpty { head += "Content-Type: application/json\r\n" }
        head += "Content-Length: \(body.count)\r\n\r\n"
        return Data(head.utf8) + body
    }

    static func make(for request: HTTPRequest, service: PairingService) -> Data {
        let origin = request.origin
        switch (request.method, request.path) {
        case ("OPTIONS", _):
            return status(204, origin: origin)
        case ("GET", "/hello"):
            switch service.hello() {
            case .hello(let nonce): return status(200, json: ["protocol": "palabra-link-v1", "nonce": nonce.hex], origin: origin)
            case .locked(let seconds): return status(423, json: ["error": "locked", "seconds": seconds], origin: origin)
            default: return status(400, json: ["error": "closed"], origin: origin)
            }
        case ("POST", "/pair"):
            guard let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: String],
                  let nonce = object["nonce"].flatMap(Data.init(hexString:)),
                  let proof = object["proof"].flatMap(Data.init(hexString:)) else {
                return status(400, json: ["error": "bad request"], origin: origin)
            }
            switch service.pair(nonce: nonce, proof: proof) {
            case .paired(let iv, let sealed):
                return status(200, json: ["iv": iv.hex, "sealed": sealed.hex], origin: origin)
            case .wrong(let left):
                return status(400, json: ["error": "wrong", "triesLeft": left], origin: origin)
            case .locked(let seconds):
                return status(423, json: ["error": "locked", "seconds": seconds], origin: origin)
            default:
                return status(400, json: ["error": "bad request"], origin: origin)
            }
        case (_, "/hello"), (_, "/pair"):
            return status(405, origin: origin)
        default:
            return status(404, origin: origin)
        }
    }
}

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }

    init?(hexString: String) {
        guard hexString.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
