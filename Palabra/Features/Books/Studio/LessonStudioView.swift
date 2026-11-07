import PhotosUI
import SwiftUI

/// Adds a lesson to a book: photos or text in, a formatted draft out, changes by asking, then Save. The look follows the Spanish
/// chat (glass cards, a floating bar); the purpose is different: the AI only presents what the source says.
struct LessonStudioView: View {
    let bookID: String
    var onSaved: (String) -> Void = { _ in }

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var session: LessonStudioSession?
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var changeText = ""
    @State private var saveFailed = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let session { content(session) } else { Color.clear }
            }
            .background(ScreenBackdrop())
            .navigationTitle("Lesson Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .onAppear {
            if session == nil { session = LessonStudioSession(environment: environment, bookID: bookID) }
        }
    }

    // MARK: Content

    private func content(_ session: LessonStudioSession) -> some View {
        @Bindable var bindable = session
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header(session)
                if let message = session.errorMessage {
                    Text(LocalizedStringKey(message)).font(.footnote).foregroundStyle(Theme.error)
                        .accessibilityIdentifier("studioError")
                }
                if saveFailed {
                    Text("The lesson couldn't be saved.").font(.footnote).foregroundStyle(Theme.error)
                }
                switch session.stage {
                case .input: inputStage($bindable)
                case .rawText: rawTextStage($bindable)
                case .draft: draftStage(session)
                }
            }
            .padding(Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .overlay { if let busy = session.busy { busyCard(busy) } }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(session) }
        .photosPicker(isPresented: $showLibrary, selection: $pickedItems, maxSelectionCount: LessonStudioSession.maxPhotos, matching: .images)
        .onChange(of: pickedItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) { await session.attachPhoto(data) }
                }
                pickedItems = []
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(
                onPhoto: { data in
                    showCamera = false
                    Task { await session.attachPhoto(data) }
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
    }

    private func header(_ session: LessonStudioSession) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            IconTile(systemImage: "book.pages.fill", tint: Theme.accent, size: 52)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(verbatim: session.book?.title ?? "").font(Theme.Font.title).foregroundStyle(Theme.ink)
                Text("The AI only arranges what your notes say. It never adds to them.")
                    .font(.subheadline).foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    // MARK: Stage 1: photos or text

    private func inputStage(_ session: Bindable<LessonStudioSession>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            chapterCard(session)
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Photos").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
                photoRow(session.wrappedValue)
                if let problem = session.wrappedValue.photoProblem {
                    Text(LocalizedStringKey(problem)).font(.caption).foregroundStyle(Theme.error)
                }
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Or paste the lesson text").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
                textArea(session.rawText, minHeight: 140)
                    .accessibilityIdentifier("studioTextField")
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("How should it look? (optional)").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
                TextField("For example: use a timeline for the dates", text: session.instruction, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(Theme.Spacing.md)
                    .innerFill(cornerRadius: Theme.Radius.medium)
            }
        }
    }

    private func chapterCard(_ session: Bindable<LessonStudioSession>) -> some View {
        let chapters = session.wrappedValue.book?.chapters ?? []
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Chapter").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
            Picker("Chapter", selection: session.chapterID) {
                ForEach(chapters) { chapter in
                    Text(verbatim: chapter.title).tag(Optional(chapter.id))
                }
                Text("New chapter").tag(String?.none)
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("studioChapterPicker")
            if session.wrappedValue.chapterID == nil {
                TextField("Chapter title", text: session.newChapterTitle)
                    .padding(Theme.Spacing.md)
                    .innerFill(cornerRadius: Theme.Radius.medium)
                    .accessibilityIdentifier("studioNewChapterField")
            }
        }
        .padding(Theme.Spacing.md)
        .glassCard()
    }

    private func photoRow(_ session: LessonStudioSession) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                Menu {
                    if CameraPicker.isAvailable {
                        Button { showCamera = true } label: { Label("Take Photo", systemImage: "camera.fill") }
                    }
                    Button { showLibrary = true } label: { Label("Choose Photo", systemImage: "photo.on.rectangle") }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.accentDeep)
                        .frame(width: 72, height: 72)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                }
                .disabled(session.isBusy)
                .accessibilityLabel("Add Photo")
                .accessibilityIdentifier("studioAddPhoto")
                ForEach(Array(session.photos.enumerated()), id: \.element.id) { entry in
                    ZStack(alignment: .topTrailing) {
                        if let image = UIImage(data: entry.element.thumbnail) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                                .accessibilityLabel("Attached photo")
                        }
                        Button { session.removePhoto(at: entry.offset) } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Theme.onTint, Theme.inkSecondary)
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                        .accessibilityLabel("Remove photo")
                    }
                    .padding(.top, 6)
                    .padding(.trailing, 6)
                }
            }
        }
    }

    private func textArea(_ text: Binding<String>, minHeight: CGFloat) -> some View {
        TextEditor(text: text)
            .scrollContentBackground(.hidden)
            .frame(minHeight: minHeight)
            .padding(Theme.Spacing.sm)
            .innerFill(cornerRadius: Theme.Radius.medium)
            .padding(Theme.Spacing.sm)
            .glassCard()
    }

    // MARK: Stage 2: what the AI read

    private func rawTextStage(_ session: Bindable<LessonStudioSession>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("What I read").font(Theme.Font.heading).foregroundStyle(Theme.ink)
            Text("Check the text below. Fix anything that is wrong before it is formatted.")
                .font(.subheadline).foregroundStyle(Theme.inkSecondary)
            textArea(session.rawText, minHeight: 280)
                .accessibilityIdentifier("studioRawText")
            if !session.wrappedValue.uncertain.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Doubtful spots").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
                    ForEach(session.wrappedValue.uncertain.indices, id: \.self) { i in
                        Text(verbatim: "• " + session.wrappedValue.uncertain[i]).font(.footnote).foregroundStyle(Theme.ink)
                    }
                }
            }
        }
    }

    // MARK: Stage 3: the draft

    @ViewBuilder
    private func draftStage(_ session: LessonStudioSession) -> some View {
        if let draft = session.draft, let book = session.book {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(verbatim: draft.lesson.title).font(Theme.Font.heading).foregroundStyle(Theme.ink)
                preview(draft.lesson, book: book)
                warnings(draft)
                if !session.changes.isEmpty {
                    VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                        ForEach(session.changes.indices, id: \.self) { i in
                            Text(verbatim: session.changes[i])
                                .font(.subheadline)
                                .foregroundStyle(Theme.onTint)
                                .padding(Theme.Spacing.sm + 2)
                                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("Ask for a change", text: $changeText, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($focused)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm + 2)
                        .innerFill(cornerRadius: Theme.Radius.medium)
                        .accessibilityIdentifier("studioChangeField")
                    Button {
                        let request = changeText
                        changeText = ""
                        Task { await session.revise(request) }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.onTint)
                            .frame(width: 38, height: 38)
                            .background(Theme.accent, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(changeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isBusy)
                    .accessibilityLabel("Send")
                    .accessibilityIdentifier("studioChangeSend")
                }
                Text("Changes only affect how it looks. After you add it, you can edit every page in the book.")
                    .font(.caption).foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private func preview(_ lesson: Lesson, book: Book) -> some View {
        let palette = Theme.Textbook.palette(for: book.subject)
        let direction: LayoutDirection = book.isRightToLeft ? .rightToLeft : .leftToRight
        let glossary = lesson.glossary
        return TabView {
            ForEach(Array(lesson.pages.enumerated()), id: \.offset) { entry in
                BookPageView(page: BookPage(
                    id: "\(lesson.id)/\(entry.element.id)", number: entry.offset + 1, chapterID: "draft", lessonID: lesson.id,
                    lessonTitle: lesson.title, page: entry.element, glossary: glossary
                ))
                .tag(entry.offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: 460)
        .background(palette.paper)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .environment(\.layoutDirection, direction)
        .environment(\.bookPalette, palette)
        .environment(ReaderContext())
        .accessibilityIdentifier("studioPreview")
    }

    @ViewBuilder
    private func warnings(_ draft: LessonDraft) -> some View {
        let notes = draft.lesson.transcriptionNotes
        if !draft.isClean || !draft.report.newWords.isEmpty || !notes.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Needs checking").font(.footnote.weight(.semibold)).foregroundStyle(Theme.error)
                if !draft.report.blockedNumbers.isEmpty {
                    warningLine("Numbers that are not in your text:", draft.report.blockedNumbers.joined(separator: "، "))
                }
                if !draft.report.newWords.isEmpty {
                    warningLine("Words that are not in your text:", draft.report.newWords.prefix(12).joined(separator: "، "))
                }
                ForEach(draft.problems.indices, id: \.self) { i in
                    Text(verbatim: "• " + draft.problems[i]).font(.footnote).foregroundStyle(Theme.ink)
                }
                ForEach(notes.indices, id: \.self) { i in
                    Text(verbatim: "• " + notes[i]).font(.footnote).foregroundStyle(Theme.ink)
                }
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .accessibilityIdentifier("studioWarnings")
        }
    }

    private func warningLine(_ title: LocalizedStringKey, _ items: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.footnote).foregroundStyle(Theme.inkSecondary)
            Text(verbatim: items).font(.footnote).foregroundStyle(Theme.ink)
        }
    }

    // MARK: Bar and busy card

    private func bottomBar(_ session: LessonStudioSession) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            switch session.stage {
            case .input:
                if !session.photos.isEmpty {
                    Button { Task { await session.transcribe() } } label: { Text("Read photos") }
                        .buttonStyle(.primary)
                        .disabled(!session.canReadPhotos)
                        .accessibilityIdentifier("studioReadPhotos")
                } else {
                    Button { Task { await session.formatDraft() } } label: { Text("Format lesson") }
                        .buttonStyle(.primary)
                        .disabled(!session.canFormat)
                        .accessibilityIdentifier("studioFormat")
                }
            case .rawText:
                HStack(spacing: Theme.Spacing.sm) {
                    Button("Back") { session.backToInput() }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.large)
                    Button { Task { await session.formatDraft() } } label: { Text("Format lesson") }
                        .buttonStyle(.primary)
                        .disabled(!session.canFormat)
                        .accessibilityIdentifier("studioFormat")
                }
            case .draft:
                HStack(spacing: Theme.Spacing.sm) {
                    Button("Back") { session.backToText() }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.large)
                    Button {
                        saveFailed = false
                        do {
                            let id = try session.save()
                            onSaved(id)
                            dismiss()
                        } catch {
                            saveFailed = true
                        }
                    } label: { Text("Add to book") }
                        .buttonStyle(.primary)
                        .disabled(session.isBusy)
                        .accessibilityIdentifier("studioSave")
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background {
            LinearGradient(colors: [Theme.backgroundBottom.opacity(0), Theme.backgroundBottom.opacity(0.92)], startPoint: .top, endPoint: .bottom)
        }
    }

    private func busyCard(_ busy: LessonStudioSession.Busy) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView().controlSize(.large)
            switch busy {
            case .transcribing: Text("Reading photos…")
            case .formatting: Text("Formatting the lesson…")
            case .revising: Text("Applying your change…")
            }
        }
        .font(Theme.Font.heading)
        .foregroundStyle(Theme.ink)
        .padding(Theme.Spacing.lg)
        .glassCard()
    }
}
