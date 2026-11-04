import Foundation

/// Frame timing while one step ran.
struct TourFrameStats: Codable, Equatable {
    var frames = 0
    var averageMs = 0.0
    var worstMs = 0.0
    /// Frames that took more than 1.5 display intervals.
    var slowFrames = 0
}

/// What happened in one step of the tour.
struct TourStepResult: Codable, Equatable {
    var id: String
    var caption: String
    /// Seconds from the start of the recording.
    var start: Double
    var end: Double
    var expected: String
    var observed: String
    var passed: Bool
    var reason: String?
    var frameStats: TourFrameStats
}

/// The machine-readable log written next to the video (`tour-<date>.json`).
struct TourReport: Codable, Equatable {
    var date: Date
    var device: String
    var osVersion: String
    var refreshRate: Int
    var engine: String
    var quality: String
    var appearance: String
    var recorded: Bool
    var steps: [TourStepResult]
    var warnings: [String]
    var residentMemoryMB: Double

    var passedCount: Int { steps.filter(\.passed).count }
    var failedSteps: [TourStepResult] { steps.filter { !$0.passed } }
    var allPassed: Bool { !steps.isEmpty && failedSteps.isEmpty }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> TourReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TourReport.self, from: data)
    }
}
