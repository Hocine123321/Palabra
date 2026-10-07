import SwiftUI

/// What every block view needs to load live data and remember ticks.
struct SpecContext {
    let registry: CapabilityRegistry
    let session: ArtifactSession
    let granted: Set<String>
    let state: SpecStateStore
}

/// Renders a validated `ArtifactSpec`. Every AI string goes through `Text(verbatim:)` and every
/// `ForEach` uses the enumerated offset, never the AI text, as identity.
struct SpecRendererView: View {
    let spec: ArtifactSpec
    let context: SpecContext

    init(spec: ArtifactSpec, registry: CapabilityRegistry, session: ArtifactSession, granted: Set<String>, state: SpecStateStore) {
        self.spec = spec
        self.context = SpecContext(registry: registry, session: session, granted: granted, state: state)
    }

    /// Spec artifacts only bind reads, which are auto-granted: requested ∩ known reads.
    static func grant(requests: [String], registry: CapabilityRegistry) -> Set<String> {
        GrantPolicy.effectiveGrant(kind: .spec, requested: requests, granted: [], registry: registry)
    }

    var body: some View {
        SpecBlockListView(blocks: spec.blocks, context: context)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SpecBlockListView: View {
    let blocks: [SpecBlock]
    let context: SpecContext

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                SpecBlockView(block: block, context: context)
            }
        }
    }
}

struct SpecBlockView: View {
    let block: SpecBlock
    let context: SpecContext

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(verbatim: text)
                .font(level <= 1 ? Theme.Font.title : (level == 2 ? Theme.Font.heading : Theme.Font.rowTitle))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
        case .text(let text):
            Text(verbatim: text)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                        Text(verbatim: ordered ? "\(index + 1)." : "•").foregroundStyle(Theme.inkSecondary)
                        Text(verbatim: item).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .table(let table):
            SpecTableView(table: table, context: context)
        case .chart(let chart):
            SpecChartView(chart: chart, context: context)
        case .stats(let tiles):
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: Theme.Spacing.sm, alignment: .top)], alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(verbatim: tile.value).font(Theme.Font.heading).foregroundStyle(Theme.ink)
                        Text(verbatim: tile.label).font(.caption).foregroundStyle(Theme.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.md)
                    .glassCard(cornerRadius: Theme.Radius.medium)
                    .accessibilityElement(children: .combine)
                }
            }
        case .checklist(let id, let items):
            SpecChecklistView(blockID: id, items: items, state: context.state)
        case .roadmap(let id, let steps):
            SpecRoadmapView(blockID: id, steps: steps, state: context.state)
        case .columns(let children):
            // Adaptive grid: side by side when there is room, stacked on a narrow screen.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: Theme.Spacing.md, alignment: .top)], alignment: .leading, spacing: Theme.Spacing.md) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    SpecBlockView(block: child, context: context)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .section(let title, let children):
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if !title.isEmpty {
                    Text(verbatim: title).font(Theme.Font.heading).foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                SpecBlockListView(blocks: children, context: context)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .glassCard()
        }
    }
}
