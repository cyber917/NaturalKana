import Foundation
import Testing
@testable import NaturalSuggestCore

struct DialectTests {
    private var kansai: SuggestionSettings {
        var value = SuggestionSettings(); value.enabled = true; value.consent = true
        value.dialect = .kansai
        return value
    }
    private let mixed = #"{"assessment":"rewrite","suggestions":[{"text":"今何してるん？","register":"kansai"},{"text":"今何してますか？","register":"polite"},{"text":"今何してる？","register":"casual"}]}"#

    @Test func oldSettingsDefaultToDialectOff() throws {
        let legacy = Data(#"{"enabled":true,"consent":true,"provider":"qwen","slangLevel":"off"}"#.utf8)
        let settings = try JSONDecoder().decode(SuggestionSettings.self, from: legacy)
        #expect(settings.dialect == .off && settings.slangLevel == .off && settings.provider == .qwen)
        let restored = try JSONDecoder().decode(SuggestionSettings.self, from: JSONEncoder().encode(kansai))
        #expect(restored.dialect == .kansai)
        #expect(restored.fingerprint != SuggestionSettings().fingerprint)
        // A dialect saved by a newer release must not wipe the rest of the settings.
        let future = Data(#"{"enabled":true,"consent":true,"provider":"qwen","dialect":"hakata"}"#.utf8)
        let downgraded = try JSONDecoder().decode(SuggestionSettings.self, from: future)
        #expect(downgraded.dialect == .off && downgraded.provider == .qwen && downgraded.consent)
    }
    @Test func dialectAppliesToJapaneseOnly() {
        var english = kansai; english.language = .english
        #expect(kansai.activeDialect == .kansai)
        #expect(english.activeDialect == .off)
        #expect(SuggestionSettings().activeDialect == .off)
    }
    @Test func kansaiDraftsAndCandidatesPassLanguageChecks() {
        for draft in ["それくれんねんやった 俺いかんかったのに", "明日雨やったら行かへん", "めっちゃええやん", "知らんけど"] {
            #expect(JapaneseDraftProfile().accepts(draft), "Rejected draft: \(draft)")
        }
        for candidate in ["今何してるん？", "昨日友達に会ってん。", "今日はええ天気やね。", "それくれるんやったら、俺行かへんかったのに。", "行かはりますか？"] {
            #expect(SuggestionLanguage.japanese.acceptsCandidate(candidate, original: "今何にしていますか"), "Rejected candidate: \(candidate)")
        }
    }
    @Test func validatorGroupsKansaiAfterStandardRegisters() throws {
        let items = try ResponseValidator().validate(Data(mixed.utf8), draft: "今何にしていますか", settings: kansai)
        #expect(items.map(\.register) == [.casual, .polite, .kansai])
        #expect(items.last?.text == TextNormalization.nfkc("今何してるん？"))
    }
    @Test func kansaiRowsAreDroppedUnlessSelected() throws {
        var off = kansai; off.dialect = .off
        let items = try ResponseValidator().validate(Data(mixed.utf8), draft: "今何にしていますか", settings: off)
        #expect(items.map(\.register) == [.casual, .polite])
        var english = kansai; english.language = .english
        let json = #"{"assessment":"rewrite","suggestions":[{"text":"今何してるん？","register":"kansai"}]}"#
        #expect(try ResponseValidator().inspect(Data(json.utf8), draft: "What are you doing now", settings: english).diagnostics == .rejectedSuggestions(1))
    }
    @Test func registerPreferenceDoesNotHideTheDialectGroup() throws {
        var casual = kansai; casual.registerPreference = .friendsCasual
        #expect(try ResponseValidator().validate(Data(mixed.utf8), draft: "今何にしていますか", settings: casual).map(\.register) == [.casual, .kansai])
        var polite = kansai; polite.registerPreference = .politeCasual
        #expect(try ResponseValidator().validate(Data(mixed.utf8), draft: "今何にしていますか", settings: polite).map(\.register) == [.polite, .kansai])
    }
    @Test func naturalStandardDraftCanStillShowKansai() throws {
        let json = #"{"assessment":"rewrite","suggestions":[{"text":"今日はええ天気やね。","register":"kansai"}]}"#
        let report = try ResponseValidator().inspect(Data(json.utf8), draft: "今日は天気がいいですね", settings: kansai)
        #expect(report.diagnostics == .ready)
        #expect(report.suggestions.map(\.register) == [.kansai])
    }
    @Test func promptCarriesTheDialectSetting() throws {
        let builder = try PromptBuilder()
        let on = try builder.make(draft: "今何にしていますか", settings: kansai)
        let payload = try #require(JSONSerialization.jsonObject(with: Data(on.user.utf8)) as? [String: Any])
        #expect(payload["dialect"] as? String == "kansai")
        #expect(on.registers == [.casual, .polite, .kansai])
        #expect(on.system.contains("dialect=kansai") && on.system.contains("Regional dialects are not errors"))
        let off = try builder.make(draft: "今何にしていますか", settings: .init())
        let offPayload = try #require(JSONSerialization.jsonObject(with: Data(off.user.utf8)) as? [String: Any])
        #expect(offPayload["dialect"] as? String == "off")
        #expect(off.registers == [.casual, .polite])
        var english = kansai; english.language = .english
        let englishPayload = try #require(JSONSerialization.jsonObject(with: Data(try builder.make(draft: "I go home.", settings: english).user.utf8)) as? [String: Any])
        #expect(englishPayload["dialect"] as? String == "off")
    }
    @Test func schemaAllowsKansaiOnlyWhenRequested() throws {
        func registers(_ schema: [String: Any]) throws -> [String] {
            let properties = try #require(schema["properties"] as? [String: Any])
            let suggestions = try #require(properties["suggestions"] as? [String: Any])
            let item = try #require(suggestions["items"] as? [String: Any])
            let fields = try #require(item["properties"] as? [String: Any])
            return try #require((fields["register"] as? [String: Any])?["enum"] as? [String])
        }
        #expect(try registers(CompatibleProvider.schema(maximumSuggestions: 5)) == ["casual", "polite"])
        #expect(try registers(CompatibleProvider.schema(maximumSuggestions: 5, registers: [.casual, .polite, .kansai])) == ["casual", "polite", "kansai"])
    }
    @Test func groupTitles() {
        #expect(SuggestionLanguage.japanese.registerTitle(.kansai) == "関西弁")
        #expect(SuggestionLanguage.japanese.registerTitle(.casual) == "カジュアル")
        #expect(Dialect.allCases.map(\.title) == [UIText.t("关闭"), "関西弁"])
        #expect(Dialect.kansai.register == .kansai && Dialect.off.register == nil)
    }
}
