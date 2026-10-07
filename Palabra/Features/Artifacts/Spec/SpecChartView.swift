import Charts
import SwiftUI

/// A bar or line chart, inline or bound. Points are plotted by index (so duplicate AI labels
/// stay separate) and the axis shows the label for each index.
struct SpecChartView: View {
    let chart: SpecChart
    let context: SpecContext

    @State private var result: SpecBindResult<ResolvedChart>?
    @Environment(\.scenePhase) private var scenePhase

    private struct Point {
        let index: Int
        let series: String
        let value: Double
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let title = chart.title, !title.isEmpty {
                Text(verbatim: title).font(Theme.Font.rowTitle).foregroundStyle(Theme.ink)
            }
            content
        }
        .task(id: scenePhase) {
            if result == nil || scenePhase == .active { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch result {
        case nil:
            ProgressView().frame(maxWidth: .infinity, minHeight: 44)
        case .failed(let message)?:
            Text(LocalizedStringKey(message)).font(.footnote).foregroundStyle(Theme.error)
        case .loaded(let resolved)?:
            if resolved.values.isEmpty && resolved.series.count <= 1 {
                Text("No data yet").font(.footnote).foregroundStyle(Theme.inkSecondary)
            } else {
                plot(resolved)
            }
        }
    }

    private func points(_ resolved: ResolvedChart) -> [Point] {
        var out: [Point] = []
        for (seriesIndex, series) in resolved.series.enumerated() {
            let name = series.name ?? "#\(seriesIndex + 1)"
            for (index, value) in series.values.enumerated() {
                out.append(Point(index: index, series: name, value: value))
            }
        }
        return out
    }

    private func plot(_ resolved: ResolvedChart) -> some View {
        let data = points(resolved)
        let labels = resolved.labels
        let multi = resolved.series.count > 1
        return Chart(Array(data.enumerated()), id: \.offset) { _, point in
            switch chart.style {
            case .bar:
                BarMark(x: .value("Index", point.index), y: .value("Value", point.value))
                    .foregroundStyle(by: .value("Series", point.series))
                    .position(by: .value("Series", point.series))
            case .line:
                LineMark(x: .value("Index", point.index), y: .value("Value", point.value))
                    .foregroundStyle(by: .value("Series", point.series))
                PointMark(x: .value("Index", point.index), y: .value("Value", point.value))
                    .foregroundStyle(by: .value("Series", point.series))
            }
        }
        .chartForegroundStyleScale(range: [Theme.accent, Color.teal, Color.indigo, Color.orange])
        .chartLegend(multi ? .visible : .hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: min(max(labels.count, 1), 7))) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let index = value.as(Int.self), labels.indices.contains(index) {
                        Text(verbatim: labels[index])
                    }
                }
            }
        }
        .frame(height: 200)
        .padding(Theme.Spacing.md)
        .glassCard(cornerRadius: Theme.Radius.medium)
    }

    private func load() async {
        result = await SpecBindLoader.chart(chart, registry: context.registry, session: context.session, granted: context.granted)
    }
}
