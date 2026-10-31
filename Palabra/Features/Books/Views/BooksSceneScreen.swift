import SwiftUI

/// The 3D desk with Palabra's own controls over it. The scene draws books, desk and tools; this layer is the 2D UI the scene
/// is not allowed to fake: navigation, tools, Memorize, text size, definitions.
struct BooksSceneScreen: View {
    @Binding var path: [BooksRoute]

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: BooksSceneModel?

    var body: some View {
        let shelf = environment.books
        Group {
            if shelf.library.books.isEmpty {
                EmptyStateView(
                    systemImage: "books.vertical",
                    title: "No books available",
                    message: "Lessons are added to the app in updates."
                )
                .frame(maxHeight: .infinity)
                .background { ScreenBackdrop(style: .rich) }
            } else if let model {
                if model.failure != nil {
                    // The 3D view couldn't start: the plain shelf still works.
                    BookshelfView()
                        .accessibilityIdentifier("booksFallback")
                } else {
                    scene(model)
                }
            } else {
                Color.clear
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if model == nil { model = BooksSceneModel(shelf: shelf) }
        }
    }

    private func scene(_ model: BooksSceneModel) -> some View {
        let preferences = environment.books.preferences
        return GeometryReader { proxy in
            let safe = proxy.safeAreaInsets
            ZStack {
                BooksSceneView(model: model, reducedMotion: reduceMotion)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                    .opacity(model.isReady ? 1 : 0)
                    .animation(Motion.reduced(Motion.standard), value: model.isReady)
                SceneHUD(model: model, path: $path)
            }
            .background(Theme.background)
            .onChange(of: colorScheme, initial: true) { _, scheme in
                model.send(.setAppearance(dark: scheme == .dark))
            }
            .onChange(of: InsetKey(state: model.state, size: proxy.size, top: safe.top, bottom: safe.bottom), initial: true) { _, key in
                model.send(.setInsets(top: key.topInset, bottom: key.bottomInset))
            }
            // Changes made in Settings while the desk is alive.
            .onChange(of: preferences) { old, new in
                if new.textSize != old.textSize { model.send(.setTextSize(new.textSize)) }
                if new.recallLevel != old.recallLevel { model.send(.setLevel(new.recallLevel)) }
                if new.sceneQuality != old.sceneQuality { model.send(.setQuality(new.sceneQuality)) }
            }
        }
        .toolbar(model.state.isReading ? .hidden : .visible, for: .tabBar)
        .overlay {
            if !model.isReady { ProgressView().accessibilityIdentifier("booksLoading") }
        }
    }
}

/// What decides how much of the scene the controls cover: the camera keeps the page clear of it.
private struct InsetKey: Equatable {
    var reading: Bool
    var focus: Bool
    var recall: Bool
    var landscape: Bool
    var top: CGFloat
    var bottom: CGFloat

    init(state: SceneState, size: CGSize, top: CGFloat, bottom: CGFloat) {
        reading = state.isReading
        focus = state.focus
        recall = state.recall
        landscape = size.width > size.height
        self.top = top
        self.bottom = bottom
    }

    var topInset: Double {
        if reading { return Double(top) + (focus ? 12 : 60) }
        return Double(top) + (landscape ? 16 : 56)
    }

    var bottomInset: Double {
        if reading { return Double(bottom) + (focus ? 76 : (recall ? 150 : 92)) }
        return Double(bottom) + (landscape ? 100 : 120)
    }
}
