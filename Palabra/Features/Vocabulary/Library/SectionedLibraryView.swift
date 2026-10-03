import SwiftUI

/// The library grouped into collapsible AI-made sections, honoring the chosen
/// grid/list layout inside each section.
struct SectionedLibraryView: View {
    let sections: [LibrarySections.Section]
    let layout: SettingsStore.LibraryLayout
    let showTags: Bool
    var onSelect: (Word) -> Void
    var onDeleteRequest: (Word) -> Void

    @State private var collapsed: Set<String> = []

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg, pinnedViews: []) {
            ForEach(sections, id: \.title) { section in
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    header(section)
                    if !collapsed.contains(section.title) {
                        if layout == .grid {
                            HoneycombGrid(words: section.words, onSelect: onSelect, onDeleteRequest: onDeleteRequest)
                        } else {
                            WordListView(words: section.words, showTags: showTags, onSelect: onSelect, onDeleteRequest: onDeleteRequest)
                        }
                    }
                }
            }
        }
    }

    private func header(_ section: LibrarySections.Section) -> some View {
        let isCollapsed = collapsed.contains(section.title)
        return Button {
            Motion.animate(Motion.standard) {
                if isCollapsed { collapsed.remove(section.title) } else { collapsed.insert(section.title) }
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    .foregroundStyle(Theme.inkSecondary)
                if section.isUnorganized {
                    Text(LocalizedStringKey(section.title))
                        .font(Theme.Font.heading).foregroundStyle(Theme.ink)
                } else {
                    Text(verbatim: section.title)
                        .font(Theme.Font.heading).foregroundStyle(Theme.ink)
                }
                Text("\(section.words.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Theme.surface, in: Capsule())
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Horizontal strip of the most-used tags; tapping one filters the library.
struct TagFilterBar: View {
    let tags: [(tag: String, count: Int)]
    @Binding var selected: String?

    var body: some View {
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(tags.prefix(30), id: \.tag) { item in
                        let isOn = selected == item.tag
                        Button {
                            Motion.animate(Motion.quick) { selected = isOn ? nil : item.tag }
                        } label: {
                            Text(verbatim: "#\(item.tag)  \(item.count)")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, Theme.Spacing.sm).padding(.vertical, 6)
                                .background(isOn ? Theme.accent : Theme.surface, in: Capsule())
                                .foregroundStyle(isOn ? Color.white : Theme.inkSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
        }
    }
}
