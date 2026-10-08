import SwiftUI
import WebKit

/// Runs an app artifact in the sandbox. Compiles the network block list first and never loads the page without it.
/// SwiftUI re-renders never reload the page: change `.id(...)` at the call site to load it again.
struct AppRendererView: View {
    let html: String
    let registry: CapabilityRegistry
    let session: ArtifactSession
    let granted: Set<String>
    let log: ArtifactErrorLog
    let colorScheme: ColorScheme
    let language: SupportedLanguage

    @State private var rules: WKContentRuleList?
    @State private var failed = false

    var body: some View {
        Group {
            if let rules {
                AppWebView(html: html, registry: registry, session: session, granted: granted, log: log, colorScheme: colorScheme, language: language, rules: rules)
            } else if failed {
                Text("Couldn't load data").font(.footnote).foregroundStyle(Theme.error)
            } else {
                ProgressView()
            }
        }
        .task {
            guard rules == nil else { return }
            rules = await ArtifactSandbox.compileRules()
            failed = rules == nil
        }
    }
}

private struct AppWebView: UIViewRepresentable {
    let html: String
    let registry: CapabilityRegistry
    let session: ArtifactSession
    let granted: Set<String>
    let log: ArtifactErrorLog
    let colorScheme: ColorScheme
    let language: SupportedLanguage
    let rules: WKContentRuleList

    func makeCoordinator() -> Coordinator { Coordinator(log: log) }

    func makeUIView(context: Context) -> WKWebView {
        let log = self.log
        let granted = self.granted
        let dispatcher = BridgeDispatcher(
            registry: registry,
            session: session,
            granted: { granted },
            onError: { text in Task { @MainActor in log.append(text) } }
        )
        let bridge = PalabraBridge(dispatcher: dispatcher, log: log)
        let shim = ArtifactSandbox.shimScript(
            granted: granted.sorted(),
            themeCSS: ArtifactTheme.variables(for: colorScheme),
            locale: language == .arabic ? "ar" : "en",
            dir: language == .arabic ? "rtl" : "ltr"
        )
        let configuration = ArtifactSandbox.makeConfiguration(handler: bridge, shim: shim, rules: rules)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.loadHTMLString(ArtifactSandbox.documentWithCSP(html), baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: ArtifactSandbox.bridgeName, contentWorld: .page)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private var gate = NavigationGate()
        private let log: ArtifactErrorLog

        init(log: ArtifactErrorLog) { self.log = log }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            gate.allowOnce() ? .allow : .cancel
        }

        /// `window.open` and target=_blank: refused.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            nil
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            log.append("The page stopped unexpectedly.")
        }
    }
}
