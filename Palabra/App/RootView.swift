import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var env = environment
        NavigationStack(path: $env.router.path) {
            LibraryView()
                .navigationDestination(for: Router.Destination.self) { destination in
                    switch destination {
                    case .settings:
                        SettingsView()
                    case .wordDetail(let id):
                        WordDetailHost(wordID: id)
                    }
                }
        }
        .tint(Theme.accent)
        .preferredColorScheme(environment.appearanceMode.colorScheme)
        .environment(\.locale, environment.appLanguage.locale)
        .environment(\.layoutDirection, environment.appLanguage.layoutDirection)
        .fullScreenCover(isPresented: onboardingBinding) {
            OnboardingView()
        }
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(get: { !environment.hasCompletedOnboarding }, set: { environment.hasCompletedOnboarding = !$0 })
    }
}
