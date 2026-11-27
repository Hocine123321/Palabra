import SwiftUI
import UIKit

/// Settings → Appearance → App Icon: pick the home-screen icon. iOS shows its own short notice when it changes.
struct AppIconPickerView: View {
    @State private var current = AppIconChoice(alternateName: UIApplication.shared.alternateIconName)
    @State private var failed = false
    private let supported = UIApplication.shared.supportsAlternateIcons
    private let thumb: CGFloat = 84
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: 3)

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                header
                GlassSurface {
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                        ForEach(AppIconChoice.allCases) { choice in cell(choice) }
                    }
                    .padding(Theme.Spacing.md)
                }
                footer
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
        }
        .background { ScreenBackdrop(style: .rich) }
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: current)
        .onAppear { current = AppIconChoice(alternateName: UIApplication.shared.alternateIconName) }
    }

    /// The icon in use, large, with its name and one line on its taste.
    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            AppIconThumbnail(choice: current, size: 128)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
                .padding(.top, Theme.Spacing.sm)
            Text(verbatim: current.title).font(Theme.Font.title).foregroundStyle(Theme.ink)
            Text(LocalizedStringKey(current.tagline)).font(.subheadline).foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .animation(Motion.reduced(Motion.quick), value: current)
    }

    private func cell(_ choice: AppIconChoice) -> some View {
        let selected = choice == current
        return Button { select(choice) } label: {
            VStack(spacing: Theme.Spacing.sm) {
                AppIconThumbnail(choice: choice, size: thumb)
                    .padding(4)
                    .overlay {
                        if selected {
                            RoundedRectangle(cornerRadius: thumb * 0.2237 + 4, style: .continuous)
                                .strokeBorder(Theme.accent, lineWidth: 3)
                        }
                    }
                Text(verbatim: choice.title)
                    .font(.footnote.weight(selected ? .bold : .medium))
                    .foregroundStyle(selected ? Theme.accentDeep : Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.95))
        .disabled(!supported)
        .accessibilityLabel(Text(verbatim: choice.title))
        .accessibilityIdentifier("appIcon.\(choice.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var footer: some View {
        Group {
            if !supported {
                Text("This device can't change the app icon.")
            } else if failed {
                Text("Couldn't change the icon.").foregroundStyle(Theme.error)
            } else {
                Text("iOS shows a short notice when the icon changes.")
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.inkSecondary)
        .multilineTextAlignment(.center)
    }

    private func select(_ choice: AppIconChoice) {
        guard choice != current else { return }
        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(choice.alternateName)
                Motion.animate(Motion.quick) { current = choice }
                failed = false
            } catch {
                failed = true
            }
        }
    }
}

/// An icon at `size`, rounded the way iOS rounds home-screen icons.
struct AppIconThumbnail: View {
    let choice: AppIconChoice
    let size: CGFloat

    var body: some View {
        Image(choice.previewAsset)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous).strokeBorder(Theme.inkSecondary.opacity(0.25), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// The Appearance row that opens the picker, showing the icon in use.
struct AppIconSettingsRow: View {
    @State private var current = AppIconChoice(alternateName: UIApplication.shared.alternateIconName)

    var body: some View {
        NavigationLink {
            AppIconPickerView()
        } label: {
            HStack(spacing: Theme.Spacing.sm + 4) {
                AppIconThumbnail(choice: current, size: 30)
                Text("App Icon")
                Spacer()
                Text(verbatim: current.title).foregroundStyle(Theme.inkSecondary)
            }
        }
        .accessibilityIdentifier("appIconRow")
        .onAppear { current = AppIconChoice(alternateName: UIApplication.shared.alternateIconName) }
    }
}
