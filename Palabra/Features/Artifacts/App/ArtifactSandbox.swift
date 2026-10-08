import Foundation
import WebKit

/// Everything that confines an app artifact. Loosening anything here needs a matching change in
/// `ArtifactSandboxTests`: these values are the security boundary.
enum ArtifactSandbox {
    static let bridgeName = "palabra"

    /// Inserted into the document before it is loaded.
    static let csp = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; font-src data:"

    /// Blocks every network load. WebKit content rules have no alternation or groups, hence two rules.
    static let blockRulesJSON = """
    [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}},{"trigger":{"url-filter":"^wss?://"},"action":{"type":"block"}}]
    """

    /// Prepends the CSP `<meta>` inside `<head>` (or `<html>`), after any doctype so the page stays in standards mode.
    static func documentWithCSP(_ html: String) -> String {
        let meta = "<meta http-equiv=\"Content-Security-Policy\" content=\"\(csp)\">"
        for pattern in ["<head(\\s[^>]*)?>", "<html(\\s[^>]*)?>"] {
            if let range = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                var result = html
                result.insert(contentsOf: meta, at: range.upperBound)
                return result
            }
        }
        return meta + html
    }

    /// Injected at document start. Defines `window.palabra`; the page's only way out of the sandbox.
    static func shimScript(granted: [String], themeCSS: [String: String], locale: String, dir: String) -> String {
        let grantedJSON = JSONValue.array(granted.map { .string($0) }).jsonString
        let themeJSON = JSONValue.object(themeCSS.mapValues { .string($0) }).jsonString
        return """
        (function () {
          var granted = \(grantedJSON);
          var theme = \(themeJSON);
          var post = function (name, args) {
            return window.webkit.messageHandlers.\(bridgeName).postMessage({ name: name, args: args });
          };
          var log = function (message) {
            try { post("__log", { message: String(message) }); } catch (e) {}
          };
          var call = function (name, args) {
            return post(String(name), args === undefined ? {} : args).then(function (reply) {
              if (reply && reply.ok) { return reply.value; }
              var error = (reply && reply.error) || { code: "failed", message: "No reply from the app" };
              log(name + ": " + error.message);
              return Promise.reject(error);
            }, function (failure) {
              var error = { code: "failed", message: String(failure) };
              log(name + ": " + error.message);
              return Promise.reject(error);
            });
          };
          var root = document.documentElement;
          Object.keys(theme).forEach(function (key) { root.style.setProperty("--" + key, theme[key]); });
          window.palabra = Object.freeze({
            call: call,
            granted: Object.freeze(granted),
            theme: Object.freeze(theme),
            locale: \(JSONValue.string(locale).jsonString),
            dir: \(JSONValue.string(dir).jsonString)
          });
          window.addEventListener("error", function (event) {
            log((event.message || "Script error") + (event.lineno ? " (line " + event.lineno + ")" : ""));
          });
          window.addEventListener("unhandledrejection", function (event) {
            var reason = event.reason;
            log("Unhandled: " + (reason && reason.message ? reason.message : String(reason)));
          });
        })();
        """
    }

    @MainActor
    static func makeConfiguration(handler: WKScriptMessageHandlerWithReply, shim: String, rules: WKContentRuleList?) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.addScriptMessageHandler(handler, contentWorld: .page, name: bridgeName)
        if let rules { controller.add(rules) }
        configuration.userContentController = controller
        return configuration
    }

    /// Compiles (or reuses) the network block list. `nil` means it could not be compiled: do not load the page.
    @MainActor
    static func compileRules() async -> WKContentRuleList? {
        await withCheckedContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "palabra.artifact.block-network", encodedContentRuleList: blockRulesJSON) { list, _ in
                continuation.resume(returning: list)
            }
        }
    }
}

/// Allows exactly one navigation: the initial load of the artifact's own document.
/// Links, forms, redirects and scripted navigation afterwards are all cancelled.
struct NavigationGate {
    private var used = false

    mutating func allowOnce() -> Bool {
        if used { return false }
        used = true
        return true
    }
}
