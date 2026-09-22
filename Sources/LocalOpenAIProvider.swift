import Foundation

/// Any OpenAI-compatible server you are running yourself. No key required, and a
/// long timeout because a local model on a cold cache is not quick.
final class LocalOpenAIProvider: OpenAICompatibleProvider, @unchecked Sendable {
    override var displayName: String { "Local" }
    override var requiresAPIKey: Bool { false }
    override var timeout: TimeInterval { max(config.timeout, 60) }
}
