import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @State private var dueCount = 0

    var body: some View {
        @Bindable var env = environment
        TabView(selection: $env.router.tab) {
            NavigationStack(path: $env.router.path) {
                SpanishHomeView()
                    .navigationDestination(for: Router.Destination.self) { destination in
                        switch destination {
                        case .vocabulary:
                            VocabularyLibraryView()
                        case .wordDetail(let id):
                            WordDetailHost(wordID: id, banner: { AnyView(ReviewNeedBanner(wordID: $0)) }, onAsk: openChat)
                        case .artifacts:
                            ArtifactsListView()
                        case .artifactDetail(let id):
                            ArtifactDetailView(artifactID: id)
                        case .needReview:
                            NeedReviewView()
                        case .chatList:
                            ChatListView()
                        case .chat(let id):
                            ChatView(conversationID: id)
                        }
                    }
            }
            .tabItem { Label("Spanish", systemImage: "text.book.closed") }
            .tag(AppTab.spanish)

            StudyRootView(cardAccessory: { AnyView(VocabularyCardPronunciation(wordID: $0)) })
                .tabItem { Label("Study", systemImage: "rectangle.stack") }
                .badge(dueCount)
                .tag(AppTab.study)

            SolveRootView()
                .tabItem { Label("Solve", systemImage: "function") }
                .tag(AppTab.solve)

            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .overlay(alignment: .top) { ResilienceOverlay() }
        // The deeper orange: toolbar text and link buttons need 4.5:1 on cream, and white labels on prominent buttons need it too.
        .tint(Theme.accentDeep)
        .preferredColorScheme(environment.appearanceMode.colorScheme)
        .environment(\.locale, environment.appLanguage.locale)
        .environment(\.layoutDirection, environment.appLanguage.layoutDirection)
        .fullScreenCover(isPresented: onboardingBinding) {
            OnboardingView()
        }
        .onAppear {
            environment.syncVocabularyCards()
            environment.syncReviewNeeds()
            refreshDueBadge()
        }
        // Reviewing happens on the Study tab; coming back to any tab refreshes the count.
        .onChange(of: environment.router.tab) { _, _ in refreshDueBadge() }
        // Picks up anything queued offline: once on launch, and again every
        // time the app returns to the foreground (a drain already in
        // progress, or an empty queue, makes this a no-op).
        .task { environment.queueProcessor.drain(environment: environment) }
        .task { await environment.migrateLegacyPronunciation() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                environment.queueProcessor.drain(environment: environment)
                refreshDueBadge()
            }
        }
    }

    private func refreshDueBadge() {
        dueCount = DeckCounts.totalDue(environment.cards.counts(now: Date()))
    }

    /// "Ask about this word": find or create the chat for the word (importing the word's old chat the first
    /// time) and push it above the word page. This is the one place that knows both `Word` and `Chat`.
    private func openChat(wordID: UUID, title: String) {
        let id: UUID
        if let existing = environment.chat.conversation(forWordID: wordID) {
            id = existing.id
        } else {
            let legacy = environment.repository.word(id: wordID)?.chat ?? []
            let turns = legacy.filter { $0.status == .sent && !$0.text.isEmpty }.map {
                ChatTurn(role: $0.role == .user ? .user : .assistant, text: $0.text, createdAt: $0.createdAt)
            }
            id = environment.chat.create(title: title, wordID: wordID, turns: turns, now: Date()).id
        }
        environment.router.path.append(.chat(id))
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(get: { !environment.hasCompletedOnboarding }, set: { environment.hasCompletedOnboarding = !$0 })
    }
}
