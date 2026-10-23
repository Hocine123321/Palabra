import Foundation

/// Wolfram|Alpha Full Results API. The App ID is the person's own (Keychain); nothing goes through a backend.
struct WolframSolver: MathSolver {
    static let endpoint = URL(string: "https://api.wolframalpha.com/v2/query")!
    /// A typeset image is a few KB; anything bigger is not worth keeping.
    static let maxImageBytes = 600_000

    /// Pod images are only fetched from Wolfram's own hosts over https, so a damaged or tampered reply cannot make
    /// the app request an arbitrary address.
    static func isTrustedImageURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "wolframalpha.com" || host.hasSuffix(".wolframalpha.com")
    }

    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    /// The request for a query (and, for steps, the `podstate` to open). Public so tests can assert what is sent.
    static func requestURL(query: String, appID: String, podstate: String? = nil) -> URL? {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        var items = [
            URLQueryItem(name: "appid", value: appID),
            URLQueryItem(name: "input", value: query),
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "format", value: "image,plaintext"),
            URLQueryItem(name: "mag", value: "2"),
            URLQueryItem(name: "width", value: "560"),
        ]
        if let podstate { items.append(URLQueryItem(name: "podstate", value: podstate)) }
        components?.queryItems = items
        return components?.url
    }

    func solve(query: String, appID: String) async -> Result<SolveResult, SolveError> {
        switch await fetch(query: query, appID: appID, podstate: nil) {
        case .failure(let error): return .failure(error)
        case .success(let parsed):
            var result = await withImages(parsed).result
            result.source = .wolfram
            return .success(result)
        }
    }

    func steps(query: String, podID: String, stepsInput: String, appID: String) async -> Result<SolvePod, SolveError> {
        switch await fetch(query: query, appID: appID, podstate: stepsInput) {
        case .failure(let error):
            if case .noResult = error { return .failure(.noSteps) }
            return .failure(error)
        case .success(let parsed):
            let withImages = await withImages(parsed).result
            guard let pod = withImages.pods.first(where: { $0.id == podID }), pod.hasSteps else { return .failure(.noSteps) }
            return .success(pod)
        }
    }

    // MARK: - Request

    private func fetch(query: String, appID: String, podstate: String?) async -> Result<WolframParser.Parsed, SolveError> {
        guard let url = Self.requestURL(query: query, appID: appID, podstate: podstate) else { return .failure(.malformed) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                switch http.statusCode {
                case 401, 403: return .failure(.invalidKey)
                case 429: return .failure(.rateLimited)
                case 500...599: return .failure(.network)
                default: break
                }
            }
            return WolframParser.parse(data, query: query)
        } catch {
            return .failure(.network)
        }
    }

    // MARK: - Images

    /// Downloads every pod image (they are signed URLs that expire) so the result still looks right later and offline.
    private func withImages(_ parsed: WolframParser.Parsed) async -> WolframParser.Parsed {
        var result = parsed.result
        let session = self.session
        var jobs: [(pod: Int, sub: Int, url: URL)] = []
        for (podIndex, urls) in parsed.imageURLs.enumerated() {
            for (subIndex, url) in urls.enumerated() {
                if let url, Self.isTrustedImageURL(url) { jobs.append((podIndex, subIndex, url)) }
            }
        }
        let downloaded = await withTaskGroup(of: (Int, Int, Data?).self) { group -> [(Int, Int, Data?)] in
            for job in jobs {
                group.addTask {
                    var request = URLRequest(url: job.url)
                    request.timeoutInterval = 20
                    return (job.pod, job.sub, await WolframSolver.download(request, with: session))
                }
            }
            var all: [(Int, Int, Data?)] = []
            for await item in group { all.append(item) }
            return all
        }
        for (podIndex, subIndex, data) in downloaded {
            result.pods[podIndex].subpods[subIndex].imageData = data
        }
        return WolframParser.Parsed(result: result, imageURLs: parsed.imageURLs)
    }

    /// Reads at most `maxImageBytes` (stops as soon as the limit is passed, instead of loading a huge body first).
    private static func download(_ request: URLRequest, with session: URLSession) async -> Data? {
        guard let (stream, response) = try? await session.bytes(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        if response.expectedContentLength > Int64(maxImageBytes) { return nil }
        var data = Data()
        do {
            for try await byte in stream {
                data.append(byte)
                if data.count > maxImageBytes { return nil }
            }
        } catch {
            return nil
        }
        return data.isEmpty ? nil : data
    }
}
