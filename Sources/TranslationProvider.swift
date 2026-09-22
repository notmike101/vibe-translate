import Foundation

/// What every translation backend has to provide.
///
/// `translate` is `async` rather than blocking: the call suspends instead of
/// holding a thread, and because every provider is `Sendable` the work runs off
/// the main actor without any hand-rolled locking.
protocol TranslationProvider: Sendable {
    var displayName: String { get }
    var requiresAPIKey: Bool { get }

    /// Courtesy pause between consecutive requests, for endpoints that rate-limit.
    var delayBetween: Duration { get }

    /// Takes text with source/target language codes and returns the translation.
    func translate(_ text: String, from source: String, to target: String) async throws -> String
}

extension TranslationProvider {
    var delayBetween: Duration { .zero }
}

/// Providers that can enumerate the models they are able to run.
protocol ModelListingProvider: TranslationProvider {
    func availableModels() async throws -> [String]
}

/// Providers that can emit the translation as it is generated. Worth having for
/// local models, where a long reply can take a while to finish.
protocol StreamingTranslationProvider: TranslationProvider {
    func translateStream(_ text: String, from source: String, to target: String)
        -> AsyncThrowingStream<String, Error>
}

/// Prompt substitution, kept out of the provider so the Settings window can show
/// the same filled text the model will actually receive.
enum PromptTemplate {
    static let defaultSystem = """
        You are a translation engine. Translate the user's text from {source} to {target}.
        Reply with the translation ONLY — no quotes, no notes, no explanation, no romanization.
        Preserve formatting tokens, markup, numbers, units and proper nouns exactly as written.
        If the text is already in {target}, return it unchanged.
        """

    static let defaultUser = "{text}"

    /// Supported placeholders: `{source}` `{target}` `{source_code}`
    /// `{target_code}` `{text}`.
    static let placeholders = ["{source}", "{target}", "{source_code}", "{target_code}", "{text}"]

    static func fill(_ template: String, text: String?, from source: String, to target: String) -> String {
        var out = template
            .replacingOccurrences(of: "{source_code}", with: source)
            .replacingOccurrences(of: "{target_code}", with: target)
            .replacingOccurrences(of: "{source}", with: Language.name(for: source))
            .replacingOccurrences(of: "{target}", with: Language.name(for: target))
        if let text { out = out.replacingOccurrences(of: "{text}", with: text) }
        return out
    }
}

/// A bulk translator can afford to swallow failures and return the input
/// unchanged — a batch of 2,000 strings should not die on one bad row. Translating
/// one box at a time wants the opposite: say what went wrong.
enum TranslationError: LocalizedError, Equatable {
    case missingAPIKey(String)
    case missingEndpoint(String)
    case badEndpoint(String)
    case http(status: Int, body: String)
    case emptyResponse(String)
    case malformedResponse(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "\(provider): no API key configured."
        case .missingEndpoint(let provider):
            return "\(provider): no endpoint configured."
        case .badEndpoint(let url):
            return "Not a usable endpoint URL: \(url)"
        case .http(let status, let body):
            let detail = body.trimmed.isEmpty ? "" : " — \(body.trimmed.prefix(300))"
            return "Server returned HTTP \(status)\(detail)"
        case .emptyResponse(let provider):
            return "\(provider): the server returned an empty response."
        case .malformedResponse(let provider):
            return "\(provider): could not read the server's response."
        case .transport(let message):
            return message
        }
    }
}
