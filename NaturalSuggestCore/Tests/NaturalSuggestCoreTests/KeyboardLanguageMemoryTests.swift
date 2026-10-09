import Foundation
import Testing
@testable import NaturalSuggestCore

struct KeyboardLanguageMemoryTests {
    @Test func everyLanguageSurvivesAStorageReload() throws {
        let suite = "KeyboardLanguageMemoryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = SuggestionSettings()
        settings.extraKeyboardLayouts = ExtraKeyboardLayout.allCases.map(\.rawValue)
        settings.keyboardSwitchOrder = ["japanese", "english"]
        for language in KeyboardSwitchLanguage.allCases {
            KeyboardLanguageMemory.save(language, to: defaults)
            let reloaded = try #require(UserDefaults(suiteName: suite))
            #expect(KeyboardLanguageMemory.load(from: reloaded, settings: settings) == language)
        }
    }

    @Test func missingUnknownAndDisabledLayoutsFallBackWithoutChangingSettings() throws {
        let suite = "KeyboardLanguageMemoryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SuggestionSettings()
        for raw in [nil, "emoji", "qwerty_numbers", "chinese", "future-language"] as [String?] {
            defaults.set(raw, forKey: KeyboardLanguageMemory.key)
            #expect(KeyboardLanguageMemory.load(from: defaults, settings: settings) == .japanese)
            #expect(defaults.data(forKey: "nk.settings") == nil)
        }
        KeyboardLanguageMemory.save(.english, to: defaults)
        #expect(KeyboardLanguageMemory.load(from: defaults, settings: settings) == .english)
    }
}
