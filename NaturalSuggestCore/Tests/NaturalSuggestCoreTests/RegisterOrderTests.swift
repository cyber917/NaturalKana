import Foundation
import Testing
@testable import NaturalSuggestCore

private actor RegisterProvider: SuggestionProvider {
    var calls = 0
    func suggest(_ prompt: Prompt, quality: Bool) async throws -> ProviderResult {
        calls += 1
        return ProviderResult(json: Data(#"{"suggestions":[{"text":"今何をしていますか？","register":"polite"},{"text":"今何してる？","register":"casual"},{"text":"今は何をしていますか？","register":"polite"},{"text":"今は何してる？","register":"casual"}]}"#.utf8))
    }
}

@MainActor struct RegisterOrderTests {
    @Test func groupedOrderSurvivesCacheAndAcceptance() async throws {
        let suite = "NaturalKana.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = SuggestionEngine(budget: DailyBudget(defaults: defaults), prompt: try PromptBuilder())
        let provider = RegisterProvider()
        var settings = SuggestionSettings(); settings.enabled = true; settings.consent = true
        let snapshot = DraftSnapshot(text: "今何にしていますか", fieldID: "register-order")
        let expected = ["今何してる？", "今は何してる？", "今何をしていますか？", "今は何をしていますか？"].map(TextNormalization.nfkc)
        engine.update(snapshot, settings: settings, provider: provider, explicit: true)
        for _ in 0..<100 {
            if engine.status == .ready { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(engine.suggestions.map(\.text) == expected)
        #expect(engine.suggestions.map(\.register) == [.casual, .casual, .polite, .polite])
        for index in expected.indices {
            engine.update(snapshot, settings: settings, provider: provider, explicit: true)
            #expect(engine.accept(index: index, current: snapshot) == expected[index])
        }
        #expect(await provider.calls == 1)
    }
}
