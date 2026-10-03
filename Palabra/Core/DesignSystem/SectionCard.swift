import SwiftUI

/// A collapsible glass card used for each of the four word-detail sections.
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
                    HStack {
                        Label(title, systemImage: systemImage)
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                            .foregroundStyle(Theme.inkSecondary)
                    }
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
