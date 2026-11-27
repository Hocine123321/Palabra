import SwiftUI
import UIKit

/// The top of Settings: the app's icon (the one the person chose), its name and version, and what the AI is set to.
struct SettingsHeroCard: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var icon = AppIconChoice(alternateName: UIApplication.shared.alternateIconName)

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        CutoutCard(tint: Theme.tileTints[3]) {
            HStack(spacing: Theme.Spacing.md) {
                AppIconThumbnail(choice: icon, size: 68)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Palabra").font(Theme.Font.title)
                    if !version.isEmpty {
                        Text("Version \(version)").font(.footnote)
                    }
                    status
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.md)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous))
        .accessibilityElement(children: .combine)
        .onAppear { icon = AppIconChoice(alternateName: UIApplication.shared.alternateIconName) }
    }

    @ViewBuilder
    private var status: some View {
        if environment.hasAPIKey {
            let parts = [environment.activeProvider.displayName, environment.selectedModel?.displayName].compactMap { $0 }
            Text(verbatim: parts.joined(separator: " · "))
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else {
            Label("Add an API key below", systemImage: "key.fill")
                .font(.footnote.weight(.semibold))
        }
    }
}
