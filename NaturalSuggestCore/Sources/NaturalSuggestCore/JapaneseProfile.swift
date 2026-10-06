import Foundation
import NaturalLanguage

public protocol LanguageProfile: Sendable { func accepts(_ text: String, composingLatin: Bool) -> Bool }
public struct JapaneseProfile: LanguageProfile {
    public init() {}
    public static func isKana(_ s: Unicode.Scalar) -> Bool {
        (0x3041...0x3096).contains(s.value) || (0x30A1...0x30FA).contains(s.value) || s.value == 0x30FC
    }
    public static func isHan(_ s: Unicode.Scalar) -> Bool {
        (0x3400...0x9FFF).contains(s.value) || (0x20000...0x3134F).contains(s.value)
    }
    static let punctuation = CharacterSet(charactersIn: "。、！？!?「」『』（）()・ー〜～….,:：;；『』【】0123456789")
    static let latinAllowlist: Set<String> = ["w", "ww", "www", "LINE", "SNS", "X", "Instagram", "TikTok", "YouTube", "DM", "OK", "NG", "AI", "URL", "PDF"]
    static func latinWords(_ text: String) -> [String] {
        text.split { !$0.isASCII || !$0.isLetter }.map(String.init)
    }
    public func accepts(_ text: String, composingLatin: Bool = false) -> Bool {
        guard !composingLatin else { return false }
        let normalized = TextNormalization.nfkc(text)
        // The OS recognizer misclassifies Chinese ending in です. Prefer false negatives for this learner tool.
        let chineseMarkers = ["今天", "明天", "昨天", "我们", "你们", "他们", "很累", "很开心", "不知道", "怎么办", "吃饭", "学习日语", "请帮", "我想", "一起去吧", "天气很好"]
        // Some simplified shapes are also Japanese shinjitai (学/会/来/対-equivalents); do not ban those.
        let unmistakableSimplified = CharacterSet(charactersIn: "这们说请谢饭吗么让给还过听欢话帮样见")
        guard !chineseMarkers.contains(where: normalized.contains),
              !normalized.unicodeScalars.contains(where: unmistakableSimplified.contains),
              Set(normalized).count > 1 || normalized.count < 5 else { return false }
        let scalars = normalized.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
        guard !scalars.isEmpty, scalars.contains(where: Self.isKana) else { return false }
        guard Self.latinWords(normalized).allSatisfy({ Self.latinAllowlist.contains($0) }) else { return false }
        let japanese = scalars.filter { Self.isKana($0) || Self.isHan($0) || Self.punctuation.contains($0) }.count
        guard Double(japanese) / Double(scalars.count) >= 0.7 else { return false }
        // Conservative local filter for translation/instruction requests; the system prompt repeats this rule.
        let denied = ["翻訳", "翻译", "訳して", "訳せ", "日本語にして", "中国語にして", "英語にして", "指示を無視", "プロンプト", "命令を無視"]
        guard !denied.contains(where: normalized.contains) else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(normalized)
        // A script ratio cannot distinguish Chinese with inserted kana. Fail closed when uncertain.
        return recognizer.dominantLanguage == .japanese
    }
}
/// Input can contain unknown foreign words inside a Japanese sentence. Output stays strict.
public struct JapaneseDraftProfile: LanguageProfile {
    public init() {}
    /// Only the unfinished roman suffix blocks requests; embedded foreign words are draft data.
    public static func hasPendingRomaji(_ composition: String) -> Bool {
        guard let last = composition.unicodeScalars.last else { return false }
        return (65...90).contains(last.value) || (97...122).contains(last.value)
    }
    public func accepts(_ text: String, composingLatin: Bool = false) -> Bool {
        guard !composingLatin else { return false }
        if JapaneseProfile().accepts(text) { return true }
        let normalized = TextNormalization.nfkc(text)
        let denied = ["翻訳", "翻译", "訳して", "訳せ", "日本語にして", "中国語にして", "英語にして", "指示を無視", "プロンプト", "命令を無視", "ignore instructions", "system prompt"]
        guard !denied.contains(where: normalized.lowercased().contains),
              !normalized.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              normalized.unicodeScalars.filter(JapaneseProfile.isKana).count >= 3 else { return false }
        // Require Japanese sentence structure, not just a foreign sentence with です appended.
        let structure = ["したら", "して", "でき", "だから", "けど", "たい", "ない", "だった", "ます", "ました", "ください", "って", "ちゃ", "った", "れる", "られる"]
        let topic = normalized.range(of: "[一-龯ぁ-ゖァ-ヺー]{2,}(?:[はがをにと]|で(?!す))", options: .regularExpression) != nil
        guard structure.contains(where: normalized.contains) || (topic && normalized.contains("です")) else { return false }
        let scalars = normalized.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
        let japanese = scalars.filter { JapaneseProfile.isKana($0) || JapaneseProfile.isHan($0) }.count
        // Count a foreign word as a slot, so a long English word does not drown out Japanese grammar.
        let latin = scalars.filter { $0.isASCII && CharacterSet.letters.contains($0) }.count
        let weightedLength = scalars.count - latin + JapaneseProfile.latinWords(normalized).reduce(0) { $0 + min(2, $1.count) }
        return Double(japanese) / Double(max(1, weightedLength)) >= 0.5
    }
}
public struct ResponseValidator: Sendable {
    public init() {}
    public enum Assessment: String, Sendable { case natural, rewrite, unsupported }
    public struct Report: Sendable {
        public let suggestions: [Suggestion]
        public let receivedCount: Int
        public let assessment: Assessment?
        public var diagnostics: Diagnostics {
            if !suggestions.isEmpty { return .ready }
            if receivedCount > 0 { return .rejectedSuggestions(receivedCount) }
            if assessment == .natural { return .natural }
            if assessment == .unsupported { return .unsupportedDraft }
            return .noSuggestions
        }
    }
    public func validate(_ data: Data, draft: String, settings: SuggestionSettings) throws -> [Suggestion] {
        try inspect(data, draft: draft, settings: settings).suggestions
    }
    public func inspect(_ data: Data, draft: String, settings: SuggestionSettings) throws -> Report {
        guard data.count <= 32_768,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              Set(object.keys).isSubset(of: ["suggestions", "assessment"]),
              let rows = object["suggestions"] as? [[String: Any]], rows.count <= SuggestionSettings.suggestionCountRange.upperBound else { throw SuggestionError.invalidResponse }
        let assessment: Assessment?
        if let value = object["assessment"] {
            guard let raw = value as? String, let known = Assessment(rawValue: raw),
                  (known == .rewrite ? !rows.isEmpty : rows.isEmpty) else { throw SuggestionError.invalidResponse }
            assessment = known
        } else { assessment = nil } // Legacy empty replies are unknown, never a green check.
        let original = TextNormalization.nfkc(draft)
        var seen = Set<String>()
        let originalLatin = Set(JapaneseProfile.latinWords(original))
        let suggestions = rows.compactMap { row -> Suggestion? in
            guard Set(row.keys) == ["text", "register"], let raw = row["text"] as? String,
                  let registerName = row["register"] as? String, let register = Register(rawValue: registerName) else { return nil }
            let text = TextNormalization.nfkc(raw).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !text.contains(where: { $0.isNewline }),
                  !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.illegalCharacters.contains($0) }),
                  text != original, text.count <= 3 * original.count,
                  JapaneseProfile().accepts(text, composingLatin: false),
                  JapaneseProfile.latinWords(text).allSatisfy({ originalLatin.contains($0) }),
                  settings.registerPreference != .friendsCasual || register == .casual,
                  settings.registerPreference != .politeCasual || register == .polite else { return nil }
            // Reject newly introduced emoji/symbols. Numeric emoji properties alone are not sufficient.
            let emoji = text.unicodeScalars.filter { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
            guard emoji.allSatisfy({ original.unicodeScalars.contains($0) }), seen.insert(text).inserted else { return nil }
            return Suggestion(text: text, register: register)
        }.prefix(settings.suggestionLimit).map { $0 }
        // Keep model ranking within each register and use the same order for display, cache and acceptance.
        let grouped = suggestions.filter { $0.register == .casual } + suggestions.filter { $0.register == .polite }
        return Report(suggestions: grouped, receivedCount: rows.count, assessment: assessment)
    }
}
