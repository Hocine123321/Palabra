import SwiftUI
import UIKit

/// Settings → Appearance → App Icon: pick the home-screen icon. iOS shows its own short notice when it changes.
struct AppIconPickerView: View {
    @State private var current = AppIconChoice(alternateName: UIApplication.shared.alternateIconName)
    @State private var failed = false
    private let supported = UIApplication.shared.supportsAlternateIcons

    var body: some View {
        Form {
            Section {
                ForEach(AppIconChoice.allCases) { choice in
                    Button { select(choice) } label: { row(choice) }
                        .buttonStyle(.plain)
                        .disabled(!supported)
                        .accessibilityIdentifier("appIcon.\(choice.rawValue)")
                        .accessibilityAddTraits(choice == current ? .isSelected : [])
                }
            } footer: {
                if !supported {
                    Text("This device can't change the app icon.")
                } else if failed {
                    Text("Couldn't change the icon.").foregroundStyle(Theme.error)
                } else {
                    Text("iOS shows a short notice when the icon changes.")
                }
            }
            .themedSection()
        }
        .glassScreen()
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { current = AppIconChoice(alternateName: UIApplication.shared.alternateIconName) }
    }

    private func row(_ choice: AppIconChoice) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            AppIconThumbnail(choice: choice, size: 60)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: choice.title).font(.headline).foregroundStyle(Theme.ink)
                Text(LocalizedStringKey(choice.tagline)).font(.footnote).foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
            if choice == current {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).font(.title3)
            }
        }
        .contentShape(Rectangle())
    }

    private func select(_ choice: AppIconChoice) {
        guard choice != current else { return }
        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(choice.alternateName)
                current = choice
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
