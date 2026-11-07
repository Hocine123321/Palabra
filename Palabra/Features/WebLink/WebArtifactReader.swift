import Foundation

/// What the web page may know about the person's artifacts. Read-only.
///
/// - The list carries titles and kinds, never payloads.
/// - A `spec` artifact (declarative blocks, no script) is decoded here and sent as a plain JSON page with its tables and charts
///   already resolved by `SpecBindLoader`, so the page has no data-binding logic of its own and never runs a capability for an
///   artifact. Binds are limited to the reads the web page may make anyway (`WebLinkDispatcher.readAllowList`).
/// - An `app` artifact (HTML with script and a bridge to the phone) is **not** sent: it is listed with `runnable: false`. Running
///   untrusted generated script next to the page that holds the link key needs a real sandbox boundary first.
struct WebArtifactReader: Sendable {
    struct Entry: Sendable, Equatable {
        let id: String
        let title: String
        let kind: ArtifactKind
        let updatedAt: Date
    }

    /// All artifacts, newest first.
    let list: @Sendable () async -> [Entry]
    /// The current version's payload for an artifact id, or nil if there is none.
    let payload: @Sendable (_ id: String) async -> Data?
    /// Ticks saved for a checklist or roadmap block id (indices).
    let ticks: @Sendable (_ artifactID: String, _ blockID: String) async -> Set<Int>
    let registry: CapabilityRegistry

    /// Reads a page may bind: the web read allow-list, and only if the registry itself calls them reads.
    private var grant: Set<String> {
        Set(WebLinkDispatcher.readAllowList.filter { registry.capability(named: $0)?.kind == .read })
    }

    func listPayload() async -> JSONValue {
        let iso = ISO8601DateFormatter()
        let items = await list().sorted { $0.updatedAt > $1.updatedAt }.prefix(200).map { entry -> JSONValue in
            .object([
                "id": .string(entry.id), "title": .string(entry.title), "kind": .string(entry.kind.rawValue),
                "runnable": .bool(false),                    // the web page shows spec pages only, for now
                "viewable": .bool(entry.kind == .spec),
                "updatedAt": .string(iso.string(from: entry.updatedAt)),
            ])
        }
        return .array(Array(items))
    }

    /// `nil` = no such artifact, or not one the web may show (an app).
    func page(id: String) async -> JSONValue? {
        guard let entry = await list().first(where: { $0.id == id }), entry.kind == .spec,
              let data = await payload(id), let spec = try? JSONDecoder().decode(ArtifactSpec.self, from: data) else { return nil }
        var blocks: [JSONValue] = []
        for block in spec.blocks.prefix(SpecLimits.maxBlocks) { blocks.append(await render(block, artifactID: id, depth: 0)) }
        return .object(["id": .string(id), "title": .string(entry.title), "blocks": .array(blocks)])
    }

    private func render(_ block: SpecBlock, artifactID: String, depth: Int) async -> JSONValue {
        let session = ArtifactSession(artifactID: nil, dryRun: false)
        switch block {
        case .heading(let level, let text):
            return .object(["type": .string("heading"), "level": .number(Double(min(max(level, 1), 3))), "text": .string(text)])
        case .text(let text):
            return .object(["type": .string("text"), "text": .string(text)])
        case .list(let ordered, let items):
            return .object(["type": .string("list"), "ordered": .bool(ordered), "items": .array(items.map { .string($0) })])
        case .table(let table):
            switch await SpecBindLoader.table(table, registry: registry, session: session, granted: grant) {
            case .loaded(let resolved):
                return .object(["type": .string("table"), "columns": .array(resolved.columns.map { .string($0) }),
                                "rows": .array(resolved.rows.map { .array($0.map { .string($0) }) })])
            case .failed(let message):
                return .object(["type": .string("note"), "text": .string(message)])
            }
        case .chart(let chart):
            switch await SpecBindLoader.chart(chart, registry: registry, session: session, granted: grant) {
            case .loaded(let resolved):
                return .object([
                    "type": .string("chart"), "style": .string(chart.style.rawValue), "title": chart.title.map { .string($0) } ?? .null,
                    "labels": .array(resolved.labels.map { .string($0) }),
                    "series": .array(resolved.series.map { .object(["name": $0.name.map { .string($0) } ?? .null, "values": .array($0.values.map { .number($0) })]) }),
                ])
            case .failed(let message):
                return .object(["type": .string("note"), "text": .string(message)])
            }
        case .stats(let tiles):
            return .object(["type": .string("stats"), "tiles": .array(tiles.map { .object(["label": .string($0.label), "value": .string($0.value)]) })])
        case .checklist(let id, let items):
            let done = await ticks(artifactID, id)
            return .object(["type": .string("checklist"), "items": .array(items.enumerated().map { .object(["text": .string($1), "done": .bool(done.contains($0))]) })])
        case .roadmap(let id, let steps):
            let done = await ticks(artifactID, id)
            return .object(["type": .string("roadmap"), "steps": .array(steps.enumerated().map {
                .object(["title": .string($1.title), "detail": $1.detail.map { .string($0) } ?? .null, "done": .bool(done.contains($0))])
            })])
        case .columns(let children):
            return .object(["type": .string("columns"), "children": .array(await renderAll(children, artifactID: artifactID, depth: depth))])
        case .section(let title, let children):
            return .object(["type": .string("section"), "title": .string(title), "children": .array(await renderAll(children, artifactID: artifactID, depth: depth))])
        }
    }

    private func renderAll(_ blocks: [SpecBlock], artifactID: String, depth: Int) async -> [JSONValue] {
        guard depth + 1 < SpecLimits.maxDepth else { return [] }
        var out: [JSONValue] = []
        for block in blocks.prefix(SpecLimits.maxBlocks) { out.append(await render(block, artifactID: artifactID, depth: depth + 1)) }
        return out
    }
}
