import SwiftUI

/// The App ID row: masked with Replace / Remove once saved, an entry field before. Used on the Solve tab and in Settings.
struct WolframKeyField: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var input = ""
    @State private var isEditing = false
    @State private var showRemoveConfirm = false
    /// True when shown inside a card on the Solve tab (not in a Settings row): fields get a flat fill, buttons flat capsules.
    private let embedded: Bool

    init(embedded: Bool = false) {
        self.embedded = embedded
    }

    private static let portal = URL(string: "https://developer.wolframalpha.com/")!

    var body: some View {
        let tool = environment.solve
        Group {
            if embedded {
                rows.buttonStyle(.bordered).buttonBorderShape(.capsule)
            } else {
                rows
            }
        }
        .confirmationDialog("Remove your App ID?", isPresented: $showRemoveConfirm) {
            Button("Remove", role: .destructive) { tool.removeAppID() }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var rows: some View {
        let tool = environment.solve
        Group {
            if tool.hasKey, !isEditing {
                HStack {
                    Text("Wolfram|Alpha App ID")
                    Spacer()
                    Text(KeychainStore.mask(tool.appID ?? "")).foregroundStyle(Theme.inkSecondary)
                }
                Button("Replace App ID") { isEditing = true; input = "" }
                Button("Remove App ID", role: .destructive) { showRemoveConfirm = true }
            } else {
                SecureField("Wolfram|Alpha App ID", text: $input)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(minHeight: embedded ? 44 : nil)
                    .padding(.horizontal, embedded ? Theme.Spacing.sm + 4 : 0)
                    .background(embedded ? Theme.fill.opacity(0.7) : Color.clear, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                    .accessibilityIdentifier("wolframKeyField")
                Button("Save App ID") {
                    if tool.saveAppID(input) { input = ""; isEditing = false }
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("saveWolframKeyButton")
                if tool.hasKey {
                    Button("Cancel") { isEditing = false }
                }
                Link(destination: Self.portal) {
                    Label("Get a free App ID", systemImage: "arrow.up.right.square")
                }
            }
        }
    }
}
