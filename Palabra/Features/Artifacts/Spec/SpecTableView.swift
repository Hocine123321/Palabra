import SwiftUI

/// A table, inline or bound. Scrolls horizontally inside its own container so a wide table
/// never stretches the screen.
struct SpecTableView: View {
    let table: SpecTable
    let context: SpecContext

    @State private var result: SpecBindResult<ResolvedTable>?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .task(id: scenePhase) {
                // First appearance always loads; afterwards only when the app becomes active again.
                if result == nil || scenePhase == .active { await load() }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch result {
        case nil:
            ProgressView().frame(maxWidth: .infinity, minHeight: 44)
        case .failed(let message)?:
            Text(LocalizedStringKey(message)) // app-authored constant, safe to localize
                .font(.footnote).foregroundStyle(Theme.error)
        case .loaded(let resolved)?:
            if resolved.rows.isEmpty {
                Text("No data yet").font(.footnote).foregroundStyle(Theme.inkSecondary)
            } else {
                grid(resolved)
            }
        }
    }

    private func grid(_ resolved: ResolvedTable) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.md, verticalSpacing: Theme.Spacing.sm) {
                GridRow {
                    ForEach(Array(resolved.columns.enumerated()), id: \.offset) { _, title in
                        Text(verbatim: title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
                            .frame(minWidth: 80, maxWidth: 220, alignment: .leading)
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(Array(resolved.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(verbatim: cell)
                                .foregroundStyle(Theme.ink)
                                .frame(minWidth: 80, maxWidth: 220, alignment: .leading)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .glassCard(cornerRadius: Theme.Radius.medium)
    }

    private func load() async {
        result = await SpecBindLoader.table(table, registry: context.registry, session: context.session, granted: context.granted)
    }
}
