import SwiftUI
import WebKit

/// The 3D desk and books: `Resources/Books3D/books3d.html` (Three.js, built from `web/books3d`) in a web view. It draws on
/// the GPU and handles touch itself; everything around it is SwiftUI (`BooksSceneScreen`). Nothing is loaded from the network.
struct BooksSceneView: UIViewRepresentable {
    let model: BooksSceneModel
    let reducedMotion: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, reducedMotion: reducedMotion)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(WeakMessageHandler(context.coordinator), name: "palabra")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.navigationDelegate = context.coordinator
        view.allowsLinkPreview = false
        model.run = { [weak view] script in view?.evaluateJavaScript(script, completionHandler: nil) }
        if let url = Self.sceneURL {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            model.fail("books3d.html is not in the app bundle")
        }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.reducedMotion = reducedMotion
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "palabra")
    }

    static var sceneURL: URL? {
        let bundle = Bundle(for: BundleToken.self)
        return bundle.url(forResource: "books3d", withExtension: "html")
            ?? bundle.url(forResource: "books3d", withExtension: "html", subdirectory: "Books3D")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let model: BooksSceneModel
        var reducedMotion: Bool

        init(model: BooksSceneModel, reducedMotion: Bool) {
            self.model = model
            self.reducedMotion = reducedMotion
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let reduced = reducedMotion
            Task { @MainActor in model.start(reducedMotion: reduced) }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in model.fail(error.localizedDescription) }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in model.fail(error.localizedDescription) }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            Task { @MainActor in model.fail("The 3D view stopped") }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let parsed = SceneMessage(body: message.body) else { return }
            Task { @MainActor in model.handle(parsed) }
        }
    }
}

/// `WKUserContentController` keeps its handler alive; this keeps it from keeping the coordinator (and the view) alive too.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
