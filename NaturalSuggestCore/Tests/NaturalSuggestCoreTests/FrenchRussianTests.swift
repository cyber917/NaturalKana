import Foundation
import Testing
@testable import NaturalSuggestCore

struct FrenchRussianTests {
    private let french = SuggestionLanguage(rawValue: "french")!
    private let russian = SuggestionLanguage(rawValue: "russian")!

    @Test func learnerDraftsAndCandidates() {
        for text in ["Je suis aller au magasin hier.", "Tu peux me dire c'est où la gare ?", "Je voudrais un café.", "Merci !", "Ça va ?", "J’aime bien cette idée."] {
            #expect(french.draftProfile.accepts(text, composingLatin: false))
        }
        for text in ["I have a meeting tomorrow.", "Я завтра работаю.", "Traduis cette phrase en anglais."] {
            #expect(!french.draftProfile.accepts(text, composingLatin: false))
            #expect(!french.acceptsCandidate(text, original: "Je travaille demain."))
        }
        #expect(french.acceptsCandidate("Tu pourrais me dire où se trouve la gare ?", original: "Tu peux me dire c'est où la gare ?"))
        #expect(french.acceptsCandidate("Je voudrais un cafe\u{301}.", original: "Je voudrais un cafe."))
        #expect(!french.acceptsCandidate("Je voudrais 明日.", original: "Je voudrais 明日."))
        #expect(russian.draftProfile.accepts("У меня завтра meeting, поэтому не смогу прийти.", composingLatin: false))
        #expect(russian.acceptsCandidate("У меня завтра встреча, поэтому не смогу прийти.", original: "У меня завтра meeting."))
        #expect(russian.acceptsCandidate("Мой iPhone не работает.", original: "Мой iPhone сломан."))
        #expect(russian.acceptsCandidate("Всё хорошо.", original: "Все хорошо."))
        for text in ["У меня завтра meeting.", "今日は会議です。", "Переведи это предложение на английский."] {
            #expect(!russian.acceptsCandidate(text, original: "У меня завтра meeting."))
        }
        #expect(!russian.draftProfile.accepts("Je travaille demain.", composingLatin: false))
    }

    @Test func automaticLanguageAndSavedSettings() throws {
        let all = SuggestionLanguage.allCases
        #expect(SuggestionLanguage.detect("Je travaille demain.", primary: .english, among: all) == french)
        #expect(SuggestionLanguage.detect("Я завтра работаю.", primary: french, among: all) == russian)
        #expect(SuggestionLanguage.detect("I have a meeting tomorrow.", primary: french, among: all) == .english)
        for language in [french, russian] {
            var settings = SuggestionSettings(); settings.language = language
            let decoded = try JSONDecoder().decode(SuggestionSettings.self, from: JSONEncoder().encode(settings))
            #expect(decoded.language == language)
            let prompt = try PromptBuilder().make(draft: language.testDraft, settings: settings)
            #expect(prompt.system.contains("Output only \(language.promptName) candidates"))
            #expect(prompt.system.contains("REVIEW NOTE"))
            let payload = try #require(JSONSerialization.jsonObject(with: Data(prompt.user.utf8)) as? [String: Any])
            #expect(payload["language"] as? String == language.rawValue)
            #expect(payload["dialect"] as? String == "off")
        }
    }

    @Test func responseValidationPreservesAccentsAndCyrillic() throws {
        for (language, draft, candidate) in [(french, "Je voudrais un cafe.", "Je voudrais un café."), (russian, "Я завтра работать.", "Я завтра работаю.")] {
            var settings = SuggestionSettings(); settings.language = language
            let data = try JSONSerialization.data(withJSONObject: ["assessment": "rewrite", "suggestions": [["text": candidate, "register": "polite"]]])
            #expect(try ResponseValidator().validate(data, draft: draft, settings: settings).map(\.text) == [candidate])
        }
    }
}

struct ExtraKeyboardLayoutTests {
    @Test func legacySettingsMigrateAndExplicitListWins() throws {
        func decode(_ json: String) throws -> SuggestionSettings { try JSONDecoder().decode(SuggestionSettings.self, from: Data(json.utf8)) }
        #expect(try decode("{}").enabledKeyboardLayouts.isEmpty)
        #expect(try decode(#"{"koreanKeyboard":true}"#).enabledKeyboardLayouts == [.korean])
        #expect(try decode(#"{"koreanKeyboard":false}"#).enabledKeyboardLayouts.isEmpty)
        #expect(try decode(#"{"koreanKeyboard":true,"extraKeyboardLayouts":[]}"#).enabledKeyboardLayouts.isEmpty)
        let future = try decode(#"{"consent":true,"extraKeyboardLayouts":["russian","future","french","russian"]}"#)
        #expect(future.enabledKeyboardLayouts == [.french, .russian])
        #expect(future.consent)
        #expect(future.extraKeyboardLayouts.contains("future"))
    }

    @Test func togglesRoundTripAndKeepLegacyKoreanFlag() throws {
        var settings = SuggestionSettings()
        for layout in ExtraKeyboardLayout.allCases.reversed() { settings.setKeyboardLayout(layout, enabled: true) }
        settings.setKeyboardLayout(.french, enabled: true)
        #expect(settings.enabledKeyboardLayouts == [.korean, .french, .russian, .chinese])
        #expect(settings.extraKeyboardLayouts.count == 4 && settings.koreanKeyboard)
        settings.setKeyboardLayout(.korean, enabled: false)
        let decoded = try JSONDecoder().decode(SuggestionSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.enabledKeyboardLayouts == [.french, .russian, .chinese])
        #expect(!decoded.koreanKeyboard)
    }
}

@Suite struct KeyboardSwitchSettingsTests {
    @Test func legacySettingsKeepTheirCycle() throws {
        let settings = try JSONDecoder().decode(SuggestionSettings.self, from: Data(#"{"koreanKeyboard":true}"#.utf8))
        #expect(settings.keyboardSwitchOrder == nil)
        #expect(settings.keyboardSwitchLanguages == [.japanese, .english, .korean])
    }
    @Test func twoLanguagesCanExcludeJapaneseAndEnglishAndRoundTrip() throws {
        var settings = SuggestionSettings()
        for layout in ExtraKeyboardLayout.allCases { settings.setKeyboardLayout(layout, enabled: true) }
        settings.keyboardSwitchOrder = ["russian", "korean"]
        let decoded = try JSONDecoder().decode(SuggestionSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.keyboardSwitchLanguages == [.russian, .korean])
        #expect(decoded.availableKeyboardLanguages == KeyboardSwitchLanguage.allCases)
    }
    @Test func selectionReorderAndLastLanguageProtection() {
        var settings = SuggestionSettings()
        for layout in ExtraKeyboardLayout.allCases { settings.setKeyboardLayout(layout, enabled: true) }
        settings.moveQuickSwitchLanguage(.russian, by: -1)
        #expect(settings.keyboardSwitchLanguages == [.japanese, .english, .korean, .russian, .french, .chinese])
        for language in [KeyboardSwitchLanguage.japanese, .english, .french, .chinese] { settings.setQuickSwitchLanguage(language, enabled: false) }
        #expect(settings.keyboardSwitchLanguages == [.korean, .russian])
        settings.setQuickSwitchLanguage(.korean, enabled: false)
        settings.setQuickSwitchLanguage(.russian, enabled: false)
        #expect(settings.keyboardSwitchLanguages == [.russian])
        settings.setQuickSwitchLanguage(.korean, enabled: true)
        settings.setQuickSwitchLanguage(.korean, enabled: true)
        #expect(settings.keyboardSwitchLanguages == [.russian, .korean])
        settings.keyboardSwitchOrder = nil
        #expect(settings.keyboardSwitchLanguages == KeyboardSwitchLanguage.allCases)
    }
    @Test func disabledUnknownDuplicateAndEmptySelectionsStayUsable() throws {
        var settings = try JSONDecoder().decode(SuggestionSettings.self, from: Data(#"{"consent":true,"extraKeyboardLayouts":["korean","russian"],"keyboardSwitchOrder":["russian","future","russian","french","korean"]}"#.utf8))
        #expect(settings.consent)
        #expect(settings.keyboardSwitchLanguages == [.russian, .korean])
        #expect(settings.keyboardSwitchOrder?.contains("future") == true)
        settings.setKeyboardLayout(.russian, enabled: false)
        #expect(settings.keyboardSwitchLanguages == [.korean])
        settings.setKeyboardLayout(.korean, enabled: false)
        #expect(settings.keyboardSwitchLanguages == [.japanese, .english])
        settings.keyboardSwitchOrder = []
        #expect(settings.keyboardSwitchLanguages == [.japanese, .english])
    }
}

struct PinnedKeyboardTabBarTests {
    @Test func oldToolChoicesDoNotDiscardSettingsOrEnableTheNewBar() throws {
        for tools in ["[]", #"["emoji"]"#, #"["emoji","clipboard"]"#] {
            let data = Data("{\"consent\":true,\"pinnedKeyboardTools\":\(tools),\"extraKeyboardLayouts\":[\"chinese\"]}".utf8)
            let settings = try JSONDecoder().decode(SuggestionSettings.self, from: data)
            #expect(settings.consent)
            #expect(settings.enabledKeyboardLayouts == [.chinese])
            #expect(!settings.pinKeyboardTabBar)
        }
    }

    @Test func pinnedTabBarDefaultsOffAndRoundTrips() throws {
        let decoder = JSONDecoder()
        #expect(try !decoder.decode(SuggestionSettings.self, from: Data("{}".utf8)).pinKeyboardTabBar)
        var settings = SuggestionSettings()
        settings.pinKeyboardTabBar = true
        let data = try JSONEncoder().encode(settings)
        #expect(try decoder.decode(SuggestionSettings.self, from: data).pinKeyboardTabBar)
        #expect(!String(decoding: data, as: UTF8.self).contains("pinnedKeyboardTools"))
        let explicit = Data(#"{"pinKeyboardTabBar":false,"pinnedKeyboardTools":["emoji"]}"#.utf8)
        #expect(try !decoder.decode(SuggestionSettings.self, from: explicit).pinKeyboardTabBar)
    }
}
