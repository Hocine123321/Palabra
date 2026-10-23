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
        // Measure first: an oversized message is refused before it is converted to `JSONValue` (the old order built the
        // whole value tree, then re-serialised it just to count the bytes).
        guard JSONSerialization.isValidJSONObject(message.body),
              let data = try? JSONSerialization.data(withJSONObject: message.body) else {
            log.append("message: not valid JSON (badMessage)")
            replyHandler(BridgeReply.error(code: "badMessage", message: "The message was not valid JSON.").json.foundationObject, nil)
            return
        }
        let byteCount = data.count
        guard byteCount <= BridgeLimits.maxMessageBytes else {
            log.append("message: too large (badMessage)")
            replyHandler(BridgeReply.error(code: "badMessage", message: "The message is too large.").json.foundationObject, nil)
            return
        }
        guard let body = JSONValue.from(foundation: message.body) else {
            log.append("message: not valid JSON (badMessage)")
            replyHandler(BridgeReply.error(code: "badMessage", message: "The message was not valid JSON.").json.foundationObject, nil)
            return
        }
        // Page-side errors are logged here and never reach the registry.
        if isMainFrame, case .object(let object) = body, object["name"]?.stringValue == "__log" {
            log.append(object["args"]?["message"]?.stringValue ?? "unknown error") // the log clips it
            replyHandler(BridgeReply.ok(.null).json.foundationObject, nil)
            return
        }
        let dispatcher = self.dispatcher
        Task { @MainActor in
            let reply = await dispatcher.handle(body: body, byteCount: byteCount, isMainFrame: isMainFrame)
            replyHandler(reply.json.foundationObject, nil)
        }
    }
}
