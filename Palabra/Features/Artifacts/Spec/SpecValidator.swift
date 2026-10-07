import Foundation

/// Every cap the validator enforces. Strings are truncated, never rejected.
enum SpecLimits {
    static let maxBlocks = 60
    static let maxDepth = 4
    static let maxTableColumns = 20
    static let maxTableRows = 200
    static let maxChartPoints = 500
    static let heading = 120
    static let text = 2000
    static let listItem = 300
    static let maxListItems = 100
    static let cell = 200
    static let chartTitle = 80
    static let chartLabel = 40
    static let statLabel = 40
    static let statValue = 60
    static let maxStatTiles = 12
    static let checklistItem = 200
    static let maxChecklistItems = 50
    static let stepTitle = 120
    static let stepDetail = 300
    static let maxSteps = 30
    static let sectionTitle = 120
    /// Block ids become state keys (`spec.<id>`, max 64), so they stay short.
    static let blockID = 40
}

struct ValidatedSpec: Equatable {
    var spec: ArtifactSpec
    /// Sorted, unique capability names the artifact needs (manifest + bindings).
    var requests: [String]
}

enum SpecValidationError: Error, Equatable {
    case empty
    case malformed(String)
}

enum SpecValidator {
    /// Parses the payload (a code fence is tolerated). Unknown blocks are dropped by the decoder.
    static func decode(_ payload: String) -> Result<ArtifactSpec, SpecValidationError> {
        guard let data = CodeFence.strip(payload).data(using: .utf8) else {
            return .failure(.malformed("the payload is not text"))
        }
        do {
            return .success(try JSONDecoder().decode(ArtifactSpec.self, from: data))
        } catch {
            return .failure(.malformed("the payload is not valid JSON with a \"blocks\" array"))
        }
    }

    /// Caps and cleans a decoded spec so it is always safe to render.
    static func validate(_ spec: ArtifactSpec, requests: [String], registry: CapabilityRegistry) -> Result<ValidatedSpec, SpecValidationError> {
        let sanitizer = Sanitizer(registry: registry)
        let blocks = sanitizer.blocks(spec.blocks, depth: 1)
        guard !blocks.isEmpty else { return .failure(.empty) }
        let manifest = requests.filter { name in
            guard let capability = registry.capability(named: name) else { return false }
            return capability.kind == .read || capability.kind == .local
        }
        let needed = Set(manifest).union(sanitizer.bindCapabilities).sorted()
        return .success(ValidatedSpec(spec: ArtifactSpec(blocks: blocks), requests: needed))
    }
}

/// One pass over the block tree, in document order. A class so the shared budget,
/// id set and bind set can be mutated from the recursive calls.
private final class Sanitizer {
    let registry: CapabilityRegistry
    var budget = SpecLimits.maxBlocks
    var usedIDs = Set<String>()
    var bindCapabilities = Set<String>()

    init(registry: CapabilityRegistry) { self.registry = registry }

    func blocks(_ input: [SpecBlock], depth: Int) -> [SpecBlock] {
        input.compactMap { sanitize($0, depth: depth) }
    }

    private func sanitize(_ block: SpecBlock, depth: Int) -> SpecBlock? {
        guard depth <= SpecLimits.maxDepth, budget > 0 else { return nil }
        switch block {
        case .columns(let children):
            budget -= 1
            let kept = blocks(children, depth: depth + 1)
            if kept.isEmpty { budget += 1; return nil }
            return .columns(kept)
        case .section(let title, let children):
            budget -= 1
            let kept = blocks(children, depth: depth + 1)
            if kept.isEmpty { budget += 1; return nil }
            return .section(title: clean(title, SpecLimits.sectionTitle), children: kept)
        default:
            guard let cleaned = leaf(block) else { return nil }
            budget -= 1
            return cleaned
        }
    }

    private func leaf(_ block: SpecBlock) -> SpecBlock? {
        switch block {
        case .heading(let level, let text):
            let value = clean(text, SpecLimits.heading)
            guard !value.isEmpty else { return nil }
            return .heading(level: min(max(level, 1), 3), text: value)
        case .text(let text):
            let value = clean(text, SpecLimits.text)
            return value.isEmpty ? nil : .text(value)
        case .list(let ordered, let items):
            let kept = items.map { clean($0, SpecLimits.listItem) }.filter { !$0.isEmpty }.prefix(SpecLimits.maxListItems)
            return kept.isEmpty ? nil : .list(ordered: ordered, items: Array(kept))
        case .table(let value):
            return sanitizeTable(value)
        case .chart(let value):
            return sanitizeChart(value)
        case .stats(let tiles):
            let kept = tiles
                .map { SpecStatTile(label: clean($0.label, SpecLimits.statLabel), value: clean($0.value, SpecLimits.statValue)) }
                .filter { !($0.label.isEmpty && $0.value.isEmpty) }
                .prefix(SpecLimits.maxStatTiles)
            return kept.isEmpty ? nil : .stats(Array(kept))
        case .checklist(let id, let items):
            let kept = items.map { clean($0, SpecLimits.checklistItem) }.filter { !$0.isEmpty }.prefix(SpecLimits.maxChecklistItems)
            guard !kept.isEmpty else { return nil }
            return .checklist(id: uniqueID(id, fallback: "checklist"), items: Array(kept))
        case .roadmap(let id, let steps):
            let kept = steps.compactMap { step -> SpecRoadmapStep? in
                let title = clean(step.title, SpecLimits.stepTitle)
                guard !title.isEmpty else { return nil }
                let detail = step.detail.map { clean($0, SpecLimits.stepDetail) }
                return SpecRoadmapStep(title: title, detail: (detail?.isEmpty ?? true) ? nil : detail)
            }.prefix(SpecLimits.maxSteps)
            guard !kept.isEmpty else { return nil }
            return .roadmap(id: uniqueID(id, fallback: "roadmap"), steps: Array(kept))
        case .columns, .section:
            return nil // containers are handled in `sanitize`
        }
    }

    private func sanitizeTable(_ table: SpecTable) -> SpecBlock? {
        let columns = table.columns.prefix(SpecLimits.maxTableColumns).map { column in
            SpecColumn(title: clean(column.title, SpecLimits.cell), field: nonEmpty(column.field.map { clean($0, SpecLimits.cell) }))
        }
        guard !columns.isEmpty else { return nil }
        if let bind = table.bind {
            // A bound table is live; any inline rows are ignored.
            guard let valid = validBind(bind) else { return nil }
            return .table(SpecTable(columns: columns, rows: nil, bind: valid))
        }
        let width = columns.count
        let rows = (table.rows ?? []).prefix(SpecLimits.maxTableRows).map { row -> [String] in
            var cells = row.prefix(width).map { clean($0, SpecLimits.cell) }
            while cells.count < width { cells.append("") }
            return cells
        }
        return .table(SpecTable(columns: columns, rows: Array(rows), bind: nil))
    }

    private func sanitizeChart(_ chart: SpecChart) -> SpecBlock? {
        let title = nonEmpty(chart.title.map { clean($0, SpecLimits.chartTitle) })
        if let bind = chart.bind {
            guard let labelField = nonEmpty(chart.labelField.map { clean($0, SpecLimits.cell) }),
                  let valueField = nonEmpty(chart.valueField.map { clean($0, SpecLimits.cell) }),
                  let valid = validBind(bind) else { return nil }
            return .chart(SpecChart(style: chart.style, title: title, labels: nil, series: nil, bind: valid, labelField: labelField, valueField: valueField))
        }
        let series = (chart.series ?? []).map { item in
            SpecChartSeries(
                name: nonEmpty(item.name.map { clean($0, SpecLimits.chartLabel) }),
                values: Array(item.values.filter { $0.isFinite }.prefix(SpecLimits.maxChartPoints))
            )
        }.filter { !$0.values.isEmpty }
        guard !series.isEmpty else { return nil }
        // Labels always line up with the longest series, so the renderer never indexes out of range.
        let count = series.map(\.values.count).max() ?? 0
        let given = (chart.labels ?? []).prefix(count).map { clean($0, SpecLimits.chartLabel) }
        let labels = given + (given.count..<count).map { String($0 + 1) }
        return .chart(SpecChart(style: chart.style, title: title, labels: labels, series: series, bind: nil, labelField: nil, valueField: nil))
    }

    /// A bind is only valid against a known `.read` capability.
    private func validBind(_ bind: SpecBind) -> SpecBind? {
        guard let capability = registry.capability(named: bind.capability), capability.kind == .read else { return nil }
        bindCapabilities.insert(capability.name)
        return bind
    }

    /// Unique across checklists and roadmaps: `c1`, `c1-2`, `c1-3`. Empty ids get a type default.
    private func uniqueID(_ raw: String, fallback: String) -> String {
        let cleaned = clean(raw, SpecLimits.blockID)
        let base = cleaned.isEmpty ? fallback : cleaned
        var candidate = base
        var suffix = 2
        while usedIDs.contains(candidate) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        usedIDs.insert(candidate)
        return candidate
    }

    private func clean(_ value: String, _ limit: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
