import XCTest
@testable import Palabra

final class PairingHTTPTests: XCTestCase {
    private func raw(_ method: String, _ path: String, body: String = "", origin: String? = "null") -> Data {
        var head = "\(method) \(path) HTTP/1.1\r\nHost: 192.168.1.20:47615\r\n"
        if let origin { head += "Origin: \(origin)\r\n" }
        head += "Content-Length: \(body.utf8.count)\r\n\r\n"
        return Data((head + body).utf8)
    }

    func testParsesARequestAndKeepsTheOrigin() {
        guard case .request(let r) = HTTPRequest.parse(raw("POST", "/pair", body: "{\"a\":\"b\"}")) else { return XCTFail() }
        XCTAssertEqual(r.method, "POST"); XCTAssertEqual(r.path, "/pair"); XCTAssertEqual(r.origin, "null")
        XCTAssertEqual(String(data: r.body, encoding: .utf8), "{\"a\":\"b\"}")
    }

    func testWaitsForTheRestOfTheBody() {
        let whole = raw("POST", "/pair", body: "{\"a\":\"b\"}")
        XCTAssertEqual(HTTPRequest.parse(whole.dropLast(3)), .incomplete)
        XCTAssertEqual(HTTPRequest.parse(Data("GET /hello HTTP/1.1\r\nHost".utf8)), .incomplete)
    }

    func testRejectsGarbageAndHugeBodies() {
        XCTAssertEqual(HTTPRequest.parse(Data("nonsense\r\n\r\n".utf8)), .invalid)
        XCTAssertEqual(HTTPRequest.parse(Data("GET / HTTP/1.1\r\nContent-Length: 999999\r\n\r\n".utf8)), .invalid)
        XCTAssertEqual(HTTPRequest.parse(Data(repeating: 65, count: HTTPRequest.maxBytes)), .invalid)
    }

    private func respond(_ data: Data, _ service: PairingService) -> (head: String, json: [String: Any]?) {
        guard case .request(let r) = HTTPRequest.parse(data) else { XCTFail("unparsed"); return ("", nil) }
        let out = HTTPResponse.make(for: r, service: service)
        let split = out.range(of: Data("\r\n\r\n".utf8))!
        let head = String(data: out[..<split.lowerBound], encoding: .utf8)!
        return (head, try? JSONSerialization.jsonObject(with: out[split.upperBound...]) as? [String: Any])
    }

    func testPreflightAllowsAFilePageAndPrivateNetworkAccess() {
        let (head, _) = respond(raw("OPTIONS", "/pair"), PairingService())
        XCTAssertTrue(head.hasPrefix("HTTP/1.1 204"))
        XCTAssertTrue(head.contains("Access-Control-Allow-Origin: null"))
        XCTAssertTrue(head.contains("Access-Control-Allow-Private-Network: true"))
    }

    func testFullPairingOverHTTP() throws {
        let service = PairingService()
        service.open(code: "482913")
        let hello = respond(raw("GET", "/hello"), service)
        let nonceHex = try XCTUnwrap(hello.json?["nonce"] as? String)
        let nonce = try XCTUnwrap(Data(hexString: nonceHex))
        let proof = LinkCrypto.pairingProof(code: "482913", nonce: nonce).hex
        let body = "{\"nonce\":\"\(nonceHex)\",\"proof\":\"\(proof)\"}"
        let paired = respond(raw("POST", "/pair", body: body), service)
        XCTAssertTrue(paired.head.hasPrefix("HTTP/1.1 200"))
        XCTAssertNotNil(paired.json?["iv"]); XCTAssertNotNil(paired.json?["sealed"])
    }

    func testWrongCodeAnswers400WithTriesLeftAndLockoutAnswers423() throws {
        let service = PairingService()
        service.open(code: "482913")
        var last: (head: String, json: [String: Any]?) = ("", nil)
        for i in 0..<5 {
            let nonceHex = try XCTUnwrap(respond(raw("GET", "/hello"), service).json?["nonce"] as? String)
            let proof = LinkCrypto.pairingProof(code: "000000", nonce: Data(hexString: nonceHex)!).hex
            last = respond(raw("POST", "/pair", body: "{\"nonce\":\"\(nonceHex)\",\"proof\":\"\(proof)\"}"), service)
            if i == 0 { XCTAssertTrue(last.head.hasPrefix("HTTP/1.1 400")); XCTAssertEqual(last.json?["triesLeft"] as? Int, 4) }
        }
        XCTAssertTrue(last.head.hasPrefix("HTTP/1.1 423"))
        XCTAssertEqual(last.json?["error"] as? String, "locked")
    }

    func testClosedPairingAndUnknownRoutes() {
        XCTAssertTrue(respond(raw("GET", "/hello"), PairingService()).head.hasPrefix("HTTP/1.1 400"))
        XCTAssertTrue(respond(raw("GET", "/other"), PairingService()).head.hasPrefix("HTTP/1.1 404"))
        XCTAssertTrue(respond(raw("DELETE", "/pair"), PairingService()).head.hasPrefix("HTTP/1.1 405"))
    }

    func testPrivateAddresses() {
        XCTAssertTrue(PrivateAddress.isPrivate(ipv4: Data([192, 168, 1, 5])))
        XCTAssertTrue(PrivateAddress.isPrivate(ipv4: Data([10, 0, 0, 2])))
        XCTAssertTrue(PrivateAddress.isPrivate(ipv4: Data([172, 16, 0, 1])))
        XCTAssertTrue(PrivateAddress.isPrivate(ipv4: Data([172, 31, 255, 1])))
        XCTAssertFalse(PrivateAddress.isPrivate(ipv4: Data([172, 32, 0, 1])))
        XCTAssertFalse(PrivateAddress.isPrivate(ipv4: Data([8, 8, 8, 8])))
        XCTAssertTrue(PrivateAddress.isPrivate(ipv6: Data([0xfe, 0x80] + [UInt8](repeating: 0, count: 14))))
        XCTAssertTrue(PrivateAddress.isPrivate(ipv6: Data([0xfd] + [UInt8](repeating: 0, count: 15))))
        XCTAssertFalse(PrivateAddress.isPrivate(ipv6: Data([0x26, 0x06] + [UInt8](repeating: 0, count: 14))))
    }
}
