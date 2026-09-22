import Foundation

/// The undocumented endpoint the Google Translate web page uses. No key, no
/// prompt, no configuration — and no guarantee it keeps working, since it is not
/// a supported API. It exists here as the zero-setup default so the app does
/// something useful before you have wired up a model.
final class GoogleFreeProvider: TranslationProvider {
    let config: ProviderConfig

    let displayName = "Google (free endpoint)"
    let requiresAPIKey = false
    let delayBetween = Duration.milliseconds(250)

    init(config: ProviderConfig) {
        self.config = config
    }

    func translate(_ text: String, from source: String, to target: String) async throws -> String {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return "" }

        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: source.isEmpty ? "auto" : source),
            URLQueryItem(name: "tl", value: target),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: trimmed),
        ]
        guard let url = components.url else { throw TranslationError.badEndpoint(components.string ?? "") }

        var request = URLRequest(url: url)
        request.timeoutInterval = min(config.timeout, 30)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OpenAICompatibleProvider.friendly(error)
        }
        try OpenAICompatibleProvider.checkStatus(response, body: data)

        return try Self.parse(data)
    }

    /// The reply is a nested array, not an object: `[[["translated","source",…], …], …]`.
    /// Sentence chunks live at `[0][n][0]` and are joined in order. It is tempting
    /// to scrape this with a regex; `JSONSerialization` reads it properly, and
    /// multi-sentence input is exactly where a regex starts dropping chunks.
    static func parse(_ data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = root.first as? [Any]
        else { throw TranslationError.malformedResponse("Google") }

        let pieces = segments.compactMap { ($0 as? [Any])?.first as? String }
        guard !pieces.isEmpty else { throw TranslationError.emptyResponse("Google") }

        return pieces.joined().trimmed
    }
}
