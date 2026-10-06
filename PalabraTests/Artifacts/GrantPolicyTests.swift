import XCTest
@testable import Palabra

final class GrantPolicyTests: XCTestCase {
    private let registry = CapabilityRegistry([
        makeCapability("r.read", .read),
        makeCapability("w.write", .write),
        makeCapability("a.ai", .ai),
        makeCapability("l.local", .local),
    ])

    func testSpecAutoGrantsReadAndLocalOnly() {
        for (name, expected) in [("r.read", true), ("l.local", true), ("w.write", false), ("a.ai", false)] {
            let capability = registry.capability(named: name)!
            XCTAssertEqual(GrantPolicy.autoGranted(kind: .spec, capability: capability), expected, name)
        }
    }

    func testAppAutoGrantsOnlyLocal() {
        for (name, expected) in [("r.read", false), ("l.local", true), ("w.write", false), ("a.ai", false)] {
            let capability = registry.capability(named: name)!
            XCTAssertEqual(GrantPolicy.autoGranted(kind: .app, capability: capability), expected, name)
        }
    }

    func testNeedingApprovalIsSortedUniqueAndSkipsUnknown() {
        let needing = GrantPolicy.needingApproval(kind: .app, requested: ["w.write", "r.read", "nope", "w.write", "l.local"], registry: registry)
        XCTAssertEqual(needing.map(\.name), ["r.read", "w.write"])
        XCTAssertTrue(GrantPolicy.needingApproval(kind: .spec, requested: ["r.read", "l.local"], registry: registry).isEmpty)
    }

    func testEffectiveGrantSpec() {
        XCTAssertEqual(
            GrantPolicy.effectiveGrant(kind: .spec, requested: ["r.read", "w.write", "nope"], granted: [], registry: registry),
            ["r.read"]
        )
        XCTAssertEqual(
            GrantPolicy.effectiveGrant(kind: .spec, requested: ["r.read", "w.write"], granted: ["w.write"], registry: registry),
            ["r.read", "w.write"]
        )
    }

    func testEffectiveGrantApp() {
        XCTAssertEqual(
            GrantPolicy.effectiveGrant(kind: .app, requested: ["r.read", "l.local"], granted: [], registry: registry),
            ["l.local"]
        )
        XCTAssertEqual(
            GrantPolicy.effectiveGrant(kind: .app, requested: ["r.read", "l.local"], granted: ["r.read"], registry: registry),
            ["r.read", "l.local"]
        )
    }

    func testGrantNotRequestedIsNotEffective() {
        XCTAssertEqual(
            GrantPolicy.effectiveGrant(kind: .app, requested: [], granted: ["r.read"], registry: registry),
            []
        )
    }
}
