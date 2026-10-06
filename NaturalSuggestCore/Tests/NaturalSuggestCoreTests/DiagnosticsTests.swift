import Foundation
import Testing
@testable import NaturalSuggestCore

private struct FixedSuggestionProvider: SuggestionProvider {
    let json: String
    func suggest(_ prompt: Prompt, quality: Bool) async throws -> ProviderResult {
        ProviderResult(json: Data(json.utf8))
    }
}

@MainActor struct DiagnosticsTests {
    func engine() throws -> SuggestionEngine {
        SuggestionEngine(budget: DailyBudget(defaults: UserDefaults(suiteName: "NaturalKana.diagnostics." + UUID().uuidString)!), prompt: try PromptBuilder())
    }
    @Test func emptyResultIsDifferentFromRejectedCandidates() async throws {
        var settings = SuggestionSettings(); settings.enabled = true; settings.consent = true
        let examples: [(String, Diagnostics)] = [
            (#"{"suggestions":[]}"#, .noSuggestions),
            (#"{"suggestions":[{"text":"私の名前わなんですか、","register":"polite"}]}"#, .rejectedSuggestions(1)),
            (#"{"suggestions":[{"text":"This is English","register":"polite"}]}"#, .rejectedSuggestions(1))
        ]
        for (json, expected) in examples {
            let subject = try engine()
            subject.update(.init(text: "私の名前わなんですか、", fieldID: "sample"), settings: settings, provider: FixedSuggestionProvider(json: json), explicit: true)
            for _ in 0..<100 {
                if subject.status != .waiting && subject.status != .requesting { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(subject.status == expected)
        }
        #expect(!Diagnostics.noSuggestions.message.contains("已自然"))
    }
    @Test func filteredReasonsAreSpecific() throws {
        var settings = SuggestionSettings(); settings.enabled = true; settings.consent = true
        let subject = try engine()
        let provider = FixedSuggestionProvider(json: #"{"suggestions":[]}"#)
        let cases: [(DraftSnapshot, Diagnostics)] = [
            (.init(text: "", fieldID: "test"), .filtered(.empty)),
            (.init(text: "今日h", fieldID: "test", composingLatin: true), .filtered(.composing)),
            (.init(text: "眠る", fieldID: "test"), .filtered(.tooShort(4))),
            (.init(text: "Hello world", fieldID: "test"), .filtered(.language)),
            (.init(text: "こんにちは", fieldID: "test", secure: true), .filtered(.protectedField))
        ]
        for (draft, expected) in cases {
            subject.update(draft, settings: settings, provider: provider)
            #expect(subject.status == expected)
        }
    }
    @Test func screenshotSentencesPassAsWholeSentences() {
        for draft in ["こんにちはご飯を食べる", "何を喋ていますか?", "私の名前わなんですか、"] {
            #expect(JapaneseProfile().accepts(draft))
        }
    }
}
