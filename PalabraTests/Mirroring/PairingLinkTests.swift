import XCTest
@testable import Palabra

final class PairingLinkTests: XCTestCase {
    private var vectors: MirrorVectors!

    override func setUpWithError() throws {
        vectors = try MirrorVectors.load()
    }

    private func fragment(p: String? = nil, k: String? = nil, n: String? = nil, extra: String = "") -> String {
        let pairID = p ?? vectors.pair.pairId
        let key = k ?? Base64URL.encode(Data(hex: vectors.pair.browserPubHex))
        let nonce = n ?? Base64URL.encode(Data(hex: vectors.pair.nonceHex))
        return "p=\(pairID)&k=\(key)&n=\(nonce)\(extra)"
    }

    private func link(_ origin: String = "https://x.test", fragment: String? = nil) -> String {
        "\(origin)/#\(fragment ?? self.fragment())"
    }

    func testValidLinkParses() throws {
        let parsed = try PairingLink.parse(link()).get()
        XCTAssertEqual(parsed.origin.absoluteString, "https://x.test")
        XCTAssertEqual(parsed.pairID, vectors.pair.pairId)
        XCTAssertEqual(parsed.browserPublic, Data(hex: vectors.pair.browserPubHex))
        XCTAssertEqual(parsed.nonce, Data(hex: vectors.pair.nonceHex))
    }

    func testOriginKeepsPortAndDropsThePath() throws {
        let parsed = try PairingLink.parse("https://x.test:8443/some/path?q=1#\(fragment())").get()
        XCTAssertEqual(parsed.origin.absoluteString, "https://x.test:8443")
    }

    func testPlainHTTPOnlyForLocalhost() throws {
        XCTAssertEqual(PairingLink.parse(link("http://example.com")), .failure(.insecureOrigin))
        XCTAssertNoThrow(try PairingLink.parse(link("http://localhost:8787")).get())
        XCTAssertNoThrow(try PairingLink.parse(link("http://127.0.0.1:8787")).get())
        XCTAssertEqual(PairingLink.parse(link("https://u:pw@x.test")), .failure(.insecureOrigin))
        XCTAssertEqual(PairingLink.parse(link("ftp://x.test")), .failure(.notALink))
    }

    func testMissingFields() {
        XCTAssertEqual(PairingLink.parse("https://x.test/"), .failure(.missingField("p")))
        let k = Base64URL.encode(Data(hex: vectors.pair.browserPubHex))
        let n = Base64URL.encode(Data(hex: vectors.pair.nonceHex))
        XCTAssertEqual(PairingLink.parse(link(fragment: "k=\(k)&n=\(n)")), .failure(.missingField("p")))
        XCTAssertEqual(PairingLink.parse(link(fragment: "p=\(vectors.pair.pairId)&n=\(n)")), .failure(.missingField("k")))
        XCTAssertEqual(PairingLink.parse(link(fragment: "p=\(vectors.pair.pairId)&k=\(k)")), .failure(.missingField("n")))
    }

    func testBadFields() {
        let pub = Data(hex: vectors.pair.browserPubHex)
        var compressed = pub
        compressed[0] = 2
        XCTAssertEqual(PairingLink.parse(link(fragment: fragment(k: Base64URL.encode(pub.prefix(64))))), .failure(.badField("k")))
        XCTAssertEqual(PairingLink.parse(link(fragment: fragment(k: Base64URL.encode(compressed)))), .failure(.badField("k")))
        XCTAssertEqual(PairingLink.parse(link(fragment: fragment(k: "ABCDEF0123456789ABCDEF"))), .failure(.badField("k")))
        XCTAssertEqual(PairingLink.parse(link(fragment: fragment(n: Base64URL.encode(Data(count: 15))))), .failure(.badField("n")))
        XCTAssertEqual(PairingLink.parse(link(fragment: fragment(p: String(vectors.pair.pairId.dropLast())))), .failure(.badField("p")))
        XCTAssertEqual(PairingLink.parse(link(fragment: fragment(extra: "&p=\(vectors.pair.pairId)"))), .failure(.badField("p")))
        XCTAssertEqual(PairingLink.parse(link(fragment: fragment(p: "a+b/cdefghijklmnopqrstu"))), .failure(.badField("p")))
    }

    func testExtraParametersAndWhitespaceAreTolerated() throws {
        XCTAssertNoThrow(try PairingLink.parse(link(fragment: fragment(extra: "&z=1"))).get())
        XCTAssertNoThrow(try PairingLink.parse("\n  \(link())  \n").get())
    }

    func testNotALink() {
        for text in ["hello world", "", "hello", "just text with spaces"] {
            XCTAssertEqual(PairingLink.parse(text), .failure(.notALink), text)
        }
    }
}
