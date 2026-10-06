import Foundation
import Testing
@testable import NaturalSuggestCore

private struct FixtureTransport: HTTPTransport {
    var data: Data
    var status: Int = 200
    func send(_ request: URLRequest) async throws -> (Data, Int) { (data, status) }
}
private struct OfflineTransport: HTTPTransport {
    let code: URLError.Code
    func send(_ request: URLRequest) async throws -> (Data, Int) { throw URLError(code) }
}

@MainActor struct FailureTests {
    private func run(_ transport: any HTTPTransport) async throws -> SuggestionEngine {
        let engine = SuggestionEngine(budget: DailyBudget(defaults: UserDefaults(suiteName: "NaturalKana.tests." + UUID().uuidString)!), prompt: try PromptBuilder())
        var settings = SuggestionSettings(); settings.enabled = true; settings.consent = true
        let provider = QwenProvider(configuration: .init(baseURL: "https://example.com/v1", fastModel: "fixture"), key: "test-only", transport: transport)
        engine.update(.init(text: "今何にしていますか", fieldID: "test"), settings: settings, provider: provider, explicit: true)
        // Await a terminal state instead of relying on a fixed fast-computer timing assumption.
        for _ in 0..<100 {
            if engine.status != .waiting && engine.status != .requesting { return engine }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Request did not reach a terminal state")
        return engine
    }

    @Test func failuresReachTheUIWithoutLeakingResponseText() async throws {
        let fixtures: [(Int, String, Diagnostics)] = [
            (401, #"{"error":{"message":"SECRET SHOULD NOT BE DISPLAYED"}}"#, .httpStatus(401)),
            (403, "forbidden", .httpStatus(403)),
            (404, "not found", .httpStatus(404)),
            (429, #"{"error":{"code":"rate_limit_exceeded"}}"#, .httpStatus(429)),
            (429, #"{"error":{"code":"insufficient_quota"}}"#, .providerQuota),
            (400, #"{"error":{"code":"invalid_parameter"}}"#, .httpStatus(400)),
            (503, "<html>unavailable</html>", .httpStatus(503)),
            (200, "invalid JSON", .invalidResponse),
            (200, #"{"choices":[{"finish_reason":"length","message":{"content":"{broken"}}]}"#, .truncated),
            (200, #"{"choices":[{"finish_reason":"content_filter","message":{}}]}"#, .refused),
            (200, #"{"choices":[{"finish_reason":"stop","message":{"refusal":"SECRET SHOULD NOT BE DISPLAYED"}}]}"#, .refused),
            (200, #"{"choices":[{"finish_reason":"stop","message":{"content":"not candidate JSON"}}]}"#, .invalidResponse),
            (200, #"{"choices":[{"finish_reason":"stop","message":{"content":"{\"suggestions\":[]}"}}]}"#, .noSuggestions)
        ]
        for (status, body, expected) in fixtures {
            let engine = try await run(FixtureTransport(data: Data(body.utf8), status: status))
            #expect(engine.status == expected)
            #expect(engine.suggestions.isEmpty)
            #expect(!engine.status.message.contains("SECRET"))
        }
    }
    @Test func networkAndTimeoutAreNotFormatFailures() async throws {
        let timeout = try await run(OfflineTransport(code: .timedOut))
        #expect(timeout.status == .timeout)
        let offline = try await run(OfflineTransport(code: .notConnectedToInternet))
        #expect(offline.status == .network)
    }
}
