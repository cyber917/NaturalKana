import Foundation
import NaturalLanguage

public enum SuggestionLanguage: String, Codable, CaseIterable, Sendable {
    case japanese, english

    public var title: String { self == .japanese ? "日语" : "英语" }
    public var promptName: String { self == .japanese ? "Japanese" : "English" }
    public var testDraft: String {
        self == .japanese ? "今日は仕事があるから、少し待ってください。" : "I have work to do, please wait me a moment."
    }
    public var draftProfile: any LanguageProfile {
        switch self {
        case .japanese: JapaneseDraftProfile()
        case .english: EnglishDraftProfile()
        }
    }
    public func acceptsCandidate(_ text: String, original: String) -> Bool {
        switch self {
        case .japanese:
            let originalLatin = Set(JapaneseProfile.latinWords(original))
            return JapaneseProfile().accepts(text) && JapaneseProfile.latinWords(text).allSatisfy(originalLatin.contains)
        case .english:
            return EnglishProfile().accepts(text)
        }
    }
    public func registerTitle(_ register: Register) -> String {
        switch (self, register) {
        case (.japanese, .casual): "カジュアル"
        case (.japanese, .polite): "丁寧"
        case (.english, .casual): "Casual"
        case (.english, .polite): "Polite"
        case (_, .kansai): Dialect.kansai.title
        }
    }
    public var closeTitle: String { self == .japanese ? "閉じる" : "Close" }
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
