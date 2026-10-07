import SwiftUI

/// One tickable row, shared by checklists and roadmaps.
private struct SpecTickRow: View {
    let title: String
    var detail: String?
    var number: Int?
    let done: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? Theme.accent : Theme.inkSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(verbatim: number.map { "\($0). \(title)" } ?? title)
                        .foregroundStyle(done ? Theme.inkSecondary : Theme.ink)
                        .strikethrough(done)
                        .multilineTextAlignment(.leading)
                    if let detail, !detail.isEmpty {
                        Text(verbatim: detail).font(.footnote).foregroundStyle(Theme.inkSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(done ? .isSelected : [])
    }
}

struct SpecChecklistView: View {
    let blockID: String
    let items: [String]
    let state: SpecStateStore

    @State private var done: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                SpecTickRow(title: item, done: done.contains(index)) { toggle(index) }
            }
        }
        .onAppear { done = state.completed(blockID: blockID) }
    }

    private func toggle(_ index: Int) {
        if done.contains(index) { done.remove(index) } else { done.insert(index) }
        state.setCompleted(blockID: blockID, done)
    }
}

struct SpecRoadmapView: View {
    let blockID: String
    let steps: [SpecRoadmapStep]
    let state: SpecStateStore

    @State private var done: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                SpecTickRow(title: step.title, detail: step.detail, number: index + 1, done: done.contains(index)) { toggle(index) }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Theme.Radius.medium)
        .onAppear { done = state.completed(blockID: blockID) }
    }

    private func toggle(_ index: Int) {
        if done.contains(index) { done.remove(index) } else { done.insert(index) }
        state.setCompleted(blockID: blockID, done)
    }
}
