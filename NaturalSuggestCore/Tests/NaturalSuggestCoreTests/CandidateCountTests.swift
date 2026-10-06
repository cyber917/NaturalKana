import Foundation
import Testing
@testable import NaturalSuggestCore

private actor CountTransport: HTTPTransport {
    var body = Data()
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        body = request.httpBody ?? Data()
        return (Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"{\"suggestions\":[]}"}}]}"#.utf8), 200)
    }
}
struct CandidateCountTests {
    @Test func requestSchemaAndOutputBudgetFollowSelection() async throws {
        for limit in [1, 5, 10] {
            var settings = SuggestionSettings(); settings.maximumSuggestions = limit
            let prompt = try PromptBuilder().make(draft: "今何にしていますか", settings: settings, lexicon: .init(entries: []))
            let payload = try #require(JSONSerialization.jsonObject(with: Data(prompt.user.utf8)) as? [String: Any])
            #expect(payload["maximum_suggestions"] as? Int == limit)
            let transport = CountTransport()
            _ = try await QwenProvider(configuration: .init(baseURL: "https://example.com/v1", fastModel: "test"), key: "test-only", transport: transport).suggest(prompt, quality: false)
            let body = try #require(JSONSerialization.jsonObject(with: await transport.body) as? [String: Any])
            let format = try #require(body["response_format"] as? [String: Any])
            let json = try #require(format["json_schema"] as? [String: Any])
            let schema = try #require(json["schema"] as? [String: Any])
            let properties = try #require(schema["properties"] as? [String: Any])
            let rows = try #require(properties["suggestions"] as? [String: Any])
            #expect(rows["maxItems"] as? Int == limit)
            #expect(body["max_completion_tokens"] as? Int == max(2048, limit * 768))
        }
    }
    @Test func validatorKeepsRequestedCountAndRejectsBeyondHardLimit() throws {
        let alternatives = ["今何してる？", "今は何してる？", "今、何をしてる？", "今何してんの？", "今何をしていますか？", "今は何をしていますか？", "今、何をされているんですか？", "今は何をしているの？", "今は何をしているんですか？", "今何をしてますか？"]
        let rows = alternatives.map { ["text": $0, "register": "casual"] }
        let data = try JSONSerialization.data(withJSONObject: ["suggestions": rows])
        for count in [1, 5, 10] {
            var settings = SuggestionSettings(); settings.maximumSuggestions = count
            #expect(try ResponseValidator().validate(data, draft: "今何にしていますか", settings: settings).count == count)
        }
        let over = try JSONSerialization.data(withJSONObject: ["suggestions": rows + [rows[0]]])
        #expect(throws: SuggestionError.self) { try ResponseValidator().validate(over, draft: "今何にしていますか", settings: .init()) }
    }
    @Test func persistedOutOfRangeCountsAreClamped() throws {
        for (raw, expected) in [(-1, 1), (0, 1), (5, 5), (999, 10)] {
            var settings = SuggestionSettings(); settings.maximumSuggestions = raw
            let loaded = try JSONDecoder().decode(SuggestionSettings.self, from: JSONEncoder().encode(settings))
            #expect(loaded.suggestionLimit == expected)
            #expect(try PromptBuilder().make(draft: "今何にしていますか", settings: loaded, lexicon: .init(entries: [])).maximumSuggestions == expected)
        }
    }
}
