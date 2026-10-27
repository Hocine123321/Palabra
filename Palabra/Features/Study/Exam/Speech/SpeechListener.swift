import AVFoundation
import Speech

/// Listens to the person say a Spanish word and returns what it heard. Used by speaking questions.
@MainActor
protocol SpeechListening: AnyObject {
    /// False when the phone has no Spanish recognizer (or it is switched off), so speaking questions are not offered.
    var isAvailable: Bool { get }
    /// Asks for speech recognition and microphone access (the system asks once). True when both are allowed.
    func requestAuthorization() async -> Bool
    /// Listens until the person stops talking (or `timeout` passes) and returns the best text, or nil when nothing was heard.
    func listen(timeout: TimeInterval) async -> String?
    func stop()
}

/// The real thing: Apple's speech recognizer for Spanish, on the device when the phone can do it there.
@MainActor
final class SpeechListener: SpeechListening {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<String?, Never>?
    private var latest = ""
    private var silenceTimer: Task<Void, Never>?
    private var limitTimer: Task<Void, Never>?

    /// How long after the last new word the sentence counts as finished.
    private let silenceGap: TimeInterval = 1.2

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    func requestAuthorization() async -> Bool {
        guard await Self.speechAllowed() else { return false }
        return await Self.microphoneAllowed()
    }

    // The system calls these back on its own queues, so the closures are made outside the main actor.
    nonisolated private static func speechAllowed() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    nonisolated private static func microphoneAllowed() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    /// Runs on the audio thread: hands each buffer to the recognizer.
    nonisolated private static func tap(into request: SFSpeechAudioBufferRecognitionRequest) -> (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, _ in request.append(buffer) }
    }

    /// Runs on the recognizer's queue: passes on the text so far, whether it is final, and whether it failed.
    nonisolated private static func resultHandler(_ deliver: @escaping @Sendable (String?, Bool, Bool) -> Void) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in deliver(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil) }
    }

    func listen(timeout: TimeInterval) async -> String? {
        stop()
        guard let recognizer, recognizer.isAvailable else { return nil }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            return nil
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request
        latest = ""

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0), block: Self.tap(into: request))
        engine.prepare()
        do { try engine.start() } catch {
            teardown()
            return nil
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler { [weak self] text, isFinal, failed in
                Task { @MainActor in self?.received(text: text, isFinal: isFinal, failed: failed) }
            })
            limitTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled else { return }
                self?.finish()
            }
        }
    }

    func stop() {
        finish()
    }

    // MARK: - Internals

    private func received(text: String?, isFinal: Bool, failed: Bool) {
        guard continuation != nil else { return }
        if let text, !text.isEmpty {
            latest = text
            // Every new word restarts the silence timer; when it runs out the person has stopped.
            silenceTimer?.cancel()
            silenceTimer = Task { [weak self, gap = silenceGap] in
                try? await Task.sleep(for: .seconds(gap))
                guard !Task.isCancelled else { return }
                self?.finish()
            }
        }
        if isFinal || failed { finish() }
    }

    private func finish() {
        let heard = latest
        teardown()
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: heard.isEmpty ? nil : heard)
    }

    private func teardown() {
        silenceTimer?.cancel()
        limitTimer?.cancel()
        silenceTimer = nil
        limitTimer = nil
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Canned hearing for UI tests (`-UITestStub`): no microphone.
@MainActor
final class StubSpeechListener: SpeechListening {
    var isAvailable: Bool { true }
    var heard: String?

    init(heard: String? = nil) { self.heard = heard }

    func requestAuthorization() async -> Bool { true }
    func listen(timeout: TimeInterval) async -> String? { heard }
    func stop() {}
}
