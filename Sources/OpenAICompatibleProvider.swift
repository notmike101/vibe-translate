import Foundation

/// Shared implementation for every `/chat/completions` backend. Subclasses supply
/// the base URL, the display name and whether a key is mandatory; everything
/// else — prompt assembly, transport, streaming, model listing, cleanup — lives
/// here.
///
/// The class is immutable after `init`, which is what makes `@unchecked Sendable`
/// honest: there is no mutable state for a concurrent request to race on.
class OpenAICompatibleProvider: TranslationProvider, ModelListingProvider,
                                StreamingTranslationProvider, @unchecked Sendable {
    let config: ProviderConfig

    required init(config: ProviderConfig) {
        self.config = config
    }

    // MARK: - Subclass surface

    var displayName: String { "OpenAI-compatible" }
    var requiresAPIKey: Bool { false }
    var delayBetween: Duration { .zero }

    /// Subclasses either hard-code this (OpenAI) or read the snapshot (Local).
    var baseURL: String { config.endpoint }

    var model: String { config.model }
    var apiKey: String { config.apiKey }
    var timeout: TimeInterval { config.timeout }

    // MARK: - Wire format

    /// Both fields are optional on purpose: a streamed `delta` carries `content`
    /// with no `role`, and the final delta carries neither. A required field here
    /// makes every chunk fail to decode.
    private struct ChatMessage: Decodable {
        let role: String?
        let content: String?
    }

    private struct Choice: Decodable {
        let message: ChatMessage?
        let delta: ChatMessage?
    }

    private struct ChatResponse: Decodable {
        let choices: [Choice]?
    }

    private struct ModelList: Decodable {
        struct Entry: Decodable { let id: String }
        let data: [Entry]?
    }

    /// Reasoning-era models rejected `max_tokens`; older and local servers only
    /// know that name. Start with the widely understood one and fall back.
    private enum TokenLimitKey: String {
        case maxTokens = "max_tokens"
        case maxCompletionTokens = "max_completion_tokens"
    }

    // MARK: - Translate

    func translate(_ text: String, from source: String, to target: String) async throws -> String {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return "" }
        try validate()

        let request = try chatRequest(text: trimmed, from: source, to: target,
                                      stream: false, tokenKey: .maxTokens)
        let raw: String
        do {
            raw = try await completion(request)
        } catch let error as TranslationError {
            guard let retry = try retryRequest(for: error, text: trimmed, from: source,
                                               to: target, stream: false) else { throw error }
            raw = try await completion(retry)
        }
        return Self.sanitize(raw)
    }

    private func completion(_ request: URLRequest) async throws -> String {
        let (data, response) = try await send(request)
        try Self.checkStatus(response, body: data)

        guard let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data) else {
            throw TranslationError.malformedResponse(displayName)
        }
        guard let content = decoded.choices?.first?.message?.content, !content.trimmed.isEmpty else {
            throw TranslationError.emptyResponse(displayName)
        }
        return content
    }

    // MARK: - Streaming

    /// Server-sent events, one `data:` line per token batch. Yields the running
    /// delta; the caller is responsible for sanitising what it shows.
    func translateStream(_ text: String, from source: String, to target: String)
        -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let trimmed = text.trimmed
                    guard !trimmed.isEmpty else { continuation.finish(); return }
                    try validate()

                    var request = try chatRequest(text: trimmed, from: source, to: target,
                                                  stream: true, tokenKey: .maxTokens)
                    var produced = false

                    do {
                        produced = try await pump(request, into: continuation)
                    } catch let error as TranslationError {
                        guard let retry = try retryRequest(for: error, text: trimmed, from: source,
                                                           to: target, stream: true) else { throw error }
                        request = retry
                        produced = try await pump(request, into: continuation)
                    }

                    if !produced { throw TranslationError.emptyResponse(displayName) }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.friendly(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Reads one streamed response, forwarding deltas. Returns whether any text
    /// actually arrived.
    private func pump(_ request: URLRequest,
                      into continuation: AsyncThrowingStream<String, Error>.Continuation) async throws -> Bool {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            var body = ""
            for try await line in bytes.lines where body.count < 600 { body += line }
            throw TranslationError.http(status: http.statusCode, body: body)
        }

        var produced = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }

            let payload = String(line.dropFirst(5)).trimmed
            if payload.isEmpty || payload == "[DONE]" { continue }

            guard let chunk = try? JSONDecoder().decode(ChatResponse.self, from: Data(payload.utf8)),
                  let piece = chunk.choices?.first?.delta?.content, !piece.isEmpty
            else { continue }

            produced = true
            continuation.yield(piece)
        }
        return produced
    }

    // MARK: - Models

    /// Asks the server what it can run. Throwing rather than returning an empty
    /// list keeps the reason — wrong port, bad key — attached to the failure.
    func availableModels() async throws -> [String] {
        guard !baseURL.trimmed.isEmpty else { throw TranslationError.missingEndpoint(displayName) }
        if requiresAPIKey && apiKey.trimmed.isEmpty { throw TranslationError.missingAPIKey(displayName) }

        var request = URLRequest(url: try endpoint(path: "models"))
        request.timeoutInterval = min(timeout, 20)
        authorize(&request)

        let (data, response) = try await send(request)
        try Self.checkStatus(response, body: data)

        // Most servers wrap the list in `data`; a few return a bare array.
        var ids = (try? JSONDecoder().decode(ModelList.self, from: data))?.data?.map(\.id)
        if ids == nil {
            ids = (try? JSONDecoder().decode([ModelList.Entry].self, from: data))?.map(\.id)
        }

        guard let ids, !ids.isEmpty else {
            throw TranslationError.emptyResponse(displayName)
        }

        return Array(Set(ids.filter { !$0.trimmed.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: - Request assembly

    private func validate() throws {
        guard !baseURL.trimmed.isEmpty else { throw TranslationError.missingEndpoint(displayName) }
        if requiresAPIKey && apiKey.trimmed.isEmpty { throw TranslationError.missingAPIKey(displayName) }
    }

    private func endpoint(path: String) throws -> URL {
        var base = baseURL.trimmed
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/" + path), url.scheme != nil, url.host != nil else {
            throw TranslationError.badEndpoint(baseURL)
        }
        return url
    }

    private func authorize(_ request: inout URLRequest) {
        let key = apiKey.trimmed
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
    }

    private func chatRequest(text: String, from source: String, to target: String,
                             stream: Bool, tokenKey: TokenLimitKey) throws -> URLRequest {
        var body: [String: Any] = [
            "model": model,
            "temperature": config.temperature,
            "stream": stream,
            "messages": [
                ["role": "system", "content": systemPrompt(from: source, to: target)],
                ["role": "user", "content": userPrompt(text: text, from: source, to: target)],
            ],
            tokenKey.rawValue: max(512, text.count * 6),
        ]
        if stream { body["stream_options"] = ["include_usage": false] }

        var request = URLRequest(url: try endpoint(path: "chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        authorize(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// One retry, only for the token-limit parameter rename.
    private func retryRequest(for error: TranslationError, text: String, from source: String,
                              to target: String, stream: Bool) throws -> URLRequest? {
        guard case .http(let status, let body) = error, status == 400,
              body.contains("max_completion_tokens") || body.contains("max_tokens")
        else { return nil }

        return try chatRequest(text: text, from: source, to: target,
                               stream: stream, tokenKey: .maxCompletionTokens)
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw Self.friendly(error)
        }
    }

    // MARK: - Prompts

    func systemPrompt(from source: String, to target: String) -> String {
        let template = config.systemPrompt.trimmed.isEmpty
            ? PromptTemplate.defaultSystem
            : config.systemPrompt
        return PromptTemplate.fill(template, text: nil, from: source, to: target)
    }

    func userPrompt(text: String, from source: String, to target: String) -> String {
        let template = config.userPrompt.trimmed.isEmpty ? "{text}" : config.userPrompt
        let filled = PromptTemplate.fill(template, text: text, from: source, to: target)
        // A template with no {text} would silently drop the input.
        return filled.contains(text) ? filled : filled + "\n\n" + text
    }

    // MARK: - Cleanup

    /// Strips the wrapping a chat model adds around an answer: reasoning blocks
    /// from local `<think>` models, and the quotes it likes to put around a
    /// one-line translation.
    static func sanitize(_ value: String) -> String {
        var s = stripReasoning(value).trimmed
        guard s.count > 1 else { return s }

        let pairs: [(Character, Character)] = [("\"", "\""), ("\u{201C}", "\u{201D}"), ("«", "»")]
        for (open, close) in pairs where s.first == open && s.last == close {
            s = String(s.dropFirst().dropLast()).trimmed
            break
        }
        return s
    }

    static func stripReasoning(_ value: String) -> String {
        var s = value
        for tag in ["think", "thinking", "reasoning"] {
            // Closed blocks first, then an unterminated one (a reply still in
            // flight). `(?s)` so `.` spans the newlines a reasoning block is
            // full of.
            s = s.replacingOccurrences(
                of: "(?s)<\(tag)>.*?</\(tag)>",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            if let open = s.range(of: "<\(tag)>", options: [.caseInsensitive]) {
                s = String(s[s.startIndex..<open.lowerBound])
            }
        }
        return s
    }

    // MARK: - Errors

    static func checkStatus(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200...299).contains(http.statusCode) else { return }
        throw TranslationError.http(status: http.statusCode,
                                    body: String(data: body, encoding: .utf8) ?? "")
    }

    /// URLError messages are unhelpful on their own — "could not connect to the
    /// server" does not tell you the local model is not running.
    static func friendly(_ error: Error) -> Error {
        guard let urlError = error as? URLError else { return error }
        let host = urlError.failingURL?.host ?? "the server"
        switch urlError.code {
        case .cancelled:
            // A superseded keystroke, not a failure — the caller must not show it.
            return CancellationError()
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
            return TranslationError.transport("Could not reach \(host). Is the server running?")
        case .timedOut:
            return TranslationError.transport("Timed out waiting for \(host).")
        case .notConnectedToInternet:
            return TranslationError.transport("No network connection.")
        default:
            return TranslationError.transport(urlError.localizedDescription)
        }
    }
}
