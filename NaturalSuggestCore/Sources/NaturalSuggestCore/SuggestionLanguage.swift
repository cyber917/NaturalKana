import Foundation
import NaturalLanguage

public enum SuggestionLanguage: String, Codable, CaseIterable, Sendable {
    case japanese, english, chinese

    /// The Mac input method only sees text typed through NaturalKana, so it cannot check Chinese typed with another IME.
    public static var available: [SuggestionLanguage] {
        #if os(macOS)
        [.japanese, .english]
        #else
        allCases
        #endif
    }
    public var title: String {
        switch self {
        case .japanese: "日语"
        case .english: "英语"
        case .chinese: "中文"
        }
    }
    public var promptName: String {
        switch self {
        case .japanese: "Japanese"
        case .english: "English"
        case .chinese: "Simplified Chinese"
        }
    }
    public var testDraft: String {
        switch self {
        case .japanese: "今日は仕事があるから、少し待ってください。"
        case .english: "I have work to do, please wait me a moment."
        case .chinese: "我明天有工作，所以请等一点我。"
        }
    }
    public var draftProfile: any LanguageProfile {
        switch self {
        case .japanese: JapaneseDraftProfile()
        case .english: EnglishDraftProfile()
        case .chinese: ChineseDraftProfile()
        }
    }
    public func acceptsCandidate(_ text: String, original: String) -> Bool {
        switch self {
        case .japanese:
            let originalLatin = Set(JapaneseProfile.latinWords(original))
            return JapaneseProfile().accepts(text) && JapaneseProfile.latinWords(text).allSatisfy(originalLatin.contains)
        case .english:
            return EnglishProfile().accepts(text)
        case .chinese:
            return ChineseProfile().accepts(text, original: original)
        }
    }
    public func registerTitle(_ register: Register) -> String {
        switch (self, register) {
        case (.japanese, .casual): "カジュアル"
        case (.japanese, .polite): "丁寧"
        case (.english, .casual): "Casual"
        case (.english, .polite): "Polite"
        case (.chinese, .casual): "口语"
        case (.chinese, .polite): "礼貌"
        case (_, .kansai): Dialect.kansai.title
        }
    }
    public var closeTitle: String {
        switch self {
        case .japanese: "閉じる"
        case .english: "Close"
        case .chinese: "关闭"
        }
    }
    public var copyHint: String {
        switch self {
        case .japanese: "クリックでコピー・元の文を選択して貼り付け"
        case .english: "Click to copy · Select the original text and paste"
        case .chinese: "点击复制 · 选中原句后粘贴"
        }
    }
}

/// Allows learner English, including a few unknown foreign words in an English sentence.
/// The model assesses meaning/naturalness; this gate only avoids unrelated input.
public struct EnglishDraftProfile: LanguageProfile {
    public init() {}
    public func accepts(_ text: String, composingLatin: Bool = false) -> Bool {
        guard !composingLatin else { return false }
        let normalized = TextNormalization.nfkc(text)
        guard EnglishProfile.isUsable(normalized) else { return false }
        let words = EnglishProfile.words(normalized)
        guard !words.isEmpty else { return false }
        let letters = normalized.unicodeScalars.filter(CharacterSet.letters.contains)
        let latin = letters.filter(EnglishProfile.isLatin)
        // Count a run of unknown characters as one word-sized slot, as with Japanese drafts.
        let foreignRuns = normalized.components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.unicodeScalars.contains { !EnglishProfile.isLatin($0) } }
        guard latin.count >= 2, foreignRuns.count <= 3,
              Double(latin.count) / Double(max(1, letters.count)) >= 0.5 else { return false }
        let anchors: Set<String> = ["i", "i'm", "i've", "i'll", "i'd", "you", "you're", "your", "we", "we're", "they", "he", "she", "it", "it's", "the", "a", "an", "is", "are", "was", "were", "to", "my", "me", "can", "could", "please", "have", "has", "don't", "doesn't", "not", "this", "that", "thanks", "hello"]
        if words.count >= 2 && words.contains(where: anchors.contains) { return true }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(normalized)
        return recognizer.dominantLanguage == .english
    }
}

/// Candidates must contain English text only; mixed-script placeholders belong in drafts.
public struct EnglishProfile: LanguageProfile {
    public init() {}
    static func isLatin(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.letters.contains(scalar) && ((65...122).contains(scalar.value) || (0xC0...0x24F).contains(scalar.value))
    }
    static func words(_ text: String) -> [String] {
        text.lowercased().replacingOccurrences(of: "’", with: "'")
            .split { !$0.isLetter && $0 != "'" }.map(String.init)
    }
    static func isUsable(_ text: String) -> Bool {
        guard !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.illegalCharacters.contains($0) }),
              Set(text).count > 1 else { return false }
        let lower = text.lowercased()
        let denied = ["ignore previous instructions", "ignore all instructions", "ignore instructions", "system prompt", "developer message", "翻译", "翻訳", "指示を無視"]
        guard !denied.contains(where: lower.contains) else { return false }
        return lower.range(of: #"^\s*(please\s+)?(translate|rewrite in|respond in)\b"#, options: .regularExpression) == nil
    }
    public func accepts(_ text: String, composingLatin: Bool = false) -> Bool {
        let normalized = TextNormalization.nfkc(text)
        guard !composingLatin, Self.isUsable(normalized),
              normalized.unicodeScalars.filter(CharacterSet.letters.contains).allSatisfy(Self.isLatin) else { return false }
        return EnglishDraftProfile().accepts(normalized)
    }
}
