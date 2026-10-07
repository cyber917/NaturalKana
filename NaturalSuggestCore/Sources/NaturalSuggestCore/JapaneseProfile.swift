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
        let structure = ["した", "する", "して", "でき", "だから", "けど", "たい", "ない", "だった", "ます", "ました", "ください", "って", "ちゃ", "った", "れる", "られる"]
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
