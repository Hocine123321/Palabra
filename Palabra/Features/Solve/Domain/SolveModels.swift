import Foundation

/// One piece of a pod: its plain text, and for Wolfram|Alpha a typeset image (kept as bytes, because the image URLs expire).
struct SolveSubpod: Codable, Equatable, Sendable {
    var title: String = ""
    var plaintext: String = ""
    var imageData: Data?
    var imageWidth: Double?
    var imageHeight: Double?

    init(title: String = "", plaintext: String = "", imageData: Data? = nil, imageWidth: Double? = nil, imageHeight: Double? = nil) {
        self.title = title
        self.plaintext = plaintext
        self.imageData = imageData
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }

    /// Tolerant: stored results written by an older version keep decoding. New fields must be optional.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        plaintext = try c.decodeIfPresent(String.self, forKey: .plaintext) ?? ""
        imageData = try c.decodeIfPresent(Data.self, forKey: .imageData)
        imageWidth = try c.decodeIfPresent(Double.self, forKey: .imageWidth)
        imageHeight = try c.decodeIfPresent(Double.self, forKey: .imageHeight)
    }
}

/// A titled section of the answer ("Result", "Plot", "Decimal approximation", ...).
struct SolvePod: Codable, Equatable, Sendable {
    /// The pod id ("Input", "Result", "Solution", ...).
    var id: String
    var title: String
    var primary: Bool = false
    var subpods: [SolveSubpod] = []
    /// What asks for this pod's steps: Wolfram's `podstate`, or "ai:" followed by the verified answer when Gemini
    /// should write the steps. Nil when none is offered or steps are already here.
    var stepsInput: String?
    /// True when `subpods` already contain the step-by-step part.
    var hasSteps: Bool = false

    init(id: String, title: String, primary: Bool = false, subpods: [SolveSubpod] = [], stepsInput: String? = nil, hasSteps: Bool = false) {
        self.id = id
        self.title = title
        self.primary = primary
        self.subpods = subpods
        self.stepsInput = stepsInput
        self.hasSteps = hasSteps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        primary = try c.decodeIfPresent(Bool.self, forKey: .primary) ?? false
        subpods = try c.decodeIfPresent([SolveSubpod].self, forKey: .subpods) ?? []
        stepsInput = try c.decodeIfPresent(String.self, forKey: .stepsInput)
        hasSteps = try c.decodeIfPresent(Bool.self, forKey: .hasSteps) ?? false
    }

    var plainText: String {
        subpods.map(\.plaintext).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// True when the steps offer is for Gemini to write (not Wolfram's, which costs a free call).
    var stepsAreAIWritten: Bool { stepsInput?.hasPrefix(GeminiMathSolver.stepsPrefix) ?? false }
}

/// Who produced an answer: the math engine on the device, Gemini, or Wolfram|Alpha.
/// Answers saved before this existed have no source and were always Wolfram's.
enum SolveSource: String, Codable, Equatable, Sendable {
    case onDevice
    case gemini
    case wolfram
}

/// What a solved problem looks like. Saved (JSON) in `SolveEntry` so reopening it costs no API call.
struct SolveResult: Codable, Equatable, Sendable {
    var query: String
    var interpretation: String?
    var pods: [SolvePod] = []
    var source: SolveSource?

    init(query: String, interpretation: String? = nil, pods: [SolvePod] = [], source: SolveSource? = nil) {
        self.query = query
        self.interpretation = interpretation
        self.pods = pods
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        query = try c.decodeIfPresent(String.self, forKey: .query) ?? ""
        interpretation = try c.decodeIfPresent(String.self, forKey: .interpretation)
        pods = try c.decodeIfPresent([SolvePod].self, forKey: .pods) ?? []
        source = try c.decodeIfPresent(SolveSource.self, forKey: .source)
    }

    /// True for answers that came from Wolfram|Alpha, including ones saved before `source` existed.
    var isFromWolfram: Bool { source == nil || source == .wolfram }

    /// The pod marked as the main answer, else the first one that is not the echo of the input.
    var answerPod: SolvePod? {
        pods.first(where: \.primary) ?? pods.first { $0.id != "Input" }
    }

    var otherPods: [SolvePod] {
        let answerID = answerPod?.id
        return pods.filter { $0.id != "Input" && $0.id != answerID }
    }

    /// The answer as plain text (for copying and sharing).
    var answerText: String { answerPod?.plainText ?? "" }

    /// The same query on wolframalpha.com (full steps are free to read there).
    var webURL: URL? {
        var components = URLComponents(string: "https://www.wolframalpha.com/input")
        components?.queryItems = [URLQueryItem(name: "i", value: query)]
        return components?.url
    }

    func replacing(_ pod: SolvePod) -> SolveResult {
        var copy = self
        if let index = copy.pods.firstIndex(where: { $0.id == pod.id }) { copy.pods[index] = pod }
        return copy
    }
}

enum SolveError: Error, Equatable {
    case emptyInput
    /// Gemini isn't set up (no key or model), so the problem can't go beyond the on-device engine.
    case missingKey
    /// Wolfram refused the App ID (wrong, or the monthly free calls are used up).
    case invalidKey
    case rateLimited
    case noResult(suggestions: [String])
    case noSteps
    case network
    case malformed

    /// A localization key (shown through `LocalizedStringKey`).
    var userMessage: String {
        switch self {
        case .emptyInput: return "Type or scan a problem first."
        case .missingKey: return "Solving this needs Gemini. Check your API key and model in Settings."
        case .invalidKey: return "Wolfram|Alpha refused the App ID. Check it, or the free calls for this month may be used up."
        case .rateLimited: return "The solver is busy. Try again in a moment."
        case .noResult: return "Couldn't understand this. Check the problem and try again."
        case .noSteps: return "There are no steps available for this one."
        case .network: return "Couldn't reach the solver. Check your connection."
        case .malformed: return "The solver sent an answer the app couldn't read."
        }
    }
}
