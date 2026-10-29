import SwiftUI
import UIKit

/// Draws one block of a lesson page. Layout depends on the block's kind; the content comes from the lesson file.
struct BlockView: View {
    let block: Block
    let scope: PageScope
    /// Position of the block on its page. Part of every recall key.
    let index: Int

    @Environment(\.bookPalette) private var palette

    private func rich(_ text: String, _ slot: String, font: Font? = nil) -> RichText {
        RichText(text, in: scope, slot: "\(index).\(slot)", font: font)
    }

    var body: some View {
        switch block {
        case .heading(let text, let level):
            heading(text, level)
        case .paragraph(let text):
            rich(text, "p")
                .foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .list(let title, let items, let ordered):
            list(title, items, ordered)
        case .keyPoint(let label, let text):
            keyPoint(label, text)
        case .quote(let text, let source):
            quote(text, source)
        case .timeline(let title, let events):
            timeline(title, events)
        case .stats(let title, let items):
            stats(title, items)
        case .comparison(let title, let corner, let columns, let rows):
            comparison(title, corner, columns, rows)
        case .causeEffect(let title, let stages):
            causeEffect(title, stages)
        case .process(let title, let steps):
            process(title, steps)
        case .definitions(let title, let items):
            definitions(title, items)
        case .image(let panel):
            imagePanel(panel)
        case .unsupported:
            unsupported
        }
    }

    // MARK: Text blocks

    private func heading(_ text: String, _ level: Int) -> some View {
        let style: Font.TextStyle = level <= 1 ? .title : (level == 2 ? .title3 : .headline)
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            rich(text, "h", font: palette.font(style, weight: .bold)).foregroundStyle(palette.ink)
            if level <= 2 {
                Rectangle().fill(palette.accent).frame(width: 36, height: 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func titleView(_ title: String?) -> some View {
        if let title {
            rich(title, "t", font: palette.font(.subheadline, weight: .semibold))
                .foregroundStyle(palette.accent)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func list(_ title: String?, _ items: [String], _ ordered: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm + 2) {
            titleView(title)
            ForEach(items.indices, id: \.self) { i in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm + 2) {
                    Text(verbatim: ordered ? "\(i + 1)" : "•")
                        .font(palette.font(.subheadline, weight: .bold))
                        .foregroundStyle(palette.accent)
                        .frame(minWidth: 16)
                    rich(items[i], "i\(i)")
                        .foregroundStyle(palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func keyPoint(_ label: String?, _ text: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
        return HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(palette.accent).frame(width: 4)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if let label {
                    rich(label, "l", font: palette.font(.caption, weight: .bold)).foregroundStyle(palette.accent)
                }
                rich(text, "k", font: palette.font(.headline, weight: .semibold)).foregroundStyle(palette.ink)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(palette.accent.opacity(0.08), in: shape)
        .clipShape(shape)
    }

    private func quote(_ text: String, _ source: String?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            rich(text, "q", font: palette.font(.title3)).foregroundStyle(palette.ink)
            if let source {
                rich(source, "s", font: palette.font(.footnote)).foregroundStyle(palette.inkSecondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle().fill(palette.rule).frame(width: 3)
        }
    }

    // MARK: Timeline, process

    private func timeline(_ title: String?, _ events: [TimelineEvent]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm + 2) {
            titleView(title)
            ForEach(events.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    VStack(spacing: 0) {
                        Circle().fill(palette.accent).frame(width: 10, height: 10).padding(.top, 6)
                        if i < events.count - 1 {
                            Rectangle().fill(palette.rule).frame(width: 2).frame(maxHeight: .infinity)
                        }
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        rich(events[i].date, "e\(i)d", font: palette.font(.subheadline, weight: .bold).monospacedDigit())
                            .foregroundStyle(palette.accent)
                        rich(events[i].title, "e\(i)t", font: palette.font(.body, weight: .semibold))
                            .foregroundStyle(palette.ink)
                        if let detail = events[i].detail {
                            rich(detail, "e\(i)x", font: palette.font(.callout)).foregroundStyle(palette.inkSecondary)
                        }
                    }
                    .padding(.bottom, Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func process(_ title: String?, _ steps: [ProcessStep]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm + 2) {
            titleView(title)
            ForEach(steps.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    VStack(spacing: 0) {
                        Text(verbatim: "\(i + 1)")
                            .font(palette.font(.footnote, weight: .bold))
                            .foregroundStyle(palette.paper)
                            .frame(width: 26, height: 26)
                            .background(palette.accent, in: Circle())
                        if i < steps.count - 1 {
                            Rectangle().fill(palette.rule).frame(width: 2).frame(maxHeight: .infinity)
                        }
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        rich(steps[i].title, "s\(i)t", font: palette.font(.body, weight: .semibold)).foregroundStyle(palette.ink)
                        if let detail = steps[i].detail {
                            rich(detail, "s\(i)d", font: palette.font(.callout)).foregroundStyle(palette.inkSecondary)
                        }
                    }
                    .padding(.bottom, Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Statistics

    private func stats(_ title: String?, _ items: [StatItem]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm + 2) {
            titleView(title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Theme.Spacing.sm + 4, alignment: .top)], spacing: Theme.Spacing.sm + 4) {
                ForEach(items.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                            rich(items[i].value, "v\(i)", font: palette.font(.title, weight: .bold).monospacedDigit())
                                .foregroundStyle(palette.accent)
                            if let unit = items[i].unit {
                                rich(unit, "u\(i)", font: palette.font(.caption, weight: .semibold)).foregroundStyle(palette.inkSecondary)
                            }
                        }
                        rich(items[i].label, "l\(i)", font: palette.font(.subheadline)).foregroundStyle(palette.ink)
                        if let note = items[i].note {
                            rich(note, "n\(i)", font: palette.font(.caption)).foregroundStyle(palette.inkSecondary)
                        }
                    }
                    .bookCard(palette)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Comparison

    private func comparison(_ title: String?, _ corner: String?, _ columns: [String], _ rows: [ComparisonRow]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm + 2) {
            titleView(title)
            if columns.count >= 2 {
                comparisonGrid(corner, columns, rows)
            } else {
                ForEach(rows.indices, id: \.self) { r in
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        rich(rows[r].label, "r\(r)l", font: palette.font(.headline, weight: .bold)).foregroundStyle(palette.accent)
                        cellLines(rows[r].cells.first ?? "", slot: "r\(r)c0")
                    }
                    .bookCard(palette)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func comparisonGrid(_ corner: String?, _ columns: [String], _ rows: [ComparisonRow]) -> some View {
        let grid = Grid(alignment: .topLeading, horizontalSpacing: Theme.Spacing.md, verticalSpacing: Theme.Spacing.sm) {
            GridRow {
                Text(verbatim: corner ?? "")
                    .font(palette.font(.caption, weight: .bold))
                    .foregroundStyle(palette.accent)
                ForEach(columns.indices, id: \.self) { c in
                    rich(columns[c], "c\(c)", font: palette.font(.caption, weight: .bold)).foregroundStyle(palette.accent)
                }
            }
            Divider()
            ForEach(rows.indices, id: \.self) { r in
                GridRow {
                    rich(rows[r].label, "r\(r)l", font: palette.font(.subheadline, weight: .bold)).foregroundStyle(palette.ink)
                    ForEach(rows[r].cells.indices, id: \.self) { c in
                        cellLines(rows[r].cells[c], slot: "r\(r)c\(c)").frame(minWidth: 120, alignment: .leading)
                    }
                }
                Divider()
            }
        }
        if columns.count > 2 {
            ScrollView(.horizontal, showsIndicators: false) { grid }
        } else {
            grid
        }
    }

    /// A table cell; line breaks in the lesson text become bullet points.
    private func cellLines(_ cell: String, slot: String) -> some View {
        let lines = cell.components(separatedBy: "\n")
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs + 2) {
            ForEach(lines.indices, id: \.self) { i in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    if lines.count > 1 {
                        Text(verbatim: "•").foregroundStyle(palette.accent)
                    }
                    rich(lines[i], "\(slot)n\(i)", font: palette.font(.callout))
                        .foregroundStyle(palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: Cause and effect

    private func causeEffect(_ title: String?, _ stages: [FlowStage]) -> some View {
        VStack(spacing: 0) {
            if let title {
                titleView(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, Theme.Spacing.sm)
            }
            ForEach(stages.indices, id: \.self) { s in
                if s > 0 {
                    Image(systemName: "arrow.down")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(palette.accent)
                        .padding(.vertical, Theme.Spacing.sm)
                        .accessibilityHidden(true)
                }
                stageView(stages[s], s, isLast: s == stages.count - 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stageView(_ stage: FlowStage, _ s: Int, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let label = stage.label {
                rich(label, "s\(s)l", font: palette.font(.caption, weight: .bold)).foregroundStyle(palette.accent)
            }
            ForEach(stage.nodes.indices, id: \.self) { n in
                rich(stage.nodes[n], "s\(s)n\(n)", font: palette.font(.callout, weight: isLast ? .bold : .regular))
                    .foregroundStyle(palette.ink)
                    .bookCard(palette, emphasized: isLast)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Definitions

    private func definitions(_ title: String?, _ items: [DefinitionItem]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm + 4) {
            titleView(title)
            ForEach(items.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    rich(items[i].term, "d\(i)t", font: palette.font(.headline, weight: .bold)).foregroundStyle(palette.accent)
                    rich(items[i].definition, "d\(i)x", font: palette.font(.body)).foregroundStyle(palette.ink)
                }
                .bookCard(palette)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Images

    private func imagePanel(_ panel: ImagePanel) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let image = UIImage(named: panel.name) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(shape)
                    .overlay(shape.stroke(palette.rule, lineWidth: panel.style == "map" ? 2 : 1))
                    .accessibilityLabel(Text(verbatim: panel.alt))
            } else {
                VStack(spacing: Theme.Spacing.xs) {
                    Label("Image not found", systemImage: "photo")
                        .font(.subheadline.weight(.semibold))
                    Text(verbatim: panel.name).font(.caption)
                }
                .foregroundStyle(palette.inkSecondary)
                .bookCard(palette)
            }
            if let caption = panel.caption {
                rich(caption, "cap", font: palette.font(.footnote)).foregroundStyle(palette.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unsupported: some View {
        Label("This content needs a newer version of Palabra.", systemImage: "arrow.down.app")
            .font(.footnote)
            .foregroundStyle(palette.inkSecondary)
            .bookCard(palette)
    }
}
