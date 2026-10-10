import Foundation

/// One piece of a Wolfram|Alpha pod: typeset image (kept as bytes, because the image URLs expire) and its plain text.
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

/// A titled section of the answer ("Result", "Plot", "Alternate forms", ...).
struct SolvePod: Codable, Equatable, Sendable {
    /// Wolfram's pod id ("Input", "Result", "Solution", ...).
    var id: String
    var title: String
    var primary: Bool = false
    var subpods: [SolveSubpod] = []
    /// The `podstate` value that asks for this pod with steps; nil when none is offered or steps are already here.
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
}

/// What a solved problem looks like. Saved (JSON) in `SolveEntry` so reopening it costs no API call.
struct SolveResult: Codable, Equatable, Sendable {
    var query: String
    var interpretation: String?
    var pods: [SolvePod] = []

    init(query: String, interpretation: String? = nil, pods: [SolvePod] = []) {
        self.query = query
        self.interpretation = interpretation
        self.pods = pods
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        query = try c.decodeIfPresent(String.self, forKey: .query) ?? ""
        interpretation = try c.decodeIfPresent(String.self, forKey: .interpretation)
        pods = try c.decodeIfPresent([SolvePod].self, forKey: .pods) ?? []
    }

    /// The pod Wolfram marks as the main answer, else the first one that is not the echo of the input.
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
        case .missingKey: return "Add your Wolfram|Alpha App ID to solve problems."
        case .invalidKey: return "Wolfram|Alpha refused the App ID. Check it, or the free calls for this month may be used up."
        case .rateLimited: return "Wolfram|Alpha is busy. Try again in a moment."
        case .noResult: return "Wolfram|Alpha couldn't understand this. Check the problem and try again."
        case .noSteps: return "There are no steps available for this one."
        case .network: return "Couldn't reach Wolfram|Alpha. Check your connection."
        case .malformed: return "Wolfram|Alpha sent an answer the app couldn't read."
        }
    }
}
