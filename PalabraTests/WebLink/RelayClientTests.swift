import XCTest
@testable import Palabra

final class RelayClientTests: XCTestCase {
    private let room = String(repeating: "ab", count: 16)

    func testThePhoneConnectsInTheAppSeatOfItsRoom() throws {
        let url = RelayClient.endpoint(relay: try XCTUnwrap(URL(string: "wss://palabra-relay.me.workers.dev")), roomID: room)
        XCTAssertEqual(url.absoluteString, "wss://palabra-relay.me.workers.dev/r/\(room)?role=app")
    }

    func testARelayAddressWithAPathOrPortKeepsItAndStillGetsTheSeat() throws {
        let url = RelayClient.endpoint(relay: try XCTUnwrap(URL(string: "ws://192.168.1.5:8787")), roomID: room)
        XCTAssertEqual(url.host, "192.168.1.5")
        XCTAssertEqual(url.port, 8787)
        XCTAssertEqual(url.path, "/r/\(room)")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "role" })?.value, "app")
    }

    func testTheReplacedCodeMatchesTheRelayAndTheHeartbeatChecksOftenEnoughToCatchADeadSocket() {
        XCTAssertEqual(RelayClient.replacedCode, 4005)
        XCTAssertLessThanOrEqual(RelayClient.pingInterval + RelayClient.pingTimeout, 30, "a dead socket is noticed within half a minute")
        XCTAssertGreaterThan(RelayClient.pingTimeout, 0)
    }

    func testAnInvalidRelayAddressOrRoomIsRefused() {
        XCTAssertNil(RelayClient(relayURL: "https://example.com", roomID: room))
        XCTAssertNil(RelayClient(relayURL: "wss://example.com", roomID: "short"))
        XCTAssertNotNil(RelayClient(relayURL: "wss://example.com", roomID: room))
    }
}
