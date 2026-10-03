import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var env = environment
        TabView {
            NavigationStack(path: $env.router.path) {
                VocabularyLibraryView()
                    .navigationDestination(for: Router.Destination.self) { destination in
                        switch destination {
                        case .settings:
                            SettingsView()
                        case .wordDetail(let id):
                            WordDetailHost(wordID: id)
                        }
                    }
            }
            .tabItem { Label("Vocabulary", systemImage: "text.book.closed") }

            StudyRootView(cardAccessory: { AnyView(VocabularyCardPronunciation(wordID: $0)) })
                .tabItem { Label("Study", systemImage: "rectangle.stack") }
        }
        .overlay(alignment: .top) { ResilienceOverlay() }
        .tint(Theme.accent)
        .preferredColorScheme(environment.appearanceMode.colorScheme)
        .environment(\.locale, environment.appLanguage.locale)
        .environment(\.layoutDirection, environment.appLanguage.layoutDirection)
        .fullScreenCover(isPresented: onboardingBinding) {
            OnboardingView()
        }
        .onAppear { environment.syncVocabularyCards() }
        // Picks up anything queued offline: once on launch, and again every
        // time the app returns to the foreground (a drain already in
        // progress, or an empty queue, makes this a no-op).
        .task { environment.queueProcessor.drain(environment: environment) }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { environment.queueProcessor.drain(environment: environment) }
        }
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(get: { !environment.hasCompletedOnboarding }, set: { environment.hasCompletedOnboarding = !$0 })
    }
}
