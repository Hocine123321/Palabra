import XCTest
@testable import Palabra

final class BrowserPresenceTests: XCTestCase {
    func testNothingKnownMeansWaiting() {
        XCTAssertEqual(BrowserPresence().link, .waitingForBrowser)
    }

    func testTheNoticeAfterConnectingLinks() {
        var p = BrowserPresence()
        p.relayConnected()
        XCTAssertEqual(p.link, .waitingForBrowser)
        p.notice(browserHere: true)
        XCTAssertEqual(p.link, .linked)
    }

    func testTheNoticeBeforeConnectingIsNotLost() {
        var p = BrowserPresence()
        p.notice(browserHere: true)              // the relay's text arrived first
        XCTAssertEqual(p.link, .waitingForBrowser, "not connected yet, nothing to show")
        p.relayConnected()
        XCTAssertEqual(p.link, .linked, "the browser was already there; waiting for it would never end")
    }

    func testTheBrowserLeavingAndReturning() {
        var p = BrowserPresence()
        p.relayConnected(); p.notice(browserHere: true)
        p.notice(browserHere: false)
        XCTAssertEqual(p.link, .waitingForBrowser)
        p.notice(browserHere: true)
        XCTAssertEqual(p.link, .linked)
    }

    func testALostConnectionForgetsWhoWasThere() {
        var p = BrowserPresence()
        p.relayConnected(); p.notice(browserHere: true)
        p.relayLost()
        XCTAssertEqual(p.link, .waitingForBrowser)
        p.relayConnected()
        XCTAssertEqual(p.link, .waitingForBrowser, "the new connection must hear from the relay again")
    }
}
