import Foundation
import Testing
@testable import NaturalSuggestCore

private actor AssessmentProvider: SuggestionProvider {
    let json: String
    private var calls = 0
    init(_ json: String) { self.json = json }
    func suggest(_ prompt: Prompt, quality: Bool) async throws -> ProviderResult {
        calls += 1
        return ProviderResult(json: Data(json.utf8))
    }
    func count() -> Int { calls }
}

@MainActor struct AssessmentTests {
    private var settings: SuggestionSettings {
        var settings = SuggestionSettings(); settings.enabled = true; settings.consent = true
        return settings
    }
    private func report(_ json: String) throws -> ResponseValidator.Report {
        try ResponseValidator().inspect(Data(json.utf8), draft: "今日は天気がいいですね。", settings: settings)
    }
    @Test func onlyAnExplicitNaturalAssessmentGetsACheck() throws {
        #expect(try report(#"{"assessment":"natural","suggestions":[]}"#).diagnostics == .natural)
        #expect(try report(#"{"suggestions":[]}"#).diagnostics == .noSuggestions)
        #expect(try report(#"{"assessment":"unsupported","suggestions":[]}"#).diagnostics == .unsupportedDraft)
    }
    @Test func contradictoryAndUnknownAssessmentsFailClosed() {
        for json in [
            #"{"assessment":"natural","suggestions":[{"text":"今日はいい天気ですね。","register":"polite"}]}"#,
            #"{"assessment":"rewrite","suggestions":[]}"#,
            #"{"assessment":"success","suggestions":[]}"#,
            #"{"assessment":null,"suggestions":[]}"#,
            #"{"assessment":"natural","suggestions":[],"explanation":"extra"}"#
        ] {
            #expect(throws: SuggestionError.self) { try report(json) }
        }
    }
    @Test func rejectedRewritesAreNotNatural() throws {
        let result = try report(#"{"assessment":"rewrite","suggestions":[{"text":"English reply","register":"polite"}]}"#)
        #expect(result.diagnostics == .rejectedSuggestions(1))
    }
    @Test func naturalResultCachesAcrossHostNotificationsAndFields() async throws {
        let engine = SuggestionEngine(budget: DailyBudget(defaults: UserDefaults(suiteName: "NaturalKana.assessment." + UUID().uuidString)!), prompt: try PromptBuilder())
        let provider = AssessmentProvider(#"{"assessment":"natural","suggestions":[]}"#)
        let draft = DraftSnapshot(text: "今日は天気がいいですね。", fieldID: "first")
        engine.update(draft, settings: settings, provider: provider, explicit: true)
        let deadline = ContinuousClock.now + .seconds(2)
        while engine.status == .waiting || engine.status == .requesting {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(engine.status == .natural)
        for _ in 0..<5 { engine.update(draft, settings: settings, provider: provider) }
        #expect(await provider.count() == 1)
        engine.cancel()
        engine.update(.init(text: draft.text, fieldID: "second"), settings: settings, provider: provider)
        #expect(engine.status == .natural)
        #expect(engine.cacheHit)
        #expect(await provider.count() == 1)
        engine.dismiss()
        engine.update(.init(text: draft.text, fieldID: "second"), settings: settings, provider: provider)
        #expect(engine.status == .idle)
    }
    @Test func schemaAndPromptRequireAnAssessmentWithoutAnotherCall() throws {
        let schema = CompatibleProvider.schema(maximumSuggestions: 5)
        #expect(schema["required"] as? [String] == ["assessment", "suggestions"])
        let system = try PromptBuilder().system
        #expect(system.contains(#""assessment":"natural""#))
        #expect(system.contains(#""assessment":"unsupported""#))
        #expect(!system.contains(#""assessment":"rewrite","suggestions":[]"#))
    }
}
