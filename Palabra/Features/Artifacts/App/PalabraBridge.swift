import Foundation
import WebKit

/// The `WKWebView` side of the bridge: converts the message, defers to `BridgeDispatcher`
/// (all the rules live there), and always replies, so a page's promise never hangs.
@MainActor
final class PalabraBridge: NSObject, WKScriptMessageHandlerWithReply {
    private let dispatcher: BridgeDispatcher
    private let log: ArtifactErrorLog

    init(dispatcher: BridgeDispatcher, log: ArtifactErrorLog) {
        self.dispatcher = dispatcher
        self.log = log
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        let isMainFrame = message.frameInfo.isMainFrame
        guard let body = JSONValue.from(foundation: message.body) else {
            log.append("message: not valid JSON (badMessage)")
            replyHandler(BridgeReply.error(code: "badMessage", message: "The message was not valid JSON.").json.foundationObject, nil)
            return
        }
        // Page-side errors are logged here and never reach the registry.
        if isMainFrame, case .object(let object) = body, object["name"]?.stringValue == "__log" {
            log.append(object["args"]?["message"]?.stringValue ?? "unknown error")
            replyHandler(BridgeReply.ok(.null).json.foundationObject, nil)
            return
        }
        let byteCount = body.jsonString.utf8.count
        let dispatcher = self.dispatcher
        Task { @MainActor in
            let reply = await dispatcher.handle(body: body, byteCount: byteCount, isMainFrame: isMainFrame)
            replyHandler(reply.json.foundationObject, nil)
        }
    }
}
