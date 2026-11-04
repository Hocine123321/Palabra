import AVFoundation
import Foundation
import ReplayKit

/// Records the app's own screen for the tour. The captions and the finger ring are part of the view tree, so they are in
/// the video.
@MainActor
protocol TourRecording: AnyObject {
    /// Nil when recording can run; otherwise why it cannot (restricted, unavailable).
    var unavailableReason: String? { get }
    func start() async -> Bool
    /// Stops and writes the shrunk video to `url`; false when nothing could be written.
    func stop(to url: URL) async -> Bool
}

/// No video: the tour still runs and writes its log.
@MainActor
final class NoTourRecorder: TourRecording {
    var unavailableReason: String? { nil }
    func start() async -> Bool { false }
    func stop(to url: URL) async -> Bool { false }
}

/// `RPScreenRecorder` (in-app capture, microphone off), then a re-encode to a small H.264 file.
@MainActor
final class ReplayKitTourRecorder: TourRecording {
    private var rawURL: URL?

    var unavailableReason: String? {
        let recorder = RPScreenRecorder.shared()
        if !recorder.isAvailable { return "Screen recording is not available on this device right now." }
        return nil
    }

    func start() async -> Bool {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else { return false }
        recorder.isMicrophoneEnabled = false
        do {
            try await recorder.startRecording()
            return true
        } catch {
            return false
        }
    }

    func stop(to url: URL) async -> Bool {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isRecording else { return false }
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent("tour-raw-\(UUID().uuidString).mp4")
        do {
            try await recorder.stopRecording(withOutput: raw)
        } catch {
            return false
        }
        defer { try? FileManager.default.removeItem(at: raw) }
        return await Self.shrink(raw, to: url)
    }

    /// Re-encodes to fit 1920 x 1080 (about 500 px wide for a portrait phone) so the file stays small enough to share.
    private static func shrink(_ source: URL, to destination: URL) async -> Bool {
        try? FileManager.default.removeItem(at: destination)
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) ?? AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            return (try? FileManager.default.copyItem(at: source, to: destination)) != nil
        }
        session.outputURL = destination
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        await session.export()
        if session.status == .completed { return true }
        return (try? FileManager.default.copyItem(at: source, to: destination)) != nil
    }
}
