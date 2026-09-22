import Foundation

/// Hosted OpenAI. The base URL is fixed here rather than read from settings —
/// there is only one place this backend can point.
final class OpenAIProvider: OpenAICompatibleProvider, @unchecked Sendable {
    override var displayName: String { "OpenAI" }
    override var requiresAPIKey: Bool { true }
    override var baseURL: String { "https://api.openai.com/v1" }
}
