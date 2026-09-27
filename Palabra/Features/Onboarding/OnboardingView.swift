import SwiftUI

/// Two screens: what the app does, then the API key it needs. "Set Up
/// Later" completes onboarding without a key — the Library then shows the
/// missing-key prompt.
struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var page = 0
    @State private var keyInput = ""
    @State private var isVerifying = false
    @State private var keyError: String?

    var body: some View {
        TabView(selection: $page) {
            welcomePage.tag(0)
            keyPage.tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .background(Theme.background)
    }

    private var welcomePage: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Image(systemName: "text.book.closed.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
            Text("Palabra")
                .font(Theme.Font.serif(34))
                .foregroundStyle(Theme.ink)
            Text("Meet a Spanish word, get an AI explanation with examples, forms and similar words, and keep it in your library for good.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.inkSecondary)
                .padding(.horizontal, Theme.Spacing.xl)
            Spacer()
            Button("Continue") { withAnimation(Motion.standard) { page = 1 } }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            Spacer(minLength: Theme.Spacing.xl)
        }
        .padding()
    }

    private var keyPage: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Text("Add your Google API key")
                .font(Theme.Font.serif(24))
                .foregroundStyle(Theme.ink)
            Text("Palabra uses your own Google AI API key to generate explanations. Get one free at aistudio.google.com.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.inkSecondary)
                .padding(.horizontal, Theme.Spacing.xl)
            SecureField("Google API Key", text: $keyInput)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, Theme.Spacing.xl)
            if let keyError {
                Text(LocalizedStringKey(keyError)).font(.footnote).foregroundStyle(Theme.error)
            }
            Button {
                Task { await saveAndFinish() }
            } label: {
                if isVerifying { ProgressView() } else { Text("Save and Continue") }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isVerifying)
            Button("Set Up Later") { environment.hasCompletedOnboarding = true }
                .foregroundStyle(Theme.inkSecondary)
            Spacer(minLength: Theme.Spacing.xl)
        }
        .padding()
    }

    private func saveAndFinish() async {
        keyError = nil
        isVerifying = true
        defer { isVerifying = false }
        switch await APIKeyEntry.verifyAndSave(keyInput, environment: environment) {
        case .invalid:
            keyError = AIError.invalidAPIKey.userMessage
        case .saved, .savedWithWarning:
            environment.hasCompletedOnboarding = true
        }
    }
}
