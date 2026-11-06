import Foundation
import Observation
import UIKit

/// Frame timing for the step in progress (a `CADisplayLink` that only measures).
@MainActor
final class TourFrameMeter: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var intervals: [Double] = []

    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    func beginSegment() {
        intervals = []
        last = 0
    }

    func endSegment() -> TourFrameStats {
        let ms = intervals.map { $0 * 1000 }
        guard !ms.isEmpty else { return TourFrameStats() }
        let interval = 1000.0 / Double(max(1, UIScreen.main.maximumFramesPerSecond))
        return TourFrameStats(
            frames: ms.count, averageMs: ms.reduce(0, +) / Double(ms.count), worstMs: ms.max() ?? 0,
            slowFrames: ms.filter { $0 > interval * 1.5 }.count
        )
    }

    @objc private func tick(_ link: CADisplayLink) {
        if last > 0 { intervals.append(link.timestamp - last) }
        last = link.timestamp
    }
}

/// Keeps the person's Books state safe while the tour changes it: a copy is saved before the run and put back at the end, on
/// Stop, and, if the app was killed mid-run, at the next launch.
@MainActor
enum TourSafety {
    private static let key = "tourSavedTextbookState"

    static func save(_ state: TextbookState, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: key) }
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    /// Puts back a copy left by a run that never finished. True when something was restored.
    @discardableResult
    static func restoreIfNeeded(into shelf: BookShelf, defaults: UserDefaults = .standard) -> Bool {
        guard let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(TextbookState.self, from: data) else { return false }
        shelf.state = saved
        defaults.removeObject(forKey: key)
        return true
    }

    static var hasPendingRestore: Bool { UserDefaults.standard.data(forKey: key) != nil }
}

/// Runs the scripted tour: drives the scene through the touch layer, records the screen, checks what each step should have
/// done and writes the log. A failing step does not stop the run.
@MainActor
@Observable
final class TourRunner {
    enum Phase: Equatable { case idle, running, finished }

    private(set) var phase = Phase.idle
    private(set) var caption = ""
    private(set) var stepNumber = 0
    private(set) var stepCount = 0
    private(set) var ringPoint: CGPoint?
    private(set) var report: TourReport?
    private(set) var videoURL: URL?
    private(set) var reportURL: URL?
    /// Shown with the result (recording unavailable, say).
    private(set) var note: String?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let meter = TourFrameMeter()

    var isRunning: Bool { phase == .running }

    func start(host: TourHost, shelf: BookShelf, recorder: TourRecording, wantsVideo: Bool = true, directory: URL? = nil) {
        guard phase != .running else { return }
        phase = .running
        report = nil
        videoURL = nil
        reportURL = nil
        note = nil
        task = Task { await run(host: host, shelf: shelf, recorder: recorder, wantsVideo: wantsVideo, directory: directory) }
    }

    func stop() {
        task?.cancel()
    }

    func dismissResult() {
        phase = .idle
        report = nil
    }

    private func run(host: TourHost, shelf: BookShelf, recorder: TourRecording, wantsVideo: Bool, directory: URL?) async {
        TourSafety.save(shelf.state)
        let controller = host.controller
        let originals = TourScript.Originals(
            dark: controller.isDark, level: controller.recall.level, textSize: controller.textSize, quality: controller.quality
        )
        let steps = TourScript.steps(originals: originals)
        stepCount = steps.count
        let context = TourContext(host: host)
        context.ring = { [weak self] p in self?.ringPoint = p }

        var recorded = false
        if wantsVideo {
            if let reason = recorder.unavailableReason {
                note = reason
            } else {
                recorded = await recorder.start()
                if !recorded { note = "Screen recording did not start; the log was still written." }
            }
        }
        let started = CACurrentMediaTime()
        meter.start()
        var results: [TourStepResult] = []
        for (index, step) in steps.enumerated() {
            if Task.isCancelled { break }
            stepNumber = index + 1
            caption = step.caption
            meter.beginSegment()
            let begin = CACurrentMediaTime() - started
            await step.run(context)
            var failure = step.check(context)
            if failure != nil {
                _ = await context.waitUntil(timeout: step.timeout) { step.check(context) == nil }
                failure = step.check(context)
            }
            results.append(TourStepResult(
                id: step.id, caption: step.caption, start: begin, end: CACurrentMediaTime() - started,
                expected: step.expectation, observed: context.observed(), passed: failure == nil, reason: failure,
                frameStats: meter.endSegment()
            ))
        }
        meter.stop()
        ringPoint = nil
        caption = Task.isCancelled ? "Stopped" : "Done"

        // Leave the scene as it was found, whatever happened.
        if host.state.mode == .reading || host.state.mode == .opening { host.send(.closeBook) }
        _ = await context.waitUntil(timeout: 6) { host.state.mode == .menu }

        let folder = directory ?? Self.defaultDirectory()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = Self.stamp()
        if recorded {
            let url = folder.appendingPathComponent("tour-\(stamp).mp4")
            if await recorder.stop(to: url) { videoURL = url } else { note = (note.map { $0 + " " } ?? "") + "The video could not be saved." }
        }
        let finished = TourReport(
            date: Date(), device: UIDevice.current.model, osVersion: UIDevice.current.systemVersion,
            refreshRate: UIScreen.main.maximumFramesPerSecond, engine: shelf.preferences.sceneEngine.rawValue,
            quality: originals.quality.rawValue, appearance: originals.dark ? "dark" : "light", recorded: videoURL != nil,
            steps: results, warnings: Task.isCancelled ? ["Stopped before the end"] : [], residentMemoryMB: Self.residentMemoryMB()
        )
        if let data = try? finished.encoded() {
            let url = folder.appendingPathComponent("tour-\(stamp).json")
            try? data.write(to: url)
            reportURL = url
        }
        report = finished

        // Put the person's state back.
        TourSafety.restoreIfNeeded(into: shelf)
        phase = .finished
    }

    static func defaultDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return docs.appendingPathComponent("Tours", isDirectory: true)
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    static func residentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
    }
}

/// The host the app uses: the real model and controller, real time.
@MainActor
final class AppTourHost: TourHost {
    private let model: BooksSceneModel
    let controller: BookSceneController

    init(model: BooksSceneModel, controller: BookSceneController) {
        self.model = model
        self.controller = controller
    }

    var state: SceneState { model.state }
    var clock: Double { CACurrentMediaTime() }

    func send(_ command: SceneCommand) { model.send(command) }

    func wait(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}
