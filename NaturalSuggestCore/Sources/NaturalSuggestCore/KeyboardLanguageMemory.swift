import Foundation

/// Remembers a language layout, independently of temporary number, emoji or URL keyboards.
public enum KeyboardLanguageMemory {
    public static let key = "nk.keyboard.lastLanguage"

    public static func load(from defaults: UserDefaults, settings: SuggestionSettings) -> KeyboardSwitchLanguage {
        guard let raw = defaults.string(forKey: key), let language = KeyboardSwitchLanguage(rawValue: raw),
              settings.availableKeyboardLanguages.contains(language) else { return .japanese }
        return language
    }

    public static func save(_ language: KeyboardSwitchLanguage, to defaults: UserDefaults) {
        defaults.set(language.rawValue, forKey: key)
    }
}
