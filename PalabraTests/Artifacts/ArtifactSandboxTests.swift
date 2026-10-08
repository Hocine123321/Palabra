import XCTest
import WebKit
@testable import Palabra

@MainActor
final class ArtifactSandboxTests: XCTestCase {
    func testCSPIsExact() {
        XCTAssertEqual(ArtifactSandbox.csp, "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; font-src data:")
    }

    func testBlockRulesAreValidJSONCoveringEveryNetworkScheme() throws {
        let data = Data(ArtifactSandbox.blockRulesJSON.utf8)
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(rules.count, 2)
        let filters = rules.compactMap { ($0["trigger"] as? [String: Any])?["url-filter"] as? String }
        XCTAssertEqual(filters, ["^https?://", "^wss?://"])
        for rule in rules { XCTAssertEqual((rule["action"] as? [String: Any])?["type"] as? String, "block") }
    }

    func testRulesCompileAndCompilationIsRepeatable() async {
        let first = await ArtifactSandbox.compileRules()
        let second = await ArtifactSandbox.compileRules()
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
    }

    // MARK: document

    func testCSPGoesInsideHeadAndAfterTheDoctype() {
        let result = ArtifactSandbox.documentWithCSP("<!DOCTYPE html><html><head><title>t</title></head><body></body></html>")
        XCTAssertTrue(result.hasPrefix("<!DOCTYPE html><html><head><meta http-equiv=\"Content-Security-Policy\""))
        XCTAssertTrue(result.contains(ArtifactSandbox.csp))
    }

    func testCSPGoesAfterHTMLTagWhenThereIsNoHead() {
        let result = ArtifactSandbox.documentWithCSP("<html lang=\"en\"><body>x</body></html>")
        XCTAssertTrue(result.hasPrefix("<html lang=\"en\"><meta http-equiv"))
    }

    func testHeaderTagIsNotMistakenForHead() {
        let result = ArtifactSandbox.documentWithCSP("<html><body><header>x</header></body></html>")
        XCTAssertTrue(result.hasPrefix("<html><meta http-equiv"))
    }

    func testCSPIsPrependedToAFragment() {
        XCTAssertTrue(ArtifactSandbox.documentWithCSP("<p>x</p>").hasPrefix("<meta http-equiv"))
    }

    // MARK: shim

    private func shim(granted: [String] = ["library.words"], theme: [String: String] = ["ink": "#000000"], locale: String = "en", dir: String = "ltr") -> String {
        ArtifactSandbox.shimScript(granted: granted, themeCSS: theme, locale: locale, dir: dir)
    }

    func testShimDefinesPalabraAPI() {
        let script = shim()
        for part in ["window.palabra", "call:", "granted:", "theme:", "locale:", "dir:", "webkit.messageHandlers.palabra", "\"error\"", "unhandledrejection", "__log"] {
            XCTAssertTrue(script.contains(part), "shim misses \(part)")
        }
    }

    func testShimEmbedsGrantedAsJSONArrayAndEscapesNames() {
        XCTAssertTrue(shim(granted: ["library.words", "storage.get"]).contains(#"["library.words","storage.get"]"#))
        let hostile = shim(granted: [#"a"];alert(1);//"#])
        XCTAssertTrue(hostile.contains(#"["a\"];alert(1);//"]"#))
        XCTAssertFalse(hostile.contains(#"["a"];alert(1)"#))
    }

    func testShimEmbedsThemeLocaleAndDirection() {
        let script = shim(theme: ["ink": "#112233"], locale: "ar", dir: "rtl")
        XCTAssertTrue(script.contains(#"{"ink":"#112233"}"#))
        XCTAssertTrue(script.contains(#"locale: "ar""#))
        XCTAssertTrue(script.contains(#"dir: "rtl""#))
    }

    // MARK: navigation and configuration

    func testNavigationGateAllowsExactlyOneNavigation() {
        var gate = NavigationGate()
        XCTAssertTrue(gate.allowOnce())
        XCTAssertFalse(gate.allowOnce())
        XCTAssertFalse(gate.allowOnce())
    }

    func testConfigurationIsLockedDown() {
        let log = ArtifactErrorLog()
        let dispatcher = BridgeDispatcher(registry: CapabilityRegistry([]), session: ArtifactSession(artifactID: nil, dryRun: true), granted: { [] })
        let bridge = PalabraBridge(dispatcher: dispatcher, log: log)
        let configuration = ArtifactSandbox.makeConfiguration(handler: bridge, shim: "/* shim */", rules: nil)
        XCTAssertFalse(configuration.websiteDataStore.isPersistent)
        XCTAssertFalse(configuration.preferences.javaScriptCanOpenWindowsAutomatically)
        let scripts = configuration.userContentController.userScripts
        XCTAssertEqual(scripts.count, 1)
        XCTAssertEqual(scripts.first?.source, "/* shim */")
        XCTAssertEqual(scripts.first?.injectionTime, .atDocumentStart)
        XCTAssertEqual(scripts.first?.isForMainFrameOnly, true)
    }

    // MARK: theme

    func testThemeVariablesAreSixHexColorsThatFollowTheScheme() {
        let light = ArtifactTheme.variables(for: .light)
        let dark = ArtifactTheme.variables(for: .dark)
        XCTAssertEqual(Set(light.keys), ["ink", "ink-secondary", "surface", "accent", "error", "background"])
        for value in light.values + dark.values {
            XCTAssertNotNil(value.range(of: "^#[0-9A-F]{6}$", options: .regularExpression), "bad color \(value)")
        }
        XCTAssertNotEqual(light["ink"], dark["ink"])
    }
}
