import Foundation

/// How a photo of a problem is handled.
enum SolvePhotoMode: String, Codable, CaseIterable, Sendable {
    /// The photo itself goes to Gemini, which reads and solves it in one step. Nothing is lost between a reading step and a solving step.
    case sendToGemini
    /// Gemini copies the problem out as text first (the on-device reader if Gemini is unavailable); you check it, then solve.
    case readText
    /// The photo never leaves the device: the on-device reader copies the text, you check it, then solve.
    case readOnDevice
}

/// What the person can tweak about the Solve tab.
struct SolveSettings: Codable, Equatable, Sendable {
    var photoMode: SolvePhotoMode = .sendToGemini
    /// Try the on-device engine before Gemini. Off sends every typed problem straight to Gemini.
    var useOnDeviceEngine = true
    /// A model for Solve only; nil follows the model chosen in Settings.
    var modelID: String?

    static let `default` = SolveSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SolveSettings()
        photoMode = (try? c.decodeIfPresent(SolvePhotoMode.self, forKey: .photoMode)) ?? d.photoMode
        useOnDeviceEngine = try c.decodeIfPresent(Bool.self, forKey: .useOnDeviceEngine) ?? d.useOnDeviceEngine
        modelID = try c.decodeIfPresent(String.self, forKey: .modelID)
    }
}

/// Persists `SolveSettings` and lets the solver (which runs off the main thread) read the current value.
final class SolveSettingsStore: @unchecked Sendable {
    static let defaultsKey = "solveSettings"

    private let lock = NSLock()
    private let defaults: UserDefaults
    private var stored: SolveSettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey), let saved = try? JSONDecoder().decode(SolveSettings.self, from: data) {
            stored = saved
        } else {
            stored = .default
        }
    }

    var value: SolveSettings {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set {
            lock.lock()
            stored = newValue
            lock.unlock()
            if let data = try? JSONEncoder().encode(newValue) { defaults.set(data, forKey: Self.defaultsKey) }
        }
    }
}
