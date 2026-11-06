import XCTest
@testable import Palabra

final class CapabilityCatalogTests: XCTestCase {
    private let registry = CapabilityRegistry([
        makeCapability("words.add", .write),
        makeCapability("library.words", .read),
        makeCapability("ai.generate", .ai),
        makeCapability("storage.get", .local),
        makeCapability("library.word", .read),
    ])

    func testAnInteractiveAppSeesEveryCapability() {
        let names = CapabilityCatalog.entries(for: .app, registry: registry).map(\.name)
        XCTAssertEqual(Set(names), Set(registry.all.map(\.name)))
    }

    func testAPageSeesOnlyWhatItCanBind() {
        let entries = CapabilityCatalog.entries(for: .spec, registry: registry)
        XCTAssertEqual(entries.map(\.name), ["library.word", "library.words", "storage.get"])
        XCTAssertFalse(entries.contains { $0.kind == .write || $0.kind == .ai })
    }

    func testAccessMatchesTheRealGrantPolicy() {
        for capability in registry.all {
            let app = CapabilityCatalog.access(of: capability, for: .app)
            XCTAssertEqual(app == .automatic, GrantPolicy.autoGranted(kind: .app, capability: capability), capability.name)
            let page = CapabilityCatalog.access(of: capability, for: .spec)
            if page != .unavailable {
                XCTAssertEqual(page == .automatic, GrantPolicy.autoGranted(kind: .spec, capability: capability), capability.name)
            }
        }
    }

    func testAppsAskForEverythingExceptTheirOwnStorage() {
        let byName = Dictionary(uniqueKeysWithValues: CapabilityCatalog.entries(for: .app, registry: registry).map { ($0.name, $0.access) })
        XCTAssertEqual(byName["library.words"], .askFirst)
        XCTAssertEqual(byName["words.add"], .askFirst)
        XCTAssertEqual(byName["ai.generate"], .askFirst)
        XCTAssertEqual(byName["storage.get"], .automatic)
    }

    func testPagesNeverAsk() {
        XCTAssertTrue(CapabilityCatalog.entries(for: .spec, registry: registry).allSatisfy { $0.access == .automatic })
    }

    func testOrderIsReadsThenWritesThenAIThenStorageAndByNameWithin() {
        XCTAssertEqual(CapabilityCatalog.entries(for: .app, registry: registry).map(\.name),
                       ["library.word", "library.words", "words.add", "ai.generate", "storage.get"])
    }

    func testEntriesCarryTheSummaryAndArguments() throws {
        let capability = Capability(
            name: "demo.thing", kind: .read, summary: "Does a thing.",
            argsSchema: .object(["limit": .string("how many"), "tag": .string("which tag")]),
            returnsSummary: "a list", handler: { _, _ in .success(.null) }
        )
        let entry = try XCTUnwrap(CapabilityCatalog.entries(for: .app, registry: CapabilityRegistry([capability])).first)
        XCTAssertEqual(entry.summary, "Does a thing.")
        XCTAssertEqual(entry.returns, "a list")
        XCTAssertEqual(entry.arguments.map(\.name), ["limit", "tag"])
        XCTAssertEqual(entry.arguments.map(\.detail), ["how many", "which tag"])
    }

    func testAnEmptyRegistryGivesEmptyGroups() {
        let empty = CapabilityRegistry([])
        XCTAssertTrue(CapabilityCatalog.entries(for: .app, registry: empty).isEmpty)
        XCTAssertTrue(CapabilityCatalog.entries(for: .spec, registry: empty).isEmpty)
    }

    /// The two lists on the screen must agree with what the AI is actually handed in the prompt.
    func testTheAppListMatchesWhatThePromptHandsTheAI() {
        let prompt = ArtifactPrompts.exportPrompt(userPrompt: "x", registry: registry, language: .english)
        for entry in CapabilityCatalog.entries(for: .app, registry: registry) {
            XCTAssertTrue(prompt.contains(entry.name), "the prompt must mention \(entry.name)")
        }
    }
}
