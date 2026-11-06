import Foundation

/// Finds the capabilities an HTML page uses by reading the page itself, so the person is asked about every one of them.
///
/// The `requests` an AI writes in an envelope are only a promise, and a page from another AI app has no envelope at all. A page may
/// also call a capability without writing `palabra.call("name")` literally (`const CAP = "library.words"`, a helper `api("x")`,
/// a template string, a lookup table). A capability that is not requested is never approved, so the running page gets `notGranted`
/// and breaks. Reading the page closes that gap: any quoted string equal to a registered capability name counts as a request.
enum ArtifactCapabilityScan {
    private static let quoted = try? NSRegularExpression(pattern: #"["'`]([A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+)["'`]"#)

    /// The registered capability names that appear as a quoted string in `html` (sorted, unique).
    static func names(in html: String, registry: CapabilityRegistry) -> [String] {
        let range = NSRange(html.startIndex..., in: html)
        let found = (quoted?.matches(in: html, range: range) ?? []).compactMap { match -> String? in
            guard let r = Range(match.range(at: 1), in: html) else { return nil }
            let name = String(html[r])
            return registry.capability(named: name) == nil ? nil : name
        }
        return Array(Set(found)).sorted()
    }

    /// `declared` (what the envelope or the importer listed) plus everything the page itself uses.
    static func merged(declared: [String], html: String, registry: CapabilityRegistry) -> [String] {
        let known = declared.filter { registry.capability(named: $0) != nil }
        return Array(Set(known).union(names(in: html, registry: registry))).sorted()
    }
}
