import Foundation

/// Turns a Wolfram|Alpha Full Results API answer (`output=json`) into a `SolveResult`.
/// Tolerant on purpose: Wolfram answers vary (a field is sometimes an object, sometimes an array).
enum WolframParser {
    struct Parsed {
        var result: SolveResult
        /// Image URL for every subpod, shaped like `result.pods[].subpods[]`; nil when a subpod has no image.
        var imageURLs: [[URL?]]
    }

    static func parse(_ data: Data, query: String) -> Result<Parsed, SolveError> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let queryResult = root["queryresult"] as? [String: Any] else {
            return .failure(.malformed)
        }
        if let error = queryResult["error"] as? [String: Any] {
            let message = ((error["msg"] as? String) ?? "").lowercased()
            return .failure(message.contains("appid") ? .invalidKey : .malformed)
        }
        if (queryResult["error"] as? Bool) == true { return .failure(.malformed) }
        guard (queryResult["success"] as? Bool) == true else {
            return .failure(.noResult(suggestions: suggestions(from: queryResult["didyoumeans"])))
        }
        guard let rawPods = queryResult["pods"] as? [[String: Any]], !rawPods.isEmpty else {
            return .failure(.noResult(suggestions: []))
        }

        var pods: [SolvePod] = []
        var urls: [[URL?]] = []
        for raw in rawPods {
            let parsed = pod(from: raw)
            pods.append(parsed.pod)
            urls.append(parsed.urls)
        }
        let interpretation = pods.first { $0.id == "Input" }?.plainText
        return .success(Parsed(result: SolveResult(query: query, interpretation: interpretation, pods: pods), imageURLs: urls))
    }

    /// One pod on its own (the steps call asks for a single pod's state).
    static func pod(from raw: [String: Any]) -> (pod: SolvePod, urls: [URL?]) {
        var subpods: [SolveSubpod] = []
        var urls: [URL?] = []
        for rawSub in (raw["subpods"] as? [[String: Any]]) ?? [] {
            var sub = SolveSubpod(title: (rawSub["title"] as? String) ?? "", plaintext: (rawSub["plaintext"] as? String) ?? "")
            var url: URL?
            if let image = rawSub["img"] as? [String: Any] {
                if let src = image["src"] as? String, let parsed = URL(string: src), parsed.scheme == "https" { url = parsed }
                sub.imageWidth = number(image["width"])
                sub.imageHeight = number(image["height"])
            }
            subpods.append(sub)
            urls.append(url)
        }
        let hasSteps = subpods.contains { $0.title.lowercased().contains("step") }
        let stepsInput = hasSteps ? nil : stepsState(in: raw["states"])
        let pod = SolvePod(
            id: (raw["id"] as? String) ?? "",
            title: (raw["title"] as? String) ?? "",
            primary: (raw["primary"] as? Bool) ?? false,
            subpods: subpods,
            stepsInput: stepsInput,
            hasSteps: hasSteps
        )
        return (pod, urls)
    }

    /// The `podstate` that asks for steps: a state named like "Step-by-step solution" (states can be nested).
    private static func stepsState(in value: Any?) -> String? {
        guard let states = value as? [[String: Any]] else { return nil }
        for state in states {
            if let name = state["name"] as? String, name.lowercased().contains("step"), let input = state["input"] as? String, !input.isEmpty {
                return input
            }
            if let nested = stepsState(in: state["states"]) { return nested }
        }
        return nil
    }

    private static func suggestions(from value: Any?) -> [String] {
        let entries: [[String: Any]]
        if let one = value as? [String: Any] {
            entries = [one]
        } else if let many = value as? [[String: Any]] {
            entries = many
        } else {
            return []
        }
        return Array(entries.compactMap { $0["val"] as? String }.filter { !$0.isEmpty }.prefix(3))
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
