import Foundation

/// Language of NaturalKana's own interface (settings, status messages, suggestion panels).
public enum InterfaceLanguage: String, Codable, CaseIterable, Sendable {
    case system, chinese, english, japanese

    /// Each language names itself, so a user who cannot read the current interface can still find theirs.
    public var title: String {
        switch self {
        case .system: UIText.t("跟随系统")
        case .chinese: "中文"
        case .english: "English"
        case .japanese: "日本語"
        }
    }
    /// The concrete language to display; `system` follows the device's preferred languages.
    public var resolved: InterfaceLanguage {
        guard self == .system else { return self }
        for identifier in Locale.preferredLanguages {
            let code = identifier.lowercased()
            if code.hasPrefix("zh") { return .chinese }
            if code.hasPrefix("ja") { return .japanese }
            if code.hasPrefix("en") { return .english }
        }
        return .english
    }
}

/// Interface strings, keyed by their Simplified Chinese source text (the language the UI was written in).
/// Translations live in Resources/ui_strings.json, shared with the Windows app; a missing entry shows the Chinese.
/// Placeholders are written %@ and filled in order.
public enum UIText {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var language: InterfaceLanguage = .system
    }
    private static let state = State()
    public static var language: InterfaceLanguage {
        get { state.lock.withLock { state.language } }
        set { state.lock.withLock { state.language = newValue } }
    }
    public static let table: [String: [String: String]] = {
        guard let url = Bundle.module.url(forResource: "ui_strings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return table
    }()

    public static func keyboard(_ chinese: String, language: KeyboardSwitchLanguage) -> String {
        let code: String = switch language {
        case .japanese: "ja"
        case .english: "en"
        case .korean: "ko"
        case .french: "fr"
        case .russian: "ru"
        }
        return table[chinese]?[code] ?? table[chinese]?["en"] ?? chinese
    }

    public static func t(_ chinese: String, _ arguments: String...) -> String {
        translate(chinese, arguments, into: language.resolved)
    }
    public static func translate(_ chinese: String, _ arguments: [String] = [], into language: InterfaceLanguage) -> String {
        let code: String? = switch language {
        case .english: "en"
        case .japanese: "ja"
        case .chinese, .system: nil
        }
        let template = code.flatMap { table[chinese]?[$0] } ?? chinese
        // Fill left to right; an argument that itself contains %@ is not substituted again.
        var text = ""; var rest = Substring(template)
        for argument in arguments {
            guard let range = rest.range(of: "%@") else { break }
            text += rest[..<range.lowerBound] + argument
            rest = rest[range.upperBound...]
        }
        return text + rest
    }
}
