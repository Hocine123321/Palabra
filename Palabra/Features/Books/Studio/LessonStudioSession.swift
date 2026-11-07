import Foundation
import Observation

/// A photo waiting to be read: the prepared image that is sent, and a small copy for the screen.
struct StudioPhoto: Equatable, Identifiable {
    let id = UUID()
    let image: AIImage
    let thumbnail: Data
}

/// Drives the Lesson Studio: photos or typed text -> what the AI read (editable) -> a formatted lesson (a draft) ->
/// changes by asking -> Save into the book. Nothing is stored until `save()`; the AI only changes how the text is presented.
@MainActor
@Observable
final class LessonStudioSession {
    enum Stage: Equatable { case input, rawText, draft }
    enum Busy: Equatable { case transcribing, formatting, revising }

    static let maxPhotos = 8
    static let maxRawTextLength = 40_000

    let bookID: String
    private(set) var stage: Stage = .input
    private(set) var busy: Busy?
    /// A message for the person (a `LocalizedStringKey` lookup at the call site); cleared by the next action.
    private(set) var errorMessage: String?

    private(set) var photos: [StudioPhoto] = []
    private(set) var photoProblem: String?
    /// The lesson's source text: typed or pasted by the person, or read from the photos. The person may edit it before formatting.
    var rawText = ""
    /// Doubtful spots the AI reported while reading the photos.
    private(set) var uncertain: [String] = []
    /// How the person wants the lesson to look (never allows adding content).
    var instruction = ""

    /// The chapter to save into; `nil` means "a new chapter called `newChapterTitle`".
    var chapterID: String?
    var newChapterTitle = ""

    private(set) var draft: LessonDraft?
    /// The changes the person has asked for so far, for the conversation under the draft.
    private(set) var changes: [String] = []

    private let environment: AppEnvironment

    init(environment: AppEnvironment, bookID: String) {
        self.environment = environment
        self.bookID = bookID
        chapterID = environment.books.book(id: bookID)?.chapters.last?.id
    }

    var book: Book? { environment.books.book(id: bookID) }
    var isBusy: Bool { busy != nil }

    var canReadPhotos: Bool { !photos.isEmpty && !isBusy }
    var canFormat: Bool { !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBusy }

    // MARK: Photos

    func attachPhoto(_ data: Data) async {
        photoProblem = nil
        guard photos.count < Self.maxPhotos else {
            photoProblem = "You can add up to 8 photos."
            return
        }
        let prepared = await Task.detached(priority: .userInitiated) {
            (full: PhotoPreparer.prepare(data, maxPixelSize: PhotoPreparer.solvePixelSize), thumbnail: PhotoPreparer.prepare(data, maxPixelSize: 160))
        }.value
        guard let full = prepared.full, let thumbnail = prepared.thumbnail else {
            photoProblem = "That photo could not be read."
            return
        }
        photos.append(StudioPhoto(image: full, thumbnail: thumbnail.data))
    }

    func removePhoto(at index: Int) {
        guard photos.indices.contains(index) else { return }
        photos.remove(at: index)
    }

    // MARK: Steps

    /// Reads every photo in order and appends what it says to `rawText`. The person then checks the text before it is formatted.
    func transcribe() async {
        guard canReadPhotos, let book else { return }
        errorMessage = nil
        busy = .transcribing
        defer { busy = nil }
        guard case .success(let credentials) = await resolveCredentials() else { return }
        var pieces: [String] = []
        var doubts: [String] = []
        for (index, photo) in photos.enumerated() {
            switch await author.transcribe(photo: photo.image, apiKey: credentials.key, model: credentials.model, language: book.language) {
            case .success(let result):
                pieces.append(result.text)
                doubts += result.uncertain.map { photos.count > 1 ? "\(index + 1): \($0)" : $0 }
            case .failure(let error):
                errorMessage = error.userMessage
                return
            }
        }
        let existing = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        rawText = String(([existing].filter { !$0.isEmpty } + pieces).joined(separator: "\n\n").prefix(Self.maxRawTextLength))
        uncertain = doubts
        photos = []
        stage = .rawText
    }

    /// Turns `rawText` into a lesson draft.
    func formatDraft() async {
        guard canFormat, let book else { return }
        errorMessage = nil
        busy = .formatting
        defer { busy = nil }
        guard case .success(let credentials) = await resolveCredentials() else { return }
        let result = await author.format(
            rawText: rawText, bookTitle: book.title, language: book.language,
            instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines),
            takenLessonIDs: takenLessonIDs, apiKey: credentials.key, model: credentials.model
        )
        switch result {
        case .success(let value):
            draft = value
            changes = []
            stage = .draft
        case .failure(let error):
            errorMessage = error.userMessage
        }
    }

    /// Asks for a change to the draft. The draft stays as it is when the change fails.
    func revise(_ request: String) async {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let current = draft, let book, !trimmed.isEmpty, !isBusy else { return }
        errorMessage = nil
        busy = .revising
        defer { busy = nil }
        guard case .success(let credentials) = await resolveCredentials() else { return }
        let result = await author.revise(
            current: current.lesson, rawText: rawText, instruction: trimmed,
            bookTitle: book.title, language: book.language, apiKey: credentials.key, model: credentials.model
        )
        switch result {
        case .success(let value):
            draft = value
            changes.append(trimmed)
        case .failure(let error):
            errorMessage = error.userMessage
        }
    }

    func backToText() { if stage == .draft { stage = .rawText } }

    func backToInput() { stage = .input }

    /// Writes the draft into the book (creating the new chapter first when asked) and returns the lesson id.
    func save() throws -> String {
        guard let lesson = draft?.lesson else { throw LessonStoreError.unknownLesson }
        let chapter: String
        if let chapterID {
            chapter = chapterID
        } else {
            let title = newChapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            chapter = try environment.books.addChapter(bookID: bookID, title: title.isEmpty ? lesson.title : title)
        }
        try environment.books.saveLesson(lesson, bookID: bookID, chapterID: chapter)
        return lesson.id
    }

    // MARK: Private

    private var author: LessonAuthor { LessonAuthor(ai: environment.ai) }

    private var takenLessonIDs: Set<String> {
        Set(environment.books.library.books.flatMap(\.chapters).flatMap(\.lessons).map(\.id))
    }

    private func resolveCredentials(repaired: Bool = false) async -> Result<(key: String, model: AIModel), AIError> {
        guard environment.hasAPIKey, let apiKey = environment.apiKey else {
            errorMessage = AIError.missingAPIKey.userMessage
            return .failure(.missingAPIKey)
        }
        guard let model = environment.selectedModel else {
            if environment.selectedModelID != nil, !repaired, await environment.repairMissingModel() != nil {
                return await resolveCredentials(repaired: true)
            }
            let error: AIError = environment.selectedModelID == nil ? .noModelSelected : .modelUnavailable(environment.selectedModelID ?? "")
            errorMessage = error.userMessage
            return .failure(error)
        }
        return .success((apiKey, model))
    }
}
