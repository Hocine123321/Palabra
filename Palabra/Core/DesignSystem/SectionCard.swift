import SwiftUI

/// A collapsible glass card used for each of the word-detail sections.
struct SectionCard<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    @State private var isExpanded = true
    @ViewBuilder var content: Content

    var body: some View {
        GlassSurface {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Button {
                    Motion.animate(Motion.standard) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: Theme.Spacing.sm + 4) {
                        IconTile(systemImage: systemImage, size: 30)
                        Text(title)
                            .font(Theme.Font.heading)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.bold))
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                            .foregroundStyle(Theme.inkSecondary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isExpanded ? [.isHeader] : [.isHeader, .isButton])

                if isExpanded {
                    content
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(Theme.Spacing.md)
        }
    }
}
